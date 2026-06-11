#!/bin/bash
# PreToolUse Hook: Pre-commit security gate
# 仅拦截硬编码密钥泄露——其他质量检查由 /df:lint 或 code-reviewer 覆盖

set -e

# 从 stdin 读取 hook 上下文，仅对 git commit 命令执行
PY_SCRIPT='
import json, sys, shlex

try:
    data = json.load(sys.stdin)
    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input", {}) or {}
    command = tool_input.get("command", "")

    if tool_name != "Bash":
        print("SKIP")
        sys.exit(0)

    parts = shlex.split(command) if command else []
    if len(parts) < 2 or parts[0] != "git" or parts[1] != "commit":
        print("SKIP")
        sys.exit(0)

    print("RUN")
except Exception:
    print("SKIP")
'

RESULT=$(python3 -c "$PY_SCRIPT" 2>/dev/null || echo "SKIP")
[ "$RESULT" = "SKIP" ] && exit 0

STAGED=$(git diff --cached --name-only --diff-filter=ACM || true)
[ -z "$STAGED" ] && exit 0

ERRORS=0

echo "[pre-commit] 安全扫描..."

# 检测硬编码密钥
SECRET_ISSUES=$(echo "$STAGED" | while read -r f; do
    [ -f "$f" ] || continue
    git check-ignore -q "$f" 2>/dev/null && continue
    grep -nH -E 'sk-[a-zA-Z0-9]{20,}' "$f" 2>/dev/null || true
    grep -nH -E 'ghp_[a-zA-Z0-9]{36}' "$f" 2>/dev/null || true
    grep -nH -E 'AKIA[A-Z0-9]{16}' "$f" 2>/dev/null || true
    if [[ "$f" != *test* ]] && [[ "$f" != *example* ]]; then
        grep -nH -iE "api[_-]?key\\s*[:=]\\s*[\\\"'][^\\\"']+[\\\"']" "$f" 2>/dev/null || true
    fi
done)

if [ -n "$SECRET_ISSUES" ]; then
    echo "🚫 检测到潜在密钥泄露："
    echo "$SECRET_ISSUES" | head -20
    ERRORS=$((ERRORS + 1))
fi

if [ "$ERRORS" -gt 0 ]; then
    echo ""
    echo "🚫 提交被拦截：发现 $ERRORS 个安全问题，请修复后重试"
    exit 1
fi

echo "✓ 提交前安全检查通过"
exit 0
