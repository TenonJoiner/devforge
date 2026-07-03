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
    c|h|cpp|cc|cxx|hpp|hh|go|py|js|ts|jsx|tsx|json|jsonc|md) ;;
    *) exit 0 ;;
esac

# 按文件类型调用对应 formatter
# - 有 config 但工具不可用 → 硬失败（项目已声明要格式化，环境必须满足）
# - 无 config → 静默跳过（项目未接入格式化）
# - 工具执行失败 → 静默跳过（可能是 WIP 代码语法不完整）
case "$ext" in
    c|h|cpp|cc|cxx|hpp|hh)
        if [ -f ".clang-format" ] || [ -f "_clang-format" ]; then
            if ! command -v clang-format >/dev/null 2>&1; then
                echo "[format] clang-format 未安装，但项目已配置 .clang-format" >&2
                exit 1
            fi
            clang-format -i "$FILE" 2>/dev/null || true
        fi
        ;;
    go)
        gofmt -w "$FILE" 2>/dev/null || true
        ;;
    py)
        black "$FILE" 2>/dev/null || true
        ;;
    js|ts|jsx|tsx|json|jsonc|md)
        if [ -f "biome.json" ] || [ -f "biome.jsonc" ]; then
            if ! command -v biome >/dev/null 2>&1 && [ ! -x "node_modules/.bin/biome" ]; then
                echo "[format] biome 未安装，但项目已配置 biome" >&2
                exit 1
            fi
            npx biome check --write "$FILE" 2>/dev/null || true
        elif [ "$ext" = "js" ] || [ "$ext" = "ts" ] || [ "$ext" = "jsx" ] || [ "$ext" = "tsx" ]; then
            if [ -f ".prettierrc" ] || [ -f ".prettierrc.json" ] || [ -f ".prettierrc.js" ]; then
                if ! command -v prettier >/dev/null 2>&1 && [ ! -x "node_modules/.bin/prettier" ]; then
                    echo "[format] prettier 未安装，但项目已配置 prettier" >&2
                    exit 1
                fi
                npx prettier --write "$FILE" 2>/dev/null || true
            fi
        fi
        ;;
esac
