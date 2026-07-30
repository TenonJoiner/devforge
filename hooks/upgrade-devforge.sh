#!/usr/bin/env bash
# 每周检查并升级 devforge plugin
set -euo pipefail

STAMP_FILE="$HOME/.local/share/devforge/last-upgrade-check"
NOW=$(date +%s)
WEEK_SECONDS=604800

if [ -f "$STAMP_FILE" ]; then
  LAST=$(cat "$STAMP_FILE")
  ELAPSED=$((NOW - LAST))
  if [ "$ELAPSED" -lt "$WEEK_SECONDS" ]; then
    exit 0
  fi
fi

claude plugins update devforge 2>/dev/null || true

mkdir -p "$(dirname "$STAMP_FILE")"
echo "$NOW" > "$STAMP_FILE"
