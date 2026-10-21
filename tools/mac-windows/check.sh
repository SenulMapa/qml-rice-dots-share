#!/usr/bin/env bash
# Layer 4 check: Lua syntax + required keys + wiring. Exit 0 = pass. Touches nothing.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
M="$REPO/hypr/hyprland/mac.lua"
fail=0
bad() { echo "FAIL: $*"; fail=1; }
if command -v luac >/dev/null; then luac -p "$M" "$REPO/hypr/hyprland.lua" || bad "lua syntax"
else lua - "$M" <<'LUA' || bad "lua syntax"
assert(loadfile(arg[1]))
LUA
fi
for k in 'layout = "master"' 'mfact = 0.62' 'orientation = "left"' 'new_status = "slave"' 'rounding = 11' \
         'color_inactive' 'windowsIn' 'windowsOut' 'workspaces' 'specialWorkspaceIn' \
         'SUPER + CTRL + M' 'special:minimized' 'hyprbars' 'hyprbars:no_bar' 'FF5F57' 'FEBC2E' '28C840' \
         'bar_height = 28' 'bar_buttons_alignment = "left"' 'size = 12' 'bar_button_padding = 8' \
         'bar_text_size = 13' 'semibold' 'system-ui' 'border_size = 0'; do
    grep -qF -- "$k" "$M" || grep -qF -- "$k" "$REPO/hypr/hyprland/scripts/mac-minimize.sh" || bad "missing: $k"
done
grep -qF 'require("hyprland.mac")' "$REPO/hypr/hyprland.lua" || bad "hyprland.lua does not load mac"
awk '/hyprland.glass/{g=NR} /hyprland.mac/{m=NR} END{exit !(g&&m&&m>g)}' "$REPO/hypr/hyprland.lua" || bad "mac must load after glass"
for s in mac-minimize.sh mac-restore.sh; do bash -n "$REPO/hypr/hyprland/scripts/$s" || bad "$s syntax"; done
# plugin-absent safety: hl stub where hl.plugin errors -> file must load
lua - "$M" <<'LUA' || bad "mac.lua fails with plugin absent"
local noop=function() end
hl=setmetatable({config=noop,curve=noop,animation=noop,bind=noop,unbind=noop,on=noop,exec_cmd=noop,workspace_rule=noop,window_rule=noop,
 dsp={exec_cmd=noop,layout=noop},plugin=setmetatable({}, {__index=function() error("no plugin") end})},{})
assert(loadfile(arg[1]))()
LUA
[ "$fail" = 0 ] && echo "check ok"
exit $fail
