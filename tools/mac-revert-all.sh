#!/bin/bash
# Undo every macOS-for-Hyprland layer (latest backup of each), then reload Hyprland.
set -u
cd "$(dirname "$0")/.."
for L in mac-blur mac-dock mac-windows mac-webapps mac-theme mac-icons mac-apps mac-text; do
  echo "=== $L"; bash "tools/$L/revert.sh" 2>&1 | tail -2
done
hyprctl reload >/dev/null && echo "Hyprland reloaded."
