#!/bin/bash
# Apply Layer 1 text settings to the LIVE session files without overwriting drifted configs.
# Backs up every touched file (or records that it did not exist) into
# ~/.local/state/qml-rice/mac-text/<stamp>/ first. Idempotent. revert.sh undoes it.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
ST="$HOME/.local/state/qml-rice/mac-text/$(date +%Y%m%d-%H%M%S-%N)"; mkdir -p "$ST/files"  # %N: two applies in one second must not share a backup
FC="$HOME/.config/fontconfig/conf.d/60-qml-rice-mac-text.conf"
F=( "$HOME/.config/hypr/hyprland/env.lua" "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"
    "$HOME/.config/qt6ct/qt6ct.conf" "$HOME/.config/kdeglobals" "$FC" )
: > "$ST/absent"
for f in "${F[@]}"; do
  if [ -f "$f" ]; then mkdir -p "$ST/files$(dirname "${f#$HOME}")"; cp -a "$f" "$ST/files${f#$HOME}"
  else echo "${f#$HOME}" >> "$ST/absent"; fi
done
gsettings get org.gnome.desktop.interface font-name > "$ST/gsettings-font-name"
gsettings get org.gnome.desktop.interface font-antialiasing > "$ST/gsettings-font-antialiasing"
gsettings get org.gnome.desktop.interface font-hinting > "$ST/gsettings-font-hinting"
echo "backup: $ST"
# fontconfig drop-in
install -D -m644 "$REPO/dots/fontconfig/.config/fontconfig/conf.d/60-qml-rice-mac-text.conf" "$FC"
# FreeType stem darkening (once)
E="$HOME/.config/hypr/hyprland/env.lua"
if ! grep -q FREETYPE_PROPERTIES "$E"; then
  if [ -s "$E" ] && [ "$(tail -c1 "$E" | od -An -c | tr -d ' ')" != '\n' ]; then echo >> "$E"; fi
  printf '%s\n' 'hl.env("FREETYPE_PROPERTIES", "cff:no-stem-darkening=0 autofitter:no-stem-darkening=0")' >> "$E"
fi
# GTK keys: replace if present, else append under [Settings] (create the section if missing)
setini() { local f=$1 k=$2 v=$3; mkdir -p "$(dirname "$f")"; [ -f "$f" ] || : > "$f"
  grep -q '^\[Settings\]' "$f" || sed -i '1i [Settings]' "$f"
  if grep -q "^$k=" "$f"; then sed -i "s|^$k=.*|$k=$v|" "$f"; else sed -i "/^\[Settings\]/a $k=$v" "$f"; fi; }
for g in gtk-3.0 gtk-4.0; do setini "$HOME/.config/$g/settings.ini" gtk-font-name "system-ui 11"; done
setini "$HOME/.config/gtk-3.0/settings.ini" gtk-xft-rgba none
setini "$HOME/.config/gtk-3.0/settings.ini" gtk-xft-hintstyle hintslight
gsettings set org.gnome.desktop.interface font-name 'system-ui 11'
gsettings set org.gnome.desktop.interface font-antialiasing 'grayscale'
gsettings set org.gnome.desktop.interface font-hinting 'slight'
# Qt (both paths: kde platform theme reads kdeglobals; qt6ct reads its own)
kwriteconfig6 --file kdeglobals --group General --key font "system-ui,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
kwriteconfig6 --file kdeglobals --group General --key menuFont "system-ui,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
Q="$HOME/.config/qt6ct/qt6ct.conf"
if [ -f "$Q" ]; then
  if grep -q '^general=' "$Q"; then sed -i 's|^general=.*|general="system-ui,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"|' "$Q"
  elif grep -q '^\[Fonts\]' "$Q"; then sed -i '/^\[Fonts\]/a general="system-ui,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"' "$Q"
  else printf '\n[Fonts]\ngeneral="system-ui,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"\n' >> "$Q"; fi
fi
fc-cache -f >/dev/null 2>&1 || true
echo "applied. New apps pick it up now; log out and back in for FREETYPE_PROPERTIES."
