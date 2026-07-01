#!/bin/bash
# Trace collector — 同时注册为 PreToolUse 和 PostToolUse
# PreToolUse:  写入 tool_intent 事件（用于检测 hook 阻拦）
# PostToolUse: 写入 tool_call / agent_dispatch / skill_invoke 事件
# 静默运行，开发者零感知

set -e

# 找到 Claude 会话锚点 PID：从当前进程向上走，跳过中间 shell 层
# 多会话并发时每个 Claude 进程有独立 PID，避免共享单个 session-id 文件
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
if [ -f "$SESSION_FILE" ]; then
    SESSION_ID=$(cat "$SESSION_FILE")
else
    REPO_NAME="unknown"
	    if command -v git >/dev/null 2>&1; then
	        REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
	        if [ -n "$REMOTE_URL" ]; then
	            REPO_NAME=$(echo "$REMOTE_URL" | sed 's|.*/||; s|\.git$||')
	        else
	            REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
	        fi
	    fi
	    USER_NAME="${USER:-unknown}"
	    SESSION_ID="$(date +%Y%m%d-%H%M%S)-${USER_NAME}-${REPO_NAME}-$$"
    echo "$SESSION_ID" > "$SESSION_FILE"
fi

TRACE_FILE="/tmp/devforge-trace-${SESSION_ID}.jsonl"
SEQ_FILE="/tmp/devforge-trace-seq-${SESSION_ID}"

python3 -c '
import json, sys, time, os

data = json.loads(sys.stdin.read())
tool_name = data.get("tool_name", "")
tool_input = data.get("tool_input", {}) or {}
tool_response = data.get("tool_response", {}) or {}
trace_file = sys.argv[2]
seq_file = sys.argv[3]

# 判断 hook 阶段：有 tool_response → PostToolUse，否则 → PreToolUse
is_post = data.get("hook_event") == "PostToolUse" or bool(tool_response)
# Skill 和 Agent 在 PreToolUse 阶段也只有 tool_input，但我们不需要 intent
# 只对普通工具调用记录 intent（Skill/Agent 本身就是调度事件）

# === 维护事件序号 ===
seq = 1
if os.path.exists(seq_file):
    try:
        with open(seq_file) as f:
            seq = int(f.read().strip()) + 1
    except Exception:
        seq = 1
with open(seq_file, "w") as f:
    f.write(str(seq))

# === 输入摘要 ===
input_summary = ""
if tool_name == "Bash":
    input_summary = (tool_input.get("command", "") or tool_input.get("description", "") or "")[:120]
elif tool_name == "Agent":
    input_summary = (tool_input.get("description", "") or tool_input.get("prompt", "") or "")[:120]
elif tool_name == "Skill":
    input_summary = (tool_input.get("skill", "") or tool_input.get("args", "") or "")[:120]
elif tool_name in ("Read", "Write", "Edit", "MultiEdit", "NotebookEdit"):
    input_summary = (tool_input.get("file_path", "") or "")[:120]
elif tool_name in ("Grep", "Glob"):
    input_summary = (tool_input.get("pattern", "") or "")[:120]

# === PreToolUse: 记录 tool_intent（仅普通工具，不含 Skill/Agent） ===
if not is_post and tool_name not in ("Skill", "Agent"):
    intent_event = {
        "seq": seq,
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "session": sys.argv[1],
        "type": "tool_intent",
        "tool": tool_name,
        "input_summary": input_summary,
    }
    line = json.dumps(intent_event, ensure_ascii=False)
    with open(trace_file, "a") as f:
        f.write(line + "\n")
    sys.exit(0)

# === PostToolUse: 记录完成事件 ===
if not is_post:
    sys.exit(0)

# 获取活跃 skill：读取 trace 文件最后 50 行，查找最近一次 skill_invoke
active_skill = ""
try:
    if os.path.exists(trace_file):
        with open(trace_file) as f:
            lines = f.readlines()
            for line in reversed(lines[-50:]):
                line = line.strip()
                if not line:
                    continue
                try:
                    e = json.loads(line)
                    if e.get("type") == "skill_invoke":
                        active_skill = e.get("input_summary", "").split()[0] or ""
                        break
                except Exception:
                    continue
except Exception:
    pass

# === 事件类型 ===
if tool_name == "Agent":
    event_type = "agent_dispatch"
elif tool_name == "Skill":
    event_type = "skill_invoke"
else:
    event_type = "tool_call"

# === 结果摘要 ===
result = {"status": "success"}
exit_code = None
if isinstance(tool_response, dict):
    exit_code = tool_response.get("exit_code")
    if exit_code is not None and exit_code != 0:
        result["status"] = "error"
    # 提取错误/输出提示
    stderr = tool_response.get("stderr", "") or ""
    stdout = tool_response.get("stdout", "") or ""
    error_msg = tool_response.get("error", "") or tool_response.get("message", "") or ""
    hint = (stderr or error_msg or stdout)[:100]
    if hint:
        result["hint"] = hint
    # 结果规模
    result_text = tool_response.get("content", "") or tool_response.get("text", "") or stdout
    result["size"] = len(result_text)

# 提取耗时
duration_ms = 0
if isinstance(tool_response, dict):
    duration_ms = tool_response.get("duration_ms", 0) or tool_response.get("duration", 0) or 0

# 提取 agent 子类型
agent_subtype = ""
if tool_name == "Agent":
    agent_subtype = tool_input.get("subagent_type", "") or ""

event = {
    "seq": seq,
    "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
    "session": sys.argv[1],
    "type": event_type,
    "tool": tool_name,
    "active_skill": active_skill,
    "input_summary": input_summary,
    "duration_ms": duration_ms,
    "result": result,
}
if exit_code is not None:
    event["exit_code"] = exit_code
if agent_subtype:
    event["agent_subtype"] = agent_subtype

line = json.dumps(event, ensure_ascii=False)
with open(trace_file, "a") as f:
    f.write(line + "\n")
' "$SESSION_ID" "$TRACE_FILE" "$SEQ_FILE"

exit 0
