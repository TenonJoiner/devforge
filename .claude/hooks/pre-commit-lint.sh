#!/bin/bash
# PreToolUse Hook: Pre-commit quality gate
# 双层检查：Layer 1 文本模式检查 + Layer 2 静态分析

set -e

STAGED=$(git diff --cached --name-only --diff-filter=ACM || true)
[ -z "$STAGED" ] && exit 0

ERRORS=0

# ── Layer 1: 文本模式检查 ─────────────────────────────────────

# 1.1 检测 TODO/FIXME 无 issue 引用
# 允许格式：TODO(#123)、TODO: #123、FIXME: issue #123
echo "[pre-commit] Layer 1: 文本模式检查..."

TODO_ISSUES=$(echo "$STAGED" | while read -r f; do
    [ -f "$f" ] || continue
    # 跳过二进制文件和已忽略文件
    git check-ignore -q "$f" 2>/dev/null && continue
    grep -nH -E '(TODO|FIXME):?\s*(?!.*#\d+)(?!.*issue)' "$f" 2>/dev/null || true
done)

if [ -n "$TODO_ISSUES" ]; then
    echo "⚠️  TODO/FIXME 未关联 issue："
    echo "$TODO_ISSUES" | head -20
    echo ""
fi

# 1.2 检测硬编码密钥（基础模式）
SECRET_ISSUES=$(echo "$STAGED" | while read -r f; do
    [ -f "$f" ] || continue
    git check-ignore -q "$f" 2>/dev/null && continue
    # OpenAI API key
    grep -nH -E 'sk-[a-zA-Z0-9]{20,}' "$f" 2>/dev/null || true
    # GitHub PAT
    grep -nH -E 'ghp_[a-zA-Z0-9]{36}' "$f" 2>/dev/null || true
    # AWS Access Key
    grep -nH -E 'AKIA[A-Z0-9]{16}' "$f" 2>/dev/null || true
    # 通用 api_key 模式（排除测试文件中的示例）
    if [[ "$f" != *test* ]] && [[ "$f" != *example* ]]; then
        grep -nH -iE 'api[_-]?key\s*[:=]\s*["'\''][^"'\'']+["'\'']' "$f" 2>/dev/null || true
    fi
done)

if [ -n "$SECRET_ISSUES" ]; then
    echo "🚫 检测到潜在密钥泄露："
    echo "$SECRET_ISSUES" | head -20
    ERRORS=$((ERRORS + 1))
fi

# 1.3 提交信息格式检查（如果命令行提供了 -m 或 --message）
# 注：此 hook 由 PreToolUse(Bash git commit) 触发，可从环境或 stdin 获取提交信息
COMMIT_MSG=""
for arg in "$@"; do
    if [[ "$arg" == -m=* ]]; then
        COMMIT_MSG="${arg#-m=}"
    elif [[ "$arg" == --message=* ]]; then
        COMMIT_MSG="${arg#--message=}"
    fi
done

# 从 git 的 commit message 文件中读取（如果使用了 git commit 不带 -m）
if [ -z "$COMMIT_MSG" ] && [ -f ".git/COMMIT_EDITMSG" ]; then
    COMMIT_MSG=$(head -1 .git/COMMIT_EDITMSG 2>/dev/null || echo "")
fi

if [ -n "$COMMIT_MSG" ]; then
    # 检查 conventional commit 格式
    if ! echo "$COMMIT_MSG" | grep -qE '^(feat|fix|docs|style|refactor|test|chore|build|ci|perf|revert)(\(.+\))?:\s+.+'; then
        echo "🚫 提交信息格式不符合 Conventional Commits"
        echo "   期望格式: type(scope): description"
        echo "   例如: feat(storage): add write buffer"
        ERRORS=$((ERRORS + 1))
    fi

    # 检查长度
    if [ "${#COMMIT_MSG}" -gt 72 ]; then
        echo "⚠️ 提交信息过长 (${#COMMIT_MSG} > 72 字符)"
    fi

    # 检查尾部标点
    if echo "$COMMIT_MSG" | grep -qE '[.。]$'; then
        echo "⚠️ 提交信息不应以句号结尾"
    fi
fi

# ── Layer 2: 静态分析 ─────────────────────────────────────────

echo "[pre-commit] Layer 2: 静态分析..."

# 按文件类型分组
C_FILES=$(echo "$STAGED" | grep -E '\.(c|h)$' || true)
CPP_FILES=$(echo "$STAGED" | grep -E '\.(cpp|cc|cxx|hpp|hh)$' || true)
RS_FILES=$(echo "$STAGED" | grep -E '\.rs$' || true)
GO_FILES=$(echo "$STAGED" | grep -E '\.go$' || true)
PY_FILES=$(echo "$STAGED" | grep -E '\.py$' || true)
JS_TS_FILES=$(echo "$STAGED" | grep -E '\.(js|ts|jsx|tsx)$' || true)

# C/C++: clang-tidy + cppcheck
if [ -n "$C_FILES" ] || [ -n "$CPP_FILES" ]; then
    ALL_C="$C_FILES $CPP_FILES"

    # clang-tidy
    if command -v clang-tidy &>/dev/null; then
        echo "  运行 clang-tidy..."
        TIDY_CHECKS="bugprone-*,cert-*,clang-analyzer-*,performance-*,readability-*"
        TIDY_OPTS=""

        # 若存在 .clang-tidy 配置文件，使用之
        if [ -f ".clang-tidy" ]; then
            TIDY_CHECKS=""  # 让 clang-tidy 读取配置文件
        fi

        # 若存在 compile_commands.json，使用之
        if [ -f "compile_commands.json" ]; then
            TIDY_OPTS="-p ."
        elif [ -f "build/compile_commands.json" ]; then
            TIDY_OPTS="-p build"
        fi

        if ! clang-tidy $ALL_C -- $TIDY_OPTS 2>/dev/null | grep -q "error:"; then
            echo "    ✓ clang-tidy: 无 error"
        else
            echo "    🚫 clang-tidy 发现 error"
            clang-tidy $ALL_C -- $TIDY_OPTS 2>/dev/null | grep "error:" | head -10
            ERRORS=$((ERRORS + 1))
        fi
    fi

    # cppcheck
    if command -v cppcheck &>/dev/null; then
        echo "  运行 cppcheck..."
        CPPCHECK_OPTS="--enable=all --error-exitcode=1 --suppress=missingIncludeSystem"

        if [ -f "compile_commands.json" ]; then
            CPPCHECK_OPTS="$CPPCHECK_OPTS --project=compile_commands.json"
        fi

        if cppcheck $CPPCHECK_OPTS $ALL_C 2>/dev/null; then
            echo "    ✓ cppcheck: 无 error"
        else
            echo "    🚫 cppcheck 发现问题"
            ERRORS=$((ERRORS + 1))
        fi
    fi
fi

# Rust: cargo clippy
if [ -n "$RS_FILES" ] && [ -f "Cargo.toml" ]; then
    echo "  运行 cargo clippy..."
    if cargo clippy -- -D warnings 2>/dev/null; then
        echo "    ✓ clippy: 无 warning"
    else
        echo "    🚫 clippy 发现问题"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Go: golangci-lint
if [ -n "$GO_FILES" ]; then
    if command -v golangci-lint &>/dev/null; then
        echo "  运行 golangci-lint..."
        if golangci-lint run $GO_FILES 2>/dev/null; then
            echo "    ✓ golangci-lint: 无问题"
        else
            echo "    🚫 golangci-lint 发现问题"
            ERRORS=$((ERRORS + 1))
        fi
    elif command -v go &>/dev/null; then
        echo "  运行 go vet..."
        if go vet $GO_FILES 2>/dev/null; then
            echo "    ✓ go vet: 无问题"
        else
            echo "    🚫 go vet 发现问题"
            ERRORS=$((ERRORS + 1))
        fi
    fi
fi

# Python: ruff / pylint
if [ -n "$PY_FILES" ]; then
    if command -v ruff &>/dev/null; then
        echo "  运行 ruff check..."
        if ruff check $PY_FILES 2>/dev/null; then
            echo "    ✓ ruff: 无问题"
        else
            echo "    🚫 ruff 发现问题"
            ERRORS=$((ERRORS + 1))
        fi
    elif command -v pylint &>/dev/null; then
        echo "  运行 pylint..."
        if pylint $PY_FILES 2>/dev/null; then
            echo "    ✓ pylint: 无问题"
        else
            echo "    🚫 pylint 发现问题"
            ERRORS=$((ERRORS + 1))
        fi
    fi
fi

# JS/TS: biome / eslint
if [ -n "$JS_TS_FILES" ]; then
    if [ -f "biome.json" ] || [ -f "biome.jsonc" ]; then
        echo "  运行 biome check..."
        if npx biome check $JS_TS_FILES 2>/dev/null; then
            echo "    ✓ biome: 无问题"
        else
            echo "    🚫 biome 发现问题"
            ERRORS=$((ERRORS + 1))
        fi
    elif [ -f ".eslintrc" ] || [ -f ".eslintrc.js" ] || [ -f "eslint.config.js" ]; then
        echo "  运行 eslint..."
        if npx eslint $JS_TS_FILES 2>/dev/null; then
            echo "    ✓ eslint: 无问题"
        else
            echo "    🚫 eslint 发现问题"
            ERRORS=$((ERRORS + 1))
        fi
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
