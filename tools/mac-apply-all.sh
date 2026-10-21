#!/bin/bash
# Apply every macOS-for-Hyprland layer to the live session (each backs itself up), then reload Hyprland.
# Undo everything: bash tools/mac-revert-all.sh
set -u
cd "$(dirname "$0")/.."
for L in mac-text mac-apps mac-icons mac-theme mac-webapps mac-windows mac-dock mac-blur; do
  echo "=== $L"; bash "tools/$L/apply.sh" 2>&1 | tail -3 || echo "!!! $L apply failed (others continue)"
done
hyprctl reload >/dev/null && echo "Hyprland reloaded (master layout, Mac motion, Gemini Super+Alt+G, minimise Super+Ctrl+M)."
echo "Log out and back in once so the new font rendering, cursor and app flags reach every app."
echo "Traffic lights (optional, may ask for your password): bash tools/mac-windows/install-hyprbars.sh"
