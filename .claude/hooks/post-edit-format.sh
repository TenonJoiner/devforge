#!/bin/bash
if [ -n "$CLAUDE_EDITED_FILE" ]; then
    FILE="$CLAUDE_EDITED_FILE"
else
    FILE=$(jq -r '.tool_response.filePath // .tool_input.file_path')
fi
[ -f "$FILE" ] && clang-format -i "$FILE" 2>/dev/null || true
