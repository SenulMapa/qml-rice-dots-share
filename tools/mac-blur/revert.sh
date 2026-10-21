#!/usr/bin/env bash
# Restore exactly from an apply.sh backup. Usage: revert.sh [stamp]  (default: latest)
set -euo pipefail
B="${HOME}/.local/state/qml-rice/mac-blur/${1:-latest}"
[ -f "$B/manifest" ] || { echo "no backup at $B"; exit 1; }
while IFS=$'\t' read -r st f; do
    if [ "$st" = existed ]; then cp -p "$B/files$f" "$f"; else rm -f "$f"; fi
done < "$B/manifest"
echo "reverted from $B. Not reloaded. Orchestrator: hyprctl reload ; pkill -USR1 kitty"
