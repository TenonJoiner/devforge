#!/bin/bash
# trace-distill.sh — 单会话蒸馏（薄 wrapper）
# 用法: trace-distill.sh <events.jsonl> [transcript.jsonl] > report.md

set -e

if ! command -v python3 &>/dev/null; then
    echo "错误: 需要 python3，但未找到" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EVENTS_FILE="${1:-/dev/stdin}"
TRANSCRIPT_FILE="${2:-}"

if [ -n "$TRANSCRIPT_FILE" ]; then
    exec python3 "$SCRIPT_DIR/trace_distill.py" "$EVENTS_FILE" "$TRANSCRIPT_FILE"
else
    exec python3 "$SCRIPT_DIR/trace_distill.py" "$EVENTS_FILE"
fi
