#!/usr/bin/env bash
# Restore exactly from a backup made by apply.sh. Usage: revert.sh [stamp]  (default: latest)
set -euo pipefail
CFG="${HOME}/.config/hypr"
STATE="${HOME}/.local/state/qml-rice/mac-windows"
B="$STATE/${1:-latest}"
[ -f "$B/manifest" ] || { echo "no backup at $B"; exit 1; }
while IFS=$'\t' read -r st f; do
    if [ "$st" = existed ]; then cp -p "$B/files/$f" "$CFG/$f"; else rm -f "$CFG/$f"; fi
done < "$B/manifest"
echo "reverted from $B. Not reloaded. Orchestrator: run   hyprctl reload"
