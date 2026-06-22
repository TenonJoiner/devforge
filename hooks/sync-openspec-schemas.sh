#!/usr/bin/env bash
# Sync DevForge openspec schemas from plugin bundle to user-level OpenSpec data directory.
# Resolution order matches OpenSpec's own global data dir logic:
#   1. $XDG_DATA_HOME/openspec/schemas/ (if XDG_DATA_HOME is set)
#   2. ~/.local/share/openspec/schemas/  (Unix/macOS default)

set -euo pipefail

plugin_root="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$plugin_root" ]; then
  echo '{"priority": "ERROR", "message": "sync-openspec-schemas: CLAUDE_PLUGIN_ROOT is not set"}' >&2
  exit 1
fi

source_dir="$plugin_root/openspec-schema/schemas"
if [ ! -d "$source_dir" ]; then
  echo '{"priority": "INFO", "message": "sync-openspec-schemas: no openspec-schema directory in plugin, skipping"}'
  exit 0
fi

if [ -n "${XDG_DATA_HOME:-}" ]; then
  target_dir="$XDG_DATA_HOME/openspec/schemas"
else
  target_dir="$HOME/.local/share/openspec/schemas"
fi

mkdir -p "$target_dir"

shopt -s nullglob
entries=("$source_dir"/*)
if [ ${#entries[@]} -eq 0 ]; then
  echo '{"priority": "INFO", "message": "sync-openspec-schemas: source schema directory is empty, skipping"}'
  exit 0
fi

if cp -R "${entries[@]}" "$target_dir"/; then
  echo '{"priority": "INFO", "message": "sync-openspec-schemas: synced openspec schemas to user data directory"}'
else
  echo '{"priority": "ERROR", "message": "sync-openspec-schemas: failed to copy schemas to user data directory"}' >&2
  exit 1
fi
