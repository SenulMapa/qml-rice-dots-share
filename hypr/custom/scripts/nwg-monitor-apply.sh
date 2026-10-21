#!/usr/bin/env bash
# nwg-displays only saves monitors.lua and waits for Hyprland to auto-reload,
# but on the Lua config a reload does not re-apply monitor rules to outputs
# that are already connected. Evaluate the file directly whenever it changes.
# hyprctl dispatch wraps the expression in hl.dispatch(), so the chunk returns a
# no-op dispatcher; a bare dofile() works too but leaves a config error banner.
dir="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
pkill -f -o "inotifywait -m -q -e close_write,moved_to $dir" 2>/dev/null
inotifywait -m -q -e close_write,moved_to "$dir" --format '%f' | while read -r file; do
    if [ "$file" = "monitors.lua" ]; then
        sleep 0.3
        hyprctl dispatch "(function() dofile(\"$dir/monitors.lua\"); return hl.dsp.exec_cmd(\"true\") end)()" >/dev/null 2>&1
    fi
done
