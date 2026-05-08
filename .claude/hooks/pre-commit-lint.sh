#!/bin/bash
# PreToolUse Hook: Pre-commit quality gate
# 仅文本模式检查（与 ECC 对齐）——静态分析留给 /df:lint 或 code-reviewer

set -e

STAGED=$(git diff --cached --name-only --diff-filter=ACM || true)
[ -z "$STAGED" ] && exit 0

ERRORS=0

echo "[pre-commit] 文本模式检查..."

# 1.1 检测 TODO/FIXME 无 issue 引用
# 允许格式：TODO(#123)、TODO: #123、FIXME: issue #123
TODO_ISSUES=$(echo "$STAGED" | while read -r f; do
    [ -f "$f" ] || continue
    git check-ignore -q "$f" 2>/dev/null && continue
    grep -nH -E '(TODO|FIXME):?\s*(?!.*#\d+)(?!.*issue)' "$f" 2>/dev/null || true
done)

if [ -n "$TODO_ISSUES" ]; then
    echo "⚠️  TODO/FIXME 未关联 issue："
    echo "$TODO_ISSUES" | head -20
    echo ""
fi

# 1.2 检测 console.log / debugger（JS/TS）
JS_TS_FILES=$(echo "$STAGED" | grep -E '\.(js|ts|jsx|tsx)$' || true)
if [ -n "$JS_TS_FILES" ]; then
    DEBUG_ISSUES=$(echo "$JS_TS_FILES" | while read -r f; do
        [ -f "$f" ] || continue
        grep -nH -E '\bconsole\.log\b|\bdebugger\b' "$f" 2>/dev/null || true
    done)
    if [ -n "$DEBUG_ISSUES" ]; then
        echo "⚠️  发现调试代码（console.log / debugger）："
        echo "$DEBUG_ISSUES" | head -20
        echo ""
    fi
fi

# 1.3 检测硬编码密钥
SECRET_ISSUES=$(echo "$STAGED" | while read -r f; do
    [ -f "$f" ] || continue
    git check-ignore -q "$f" 2>/dev/null && continue
    grep -nH -E 'sk-[a-zA-Z0-9]{20,}' "$f" 2>/dev/null || true
    grep -nH -E 'ghp_[a-zA-Z0-9]{36}' "$f" 2>/dev/null || true
    grep -nH -E 'AKIA[A-Z0-9]{16}' "$f" 2>/dev/null || true
    if [[ "$f" != *test* ]] && [[ "$f" != *example* ]]; then
        grep -nH -iE 'api[_-]?key\s*[:=]\s*["'\''][^"'\'']+["'\'']' "$f" 2>/dev/null || true
    fi
done)

if [ -n "$SECRET_ISSUES" ]; then
    echo "🚫 检测到潜在密钥泄露："
    echo "$SECRET_ISSUES" | head -20
    ERRORS=$((ERRORS + 1))
fi

# 1.4 提交信息格式检查
COMMIT_MSG=""
for arg in "$@"; do
    if [[ "$arg" == -m=* ]]; then
        COMMIT_MSG="${arg#-m=}"
    elif [[ "$arg" == --message=* ]]; then
        COMMIT_MSG="${arg#--message=}"
    fi
done

if [ -z "$COMMIT_MSG" ] && [ -f ".git/COMMIT_EDITMSG" ]; then
    COMMIT_MSG=$(head -1 .git/COMMIT_EDITMSG 2>/dev/null || echo "")
fi

if [ -n "$COMMIT_MSG" ]; then
    if ! echo "$COMMIT_MSG" | grep -qE '^(feat|fix|docs|style|refactor|test|chore|build|ci|perf|revert)(\(.+\))?:\s+.+'; then
        echo "🚫 提交信息格式不符合 Conventional Commits"
        echo "   期望格式: type(scope): description"
        ERRORS=$((ERRORS + 1))
    fi

    if [ "${#COMMIT_MSG}" -gt 72 ]; then
        echo "⚠️ 提交信息过长 (${#COMMIT_MSG} > 72 字符)"
    fi

    if echo "$COMMIT_MSG" | grep -qE '[.。]$'; then
        echo "⚠️ 提交信息不应以句号结尾"
    fi
fi

# ── 汇总 ──────────────────────────────────────────────────────

if [ "$ERRORS" -gt 0 ]; then
    echo ""
    echo "🚫 提交被拦截：发现 $ERRORS 个错误，请修复后重试"
    exit 1
fi

echo "✓ 提交前检查通过"
exit 0
