#!/bin/bash
# PostToolUse Hook: Auto-format on file edit
# 按文件类型自动探测 formatter 并执行格式化

set -e

# 从 stdin 读取 hook 上下文，获取被编辑文件路径
PY_SCRIPT='
import json, sys
try:
    data = json.load(sys.stdin)
    tool_input = data.get("tool_input", {}) or {}
    tool_response = data.get("tool_response", {}) or {}
    print(tool_input.get("file_path") or tool_response.get("filePath") or "")
except Exception:
    print("")
'

if [ -n "$CLAUDE_EDITED_FILE" ]; then
    FILE="$CLAUDE_EDITED_FILE"
else
    FILE=$(python3 -c "$PY_SCRIPT" 2>/dev/null || echo "")
fi

[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

# 获取文件扩展名
ext="${FILE##*.}"

# 只处理支持格式化的文件类型
case "$ext" in
    c|h|cpp|cc|cxx|hpp|hh|rs|go|py|js|ts|jsx|tsx|json|jsonc|md) ;;
    *) exit 0 ;;
esac

# 按文件类型调用对应 formatter
# 失败时静默退出（不阻塞编辑）
case "$ext" in
    c|h)
        if [ -f ".clang-format" ] || [ -f "_clang-format" ]; then
            clang-format -i "$FILE" 2>/dev/null || true
        fi
        ;;
    cpp|cc|cxx|hpp|hh)
        if [ -f ".clang-format" ] || [ -f "_clang-format" ]; then
            clang-format -i "$FILE" 2>/dev/null || true
        fi
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
