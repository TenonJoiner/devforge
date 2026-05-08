#!/bin/bash
# PostToolUse Hook: Lightweight quality check after file edit
# 非格式化类的轻量检查（JSON/YAML 语法等）

set -e

if [ -n "$CLAUDE_EDITED_FILE" ]; then
    FILE="$CLAUDE_EDITED_FILE"
else
    FILE=$(jq -r '.tool_response.filePath // .tool_input.file_path' 2>/dev/null || echo "")
fi

[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

ext="${FILE##*.}"

# 失败时静默退出（不阻塞编辑）
case "$ext" in
    json|jsonc)
        python3 -m json.tool "$FILE" > /dev/null 2>&1 || true
        ;;
    yaml|yml)
        python3 -c "import yaml; yaml.safe_load(open('$FILE'))" 2>/dev/null || true
        ;;
esac
