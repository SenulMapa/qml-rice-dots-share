#!/usr/bin/env bash
set -euo pipefail
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"; HYPR="$CFG/hypr"
rm -f "$HYPR/qml-rice-binds.lua" "$HOME/.local/bin/qml-rice"
rm -rf "$HOME/.local/share/fonts/qml-rice"
if [ -f "$HYPR/hyprland.lua" ]; then
  sed -i '/qml-rice-binds/d' "$HYPR/hyprland.lua"
fi
pkill -f "shell.qml" 2>/dev/null || true
echo "qml-rice removed. Backups of hyprland.lua (if any) are kept as *.bak-qml-rice-*"
