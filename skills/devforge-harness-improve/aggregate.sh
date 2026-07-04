#!/bin/bash
# aggregate.sh — 跨会话聚合（薄 wrapper）
# 用法: aggregate.sh <report_dir> > overview.md

set -e

if ! command -v python3 &>/dev/null; then
    echo "错误: 需要 python3，但未找到" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$SCRIPT_DIR/aggregate.py" "${1:-.}"
