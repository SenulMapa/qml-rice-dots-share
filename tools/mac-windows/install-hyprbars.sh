#!/usr/bin/env bash
# OWNER-RUN. Builds + enables the hyprbars plugin (traffic lights) via hyprpm.
# Not run by apply.sh: it compiles C++ against the Hyprland headers, writes
# ~/.local/share/hyprpm and (on first run) may prompt for sudo to read headers.
# Needs: git cmake meson ninja g++ pkg-config and the hyprland headers
# (/usr/include/hyprland, shipped by the hyprland package).
set -euo pipefail
command -v hyprpm >/dev/null || { echo "hyprpm not found (it ships with the hyprland package)"; exit 1; }
[ -d /usr/include/hyprland ] || { echo "Hyprland headers missing: reinstall the hyprland package"; exit 1; }

hyprpm update                                        # builds headers for the RUNNING version (0.56.2)
hyprpm add https://github.com/hyprwm/hyprland-plugins   # answers y to the build prompt
hyprpm enable hyprbars
hyprpm reload -n                                     # loads it now; plugin triggers a config reload,
                                                     # which re-runs mac.lua and adds the bars
hyprpm list
echo "Done. Verify: hyprctl plugin list   (should show hyprbars)"
echo "Disable: hyprpm disable hyprbars && hyprpm reload -n"
