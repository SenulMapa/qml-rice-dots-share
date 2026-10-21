#!/usr/bin/env bash
# Restore what apply.sh changed. Usage: revert.sh [stamp]
# Default stamp = the OLDEST backup, i.e. the file as it was before the dock
# was ever applied (later backups can hold an already-patched copy).
set -euo pipefail
state="$HOME/.local/state/qml-rice/mac-dock"
stamp="${1:-}"
if [ -z "$stamp" ]; then
  stamp="$(ls -1 "$state" 2>/dev/null | sort | head -n1 || true)"
fi
[ -n "$stamp" ] && [ -d "$state/$stamp" ] || { echo "no backup found in $state" >&2; exit 1; }
dir="$state/$stamp"
target="$(sed -n 's/^target=//p' "$dir/MANIFEST")"
[ -n "$target" ] || { echo "bad MANIFEST in $dir" >&2; exit 1; }
cp -p "$dir/glass.lua" "$target"
echo "restored $target from $dir"
echo "Then: hyprctl reload   (and restart the shell if it should stop drawing the dock: set dock.enabled=false first)"
