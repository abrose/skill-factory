#!/usr/bin/env bash
set -euo pipefail

# Keep a running log of every worktree we've seen.
LOG="$HERDR_PLUGIN_ROOT/seen-worktrees.log"

branch=$(echo "$HERDR_PLUGIN_EVENT_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("data",{}).get("worktree",{}).get("branch","?"))')

echo "$(date -u +%FT%TZ) $branch" >> "$LOG"
echo "worktree created: $branch"
