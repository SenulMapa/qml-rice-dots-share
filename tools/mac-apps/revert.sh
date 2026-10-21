#!/usr/bin/env bash
# revert.sh -- undo an apply.sh run exactly, from its backup.
#
#   tools/mac-apps/revert.sh [STAMP]    # default: the newest un-reverted backup
#
# Files that apply created are removed; files it edited are copied back from the
# backup; the cursor dir and the gsettings value are restored. Each backup is
# renamed <stamp>.reverted afterwards, so a second revert picks the next older one.
set -euo pipefail

H="${HOME:?HOME must be set}"
STATE="$H/.local/state/qml-rice/mac-apps"

if [ "$#" -ge 1 ]; then
    case "$1" in
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    esac
    STAMP="$1"
else
    STAMP=$(ls -1 "$STATE" 2>/dev/null | grep -v '\.reverted' | sort | tail -n 1 || true)
    [ -n "$STAMP" ] || { echo "revert: no un-reverted backup under $STATE" >&2; exit 1; }
fi

BK="$STATE/$STAMP"
MANIFEST="$BK/manifest.tsv"
[ -f "$MANIFEST" ] || { echo "revert: no manifest at $MANIFEST" >&2; exit 1; }

echo "mac-apps: reverting $STAMP"

# Reverse order: a later entry never depends on an earlier one, but undoing in
# reverse is the safe habit for any manifest.
mapfile -t LINES < <(grep -v '^#' "$MANIFEST" | tac)
for line in "${LINES[@]}"; do
    [ -n "$line" ] || continue
    IFS=$'\t' read -r kind type a b c <<< "$line"
    case "$kind" in
        keep)
            if [ "$type" = file ]; then
                mkdir -p "$(dirname "$H/$a")"
                cp -a "$BK/files/$a" "$H/$a"
            else # dir
                rm -rf "$H/$a"
                mkdir -p "$(dirname "$H/$a")"
                cp -a "$BK/files/$a" "$H/$a"
            fi
            echo "  restored $a"
            ;;
        absent)
            rm -rf "$H/$a"
            echo "  removed $a"
            ;;
        mkdir)
            rmdir "$H/$a" 2>/dev/null || true   # only if this run left it empty
            ;;
        gsettings)
            # type=schema, a=key, b=previous value (GVariant text as printed by get)
            gsettings set "$type" "$a" "$b"
            echo "  gsettings $a = $b"
            ;;
        *)
            echo "revert: unknown manifest line: $line" >&2
            exit 1
            ;;
    esac
done

mv "$BK" "$STATE/$STAMP.reverted"
echo "mac-apps: reverted $STAMP (backup kept as $STAMP.reverted)"
