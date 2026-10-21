#!/usr/bin/env bash
# Restores the exact pre-apply state recorded by tools/mac-webapps/apply.sh.
# Usage: revert.sh [stamp]   (default: the newest backup)
set -euo pipefail

STATE_ROOT="$HOME/.local/state/qml-rice/mac-webapps"
STAMP="${1:-}"
if [ -z "$STAMP" ]; then
    STAMP="$(ls -1 "$STATE_ROOT" 2>/dev/null | sort | tail -n 1 || true)"
fi
[ -n "$STAMP" ] || { echo "revert: no backups under $STATE_ROOT" >&2; exit 1; }
BK="$STATE_ROOT/$STAMP"
[ -f "$BK/manifest.tsv" ] || { echo "revert: no manifest at $BK" >&2; exit 1; }

# Undo in reverse order so a file touched twice ends up at its original state.
mapfile -t LINES < "$BK/manifest.tsv"
for ((i = ${#LINES[@]} - 1; i >= 0; i--)); do
    IFS=$'\t' read -r action target saved <<< "${LINES[$i]}"
    case "$action" in
        restore)
            cp -a "$saved" "$target"
            echo "  restored $target"
            ;;
        remove)
            rm -f "$target"
            echo "  removed  $target"
            ;;
        rmdir)
            # Only removes a directory apply created; leaves it alone if something else is in it.
            rmdir "$target" 2>/dev/null || true
            echo "  rmdir    $target (if empty)"
            ;;
        *)
            echo "revert: unknown action '$action'" >&2
            exit 1
            ;;
    esac
done
echo "reverted stamp $STAMP (backup kept at $BK)"
echo "NOTE: Hyprland must reload (hyprctl reload or relogin) to drop the SUPER+ALT+G bind."
