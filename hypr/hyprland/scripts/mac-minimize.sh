#!/usr/bin/env bash
# Minimise the active window (or address:0x... given as $1): park it silently on
# the special:minimized workspace. Contract shared with the dock (Layer 5):
# a window is "minimised" iff its workspace name is special:minimized.
set -euo pipefail
target="${1:-}"
if [ -z "$target" ]; then
    addr=$(hyprctl activewindow -j | jq -r '.address // empty')
    [ -n "$addr" ] || exit 0
    target="address:$addr"
fi
hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:minimized\", follow = false, window = \"$target\" })" >/dev/null
