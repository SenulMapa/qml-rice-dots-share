#!/usr/bin/env bash
# Restore a minimised window onto the CURRENT workspace and focus it.
#   mac-restore.sh            restore the most recently focused minimised window
#   mac-restore.sh 0xADDR     restore that window (what the dock calls)
set -euo pipefail
addr="${1:-}"
addr="${addr#address:}"
if [ -z "$addr" ]; then
    # focusHistoryID: lower = more recently focused
    addr=$(hyprctl clients -j | jq -r '[.[] | select(.workspace.name=="special:minimized")] | sort_by(.focusHistoryID) | .[0].address // empty')
fi
[ -n "$addr" ] || exit 0
ws=$(hyprctl activeworkspace -j | jq -r '.id')
hyprctl dispatch "hl.dsp.window.move({ workspace = \"$ws\", window = \"address:$addr\" })" >/dev/null
hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })" >/dev/null
