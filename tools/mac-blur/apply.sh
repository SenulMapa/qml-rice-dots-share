#!/usr/bin/env bash
# Apply vibrancy blur to the LIVE config. Targeted + idempotent; backs up first.
#  1. live hyprland/mac.lua: replace/append the mac-blur:begin..end block from the repo
#  2. live hyprland/rules.lua: delete the blanket `class ".*" ... no_blur = true` line
#  3. live kitty.conf: background_opacity -> 0.85
# Never reloads Hyprland, never signals kitty.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CFG="${HOME}/.config/hypr"; KC="${HOME}/.config/kitty/kitty.conf"
STATE="${HOME}/.local/state/qml-rice/mac-blur"; STAMP="$(date +%Y%m%d-%H%M%S)"; B="$STATE/$STAMP"
SRC="$REPO/hypr/hyprland/mac.lua"; MAC="$CFG/hyprland/mac.lua"; RULES="$CFG/hyprland/rules.lua"
[ -f "$MAC" ] || { echo "no $MAC; apply tools/mac-windows first"; exit 1; }
BLOCK="$(mktemp)"; trap 'rm -f "$BLOCK"' EXIT
awk '/-- mac-blur:begin/{p=1} p{print} /-- mac-blur:end/{p=0}' "$SRC" > "$BLOCK"
[ -s "$BLOCK" ] || { echo "block missing in repo mac.lua"; exit 1; }

newmac="$(mktemp)"
if grep -qF 'mac-blur:begin' "$MAC"; then
    awk -v bf="$BLOCK" '/-- mac-blur:begin/{while((getline l < bf)>0) print l; skip=1; next} /-- mac-blur:end/{skip=0; next} !skip{print}' "$MAC" > "$newmac"
else { cat "$MAC"; echo; cat "$BLOCK"; } > "$newmac"; fi
BL='^[[:space:]]*hl\.window_rule\(\{[[:space:]]*match[[:space:]]*=[[:space:]]*\{[[:space:]]*class[[:space:]]*=[[:space:]]*"\.\*"[[:space:]]*\},[[:space:]]*no_blur[[:space:]]*=[[:space:]]*true'
newrules="$(mktemp)"
if [ -f "$RULES" ]; then grep -vE "$BL" "$RULES" > "$newrules" || true; fi
newkitty="$(mktemp)"
if [ -f "$KC" ]; then
    if grep -qE '^background_opacity ' "$KC"; then sed -E 's/^background_opacity .*/background_opacity 0.85/' "$KC" > "$newkitty"
    else { cat "$KC"; echo "background_opacity 0.85"; } > "$newkitty"; fi
fi
need=0
cmp -s "$newmac" "$MAC" || need=1
[ -f "$RULES" ] && ! cmp -s "$newrules" "$RULES" && need=1
[ -f "$KC" ] && ! cmp -s "$newkitty" "$KC" && need=1
if [ "$need" = 0 ]; then echo "already applied; nothing to do"; rm -f "$newmac" "$newrules" "$newkitty"; exit 0; fi

mkdir -p "$B/files"; : > "$B/manifest"   # "existed|absent<TAB>abs path"
for f in "$MAC" "$RULES" "$KC"; do
    if [ -e "$f" ]; then mkdir -p "$B/files$(dirname "$f")"; cp -p "$f" "$B/files$f"; printf 'existed\t%s\n' "$f" >> "$B/manifest"
    else printf 'absent\t%s\n' "$f" >> "$B/manifest"; fi
done
ln -sfn "$B" "$STATE/latest"
cat "$newmac" > "$MAC"
[ -f "$RULES" ] && cat "$newrules" > "$RULES"
[ -f "$KC" ] && cat "$newkitty" > "$KC"
rm -f "$newmac" "$newrules" "$newkitty"
echo "applied. backup: $B"
echo "Not reloaded. Orchestrator: run   hyprctl reload"
echo "Kitty (not signalled): pkill -USR1 kitty   (reloads config in all kitty windows)"
