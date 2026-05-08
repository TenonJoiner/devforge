#!/bin/bash
# PostToolUse Hook: Auto-format on file edit
# 按文件类型自动探测 formatter 并执行格式化

set -e

if [ -n "$CLAUDE_EDITED_FILE" ]; then
    FILE="$CLAUDE_EDITED_FILE"
else
    FILE=$(jq -r '.tool_response.filePath // .tool_input.file_path' 2>/dev/null || echo "")
fi

[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

# 获取文件扩展名
ext="${FILE##*.}"

# 按文件类型调用对应 formatter
# 失败时静默退出（不阻塞编辑）
case "$ext" in
    c|h)
        clang-format -i "$FILE" 2>/dev/null || true
        ;;
    cpp|cc|cxx|hpp|hh)
        clang-format -i "$FILE" 2>/dev/null || true
        ;;
    rs)
        rustfmt "$FILE" 2>/dev/null || true
        ;;
    go)
        gofmt -w "$FILE" 2>/dev/null || true
        ;;
    py)
        black "$FILE" 2>/dev/null || true
        ;;
    js|ts|jsx|tsx)
        # 探测项目 formatter：Biome 优先（format + lint 二合一）
        if [ -f "biome.json" ] || [ -f "biome.jsonc" ]; then
            npx biome check --write "$FILE" 2>/dev/null || true
        elif [ -f ".prettierrc" ] || [ -f ".prettierrc.json" ] || [ -f ".prettierrc.js" ]; then
            npx prettier --write "$FILE" 2>/dev/null || true
        fi
        ;;
    json|jsonc)
        if [ -f "biome.json" ] || [ -f "biome.jsonc" ]; then
            npx biome check --write "$FILE" 2>/dev/null || true
        fi
        ;;
    md)
        if [ -f "biome.json" ] || [ -f "biome.jsonc" ]; then
            npx biome check --write "$FILE" 2>/dev/null || true
        fi
        ;;
esac
