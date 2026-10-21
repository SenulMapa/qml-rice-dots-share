#!/usr/bin/env bash
# revert.sh -- undo an apply.sh run exactly, from its backup.
#
#   tools/mac-theme/revert.sh [STAMP]    # default: the newest un-reverted backup
#
# Created files/dirs are removed, edited ones copied back, gsettings values restored.
# The backup is renamed <stamp>.reverted, so a second revert takes the next older one.
set -euo pipefail

H="${HOME:?HOME must be set}"
STATE="$H/.local/state/qml-rice/mac-theme"
if [ "$#" -ge 1 ]; then
    case "$1" in -h|--help) sed -n '2,7p' "$0"; exit 0 ;; esac
    STAMP="$1"
else
    STAMP=$(ls -1 "$STATE" 2>/dev/null | grep -v '\.reverted' | sort | tail -n 1 || true)
    [ -n "$STAMP" ] || { echo "revert: no un-reverted backup under $STATE" >&2; exit 1; }
fi
BK="$STATE/$STAMP"
MANIFEST="$BK/manifest.tsv"
[ -f "$MANIFEST" ] || { echo "revert: no manifest at $MANIFEST" >&2; exit 1; }

echo "mac-theme: reverting $STAMP"
mapfile -t LINES < <(grep -v '^#' "$MANIFEST" | tac)
for line in "${LINES[@]}"; do
    [ -n "$line" ] || continue
    IFS=$'\t' read -r kind type a b <<< "$line"
    case "$kind" in
        keep)
            rm -rf "$a"
            mkdir -p "$(dirname "$a")"
            cp -a "$BK/files/$a" "$a"
            echo "  restored ${a#"$H"/}" ;;
        absent) rm -rf "$a"; echo "  removed ${a#"$H"/}" ;;
        mkdir) rmdir "$a" 2>/dev/null || true ;;
        gsettings)
            # type=schema a=key b=old GVariant text (read keeps the tail intact)
            gsettings set "$type" "$a" "$b"
            echo "  gsettings $a = $b" ;;
        *) echo "revert: unknown manifest line: $line" >&2; exit 1 ;;
    esac
done
mv "$BK" "$STATE/$STAMP.reverted"
echo "mac-theme: reverted $STAMP (backup kept as $STAMP.reverted)"
