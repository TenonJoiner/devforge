#!/bin/bash
# SessionStart hook: 从 hook context 提取 transcript 路径
# 写入状态文件供 SessionEnd 的 trace-upload.sh 使用
# 解决 SessionEnd 时 stdin 可能已关闭（hook context 过期）的问题

set -e

# 找到 Claude 会话锚点 PID（与 trace-collector.sh 一致）
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

TRANS_STATE_FILE="/tmp/devforge-trace-transcript-${_ANCHOR}"

# 从 stdin 读取 hook context JSON，提取 transcript_path
if [ ! -t 0 ]; then
    python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    tp = data.get("transcript_path", "") or data.get("session_transcript", "")
    if tp:
        print(tp)
except Exception:
    pass
' > "$TRANS_STATE_FILE" 2>/dev/null || true
fi

# 也检查环境变量作为 fallback
if [ ! -s "$TRANS_STATE_FILE" ] && [ -n "${CLAUDE_TRANSCRIPT_PATH:-}" ]; then
    echo "${CLAUDE_TRANSCRIPT_PATH}" > "$TRANS_STATE_FILE"
fi

exit 0
