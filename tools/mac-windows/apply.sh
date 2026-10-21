#!/usr/bin/env bash
# Apply Layer 4 (mac.lua + minimise scripts) to the live Hyprland config.
# Targeted: copies 3 files, inserts ONE require line into hyprland.lua after
# `require("hyprland.glass")`. Backs up first. Never reloads Hyprland.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CFG="${HOME}/.config/hypr"
STATE="${HOME}/.local/state/qml-rice/mac-windows"
STAMP="$(date +%Y%m%d-%H%M%S)"
B="$STATE/$STAMP"
LINE='require("hyprland.mac")'
ANCHOR='require("hyprland.glass")'
FILES=(hyprland/mac.lua hyprland/scripts/mac-minimize.sh hyprland/scripts/mac-restore.sh)

[ -f "$CFG/hyprland.lua" ] || { echo "no $CFG/hyprland.lua"; exit 1; }
grep -qF "$ANCHOR" "$CFG/hyprland.lua" || { echo "anchor $ANCHOR not found in hyprland.lua; refusing to guess"; exit 1; }

need=0
for f in "${FILES[@]}"; do cmp -s "$REPO/hypr/$f" "$CFG/$f" || need=1; done
grep -qF "$LINE" "$CFG/hyprland.lua" || need=1
if [ "$need" = 0 ]; then echo "already applied; nothing to do"; exit 0; fi

mkdir -p "$B/files"
: > "$B/manifest"   # lines: "existed|absent<TAB>relpath"
for f in "${FILES[@]}" hyprland.lua; do
    if [ -e "$CFG/$f" ]; then
        mkdir -p "$B/files/$(dirname "$f")"; cp -p "$CFG/$f" "$B/files/$f"; printf 'existed\t%s\n' "$f" >> "$B/manifest"
    else
        printf 'absent\t%s\n' "$f" >> "$B/manifest"
    fi
done
ln -sfn "$B" "$STATE/latest"

for f in "${FILES[@]}"; do install -m755 -D "$REPO/hypr/$f" "$CFG/$f"; done
chmod 644 "$CFG/hyprland/mac.lua"
if ! grep -qF "$LINE" "$CFG/hyprland.lua"; then
    tmp="$(mktemp)"
    awk -v a="$ANCHOR" -v l="$LINE" '{print} index($0,a)==1 && !d {print "-- macOS layer 4 (tools/mac-windows); remove this line to disable."; print l; d=1}' "$CFG/hyprland.lua" > "$tmp"
    cat "$tmp" > "$CFG/hyprland.lua"; rm -f "$tmp"
fi
echo "applied. backup: $B"
echo "Not reloaded. Orchestrator: run   hyprctl reload"
