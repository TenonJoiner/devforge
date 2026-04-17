#!/bin/bash
set -e

STAGED=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(c|h)$' || true)
[ -z "$STAGED" ] && exit 0

clang-tidy $STAGED -- -I./include \
  -checks="bugprone-*,cert-*,clang-analyzer-*" 2>&1 | tee /tmp/clang-tidy.log

if grep -q "error:" /tmp/clang-tidy.log; then
    echo "clang-tidy 发现错误，提交被拦截"
    exit 1
fi
