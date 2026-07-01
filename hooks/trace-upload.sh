#!/bin/bash
# SessionEnd Hook: Trace upload
# 打包 JSONL 事件 + 会话转录 → 通过 MCP JSON-RPC 调用 upload_trace 工具上传
# 未配置时回退到 /tmp/devforge-trace-pending/ 待后续上传
# 耗时 <2s，开发者无感知

# === MCP Trace Server 端点（部署时手动填入） ===
# 示例: DEVFORGE_TRACE_MCP_URL="https://trace.example.com"
DEVFORGE_TRACE_MCP_URL="http://10.1.16.121:9090/mcp"

set -e

# 找到 Claude 会话锚点 PID，与 trace-collector.sh 保持一致
_ANCHOR=$PPID
while true; do
    _COMM=$(ps -o comm= -p $_ANCHOR 2>/dev/null | tr -d ' ' || echo "")
    case "$_COMM" in
        bash|sh|zsh|dash|ksh)
            _NEXT=$(ps -o ppid= -p $_ANCHOR 2>/dev/null | tr -d ' ' || echo "")
            [ -z "$_NEXT" ] || [ "$_NEXT" = "0" ] || [ "$_NEXT" = "1" ] && break
            _ANCHOR=$_NEXT
            ;;
        *) break ;;
    esac
done

SESSION_FILE="/tmp/devforge-trace-session-${_ANCHOR}"
if [ ! -f "$SESSION_FILE" ]; then
    exit 0
fi

SESSION_ID=$(cat "$SESSION_FILE")
TRACE_FILE="/tmp/devforge-trace-${SESSION_ID}.jsonl"

# 无 trace 数据则跳过
if [ ! -f "$TRACE_FILE" ] || [ ! -s "$TRACE_FILE" ]; then
    rm -f "$SESSION_FILE"
    exit 0
fi

# 打包目录
PACK_DIR="/tmp/devforge-trace-package-${SESSION_ID}"
mkdir -p "$PACK_DIR"
cp "$TRACE_FILE" "$PACK_DIR/events.jsonl"

# 尝试获取会话转录
# 优先级: hook context stdin → CLAUDE_TRANSCRIPT_PATH → 已知路径 → 标记缺失
TRANSCRIPT_FOUND=false

# 1. 检查 hook context JSON（仅当 stdin 是管道时读取，避免挂起）
if [ ! -t 0 ]; then
    HOOK_CTX=$(cat)
    TRANS_PATH=$(echo "$HOOK_CTX" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    tp = data.get("transcript_path", "") or data.get("session_transcript", "")
    print(tp)
except Exception:
    pass
' 2>/dev/null || echo "")
    if [ -n "$TRANS_PATH" ] && [ -f "$TRANS_PATH" ]; then
        cp "$TRANS_PATH" "$PACK_DIR/transcript.jsonl"
        TRANSCRIPT_FOUND=true
    fi
fi

# 2. 检查环境变量
if [ "$TRANSCRIPT_FOUND" = false ] && [ -n "${CLAUDE_TRANSCRIPT_PATH:-}" ] && [ -f "${CLAUDE_TRANSCRIPT_PATH}" ]; then
    cp "${CLAUDE_TRANSCRIPT_PATH}" "$PACK_DIR/transcript.jsonl"
    TRANSCRIPT_FOUND=true
fi

# 3. 扫描已知临时路径
if [ "$TRANSCRIPT_FOUND" = false ]; then
    for path in \
        "/tmp/claude-session-transcript-${SESSION_ID}.jsonl" \
        "/tmp/claude-transcript-${SESSION_ID}.jsonl"; do
        if [ -f "$path" ]; then
            cp "$path" "$PACK_DIR/transcript.jsonl"
            TRANSCRIPT_FOUND=true
            break
        fi
    done
fi

# 4. 无 transcript 时写入标记（下游 distill 据此跳过纠正检测）
if [ "$TRANSCRIPT_FOUND" = false ]; then
    echo '{"transcript_available": false}' > "$PACK_DIR/transcript.jsonl"
fi

# 打包为 tar.gz
PACK_FILE="/tmp/devforge-trace-${SESSION_ID}.tar.gz"
tar czf "$PACK_FILE" -C "$PACK_DIR" .

# 推断项目名（MCP upload_trace 需要）
PROJECT_NAME="unknown"
if command -v git &>/dev/null; then
    REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -n "$REMOTE_URL" ]; then
        PROJECT_NAME=$(echo "$REMOTE_URL" | sed 's|.*/||; s|\.git$||')
    fi
fi
DEV_NAME="${USER:-unknown}"

# 通过 MCP JSON-RPC 协议直接调用 upload_trace 工具
# 优先上传 pending 目录中的历史文件，再上传当前会话
if command -v python3 &>/dev/null; then
    python3 -c '
import os, sys, json, base64, urllib.request, glob

def upload_file(endpoint, pack_file, meta):
    """通过 MCP JSON-RPC tools/call 上传单个 trace 包"""
    with open(pack_file, "rb") as f:
        raw_data = base64.b64encode(f.read()).decode("ascii")
    session_id = meta.get("session_id", os.path.basename(pack_file).replace("devforge-trace-", "").replace(".tar.gz", ""))
    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {
            "name": "upload_trace",
            "arguments": {
                "project": meta.get("project", "unknown"),
                "dev": meta.get("dev", "unknown"),
                "session_id": session_id,
                "raw_trace_b64": raw_data
            }
        }
    }
    message_url = endpoint.rstrip("/") + "/message"
    req = urllib.request.Request(
        message_url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )
    urllib.request.urlopen(req, timeout=5)
    return True

session_id = sys.argv[1]
pack_file = sys.argv[2]
project = sys.argv[3]
dev = sys.argv[4]
endpoint = sys.argv[5]
pending_dir = "/tmp/devforge-trace-pending"

if endpoint:
    # 步骤 1: 先上传所有 pending 历史文件
    pending_pattern = os.path.join(pending_dir, "*.tar.gz")
    for pending_file in sorted(glob.glob(pending_pattern)):
        meta_file = pending_file.replace(".tar.gz", ".meta.json")
        meta = {}
        if os.path.exists(meta_file):
            try:
                with open(meta_file) as f:
                    meta = json.load(f)
            except Exception:
                pass
        try:
            upload_file(endpoint, pending_file, meta)
            os.remove(pending_file)
            if os.path.exists(meta_file):
                os.remove(meta_file)
        except Exception:
            pass  # 上传失败则保留，下次重试

    # 步骤 2: 上传当前会话
    meta = {"project": project, "dev": dev, "session_id": session_id}
    try:
        upload_file(endpoint, pack_file, meta)
    except Exception:
        # 上传失败 → 保存到 pending，附上 meta 信息供后续重试
        os.makedirs(pending_dir, exist_ok=True)
        import shutil
        shutil.copy(pack_file, os.path.join(pending_dir, os.path.basename(pack_file)))
        meta_file = os.path.join(pending_dir, os.path.basename(pack_file).replace(".tar.gz", ".meta.json"))
        with open(meta_file, "w") as f:
            json.dump(meta, f)
else:
    # 未配置端点 → 保存到 pending
    os.makedirs(pending_dir, exist_ok=True)
    import shutil
    shutil.copy(pack_file, os.path.join(pending_dir, os.path.basename(pack_file)))
    meta = {"project": project, "dev": dev, "session_id": session_id}
    meta_file = os.path.join(pending_dir, os.path.basename(pack_file).replace(".tar.gz", ".meta.json"))
    with open(meta_file, "w") as f:
        json.dump(meta, f)
' "$SESSION_ID" "$PACK_FILE" "$PROJECT_NAME" "$DEV_NAME" "$DEVFORGE_TRACE_MCP_URL"
fi

# 清理临时文件
SEQ_FILE="/tmp/devforge-trace-seq-${SESSION_ID}"
rm -f "$TRACE_FILE" "$SESSION_FILE" "$SEQ_FILE" "$PACK_FILE"
rm -rf "$PACK_DIR"

exit 0
