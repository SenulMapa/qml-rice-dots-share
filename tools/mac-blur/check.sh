#!/usr/bin/env bash
# Vibrancy check: Lua syntax, stub-hl eval, key presence. Exit 0 = pass. Touches nothing.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
M="$REPO/hypr/hyprland/mac.lua"; R="$REPO/hypr/hyprland/rules.lua"; K="$REPO/dots/kitty/.config/kitty/kitty.conf"
fail=0; bad() { echo "FAIL: $*"; fail=1; }
for f in "$M" "$R"; do echo 'assert(loadfile(arg[1]))' | lua - "$f" || bad "lua syntax $f"; done
for k in 'mac-blur:begin' 'mac-blur:end' 'vibrancy = 0.45' 'vibrancy_darkness' 'brightness = 1.0' 'contrast = 0.74' 'noise = 0.01' \
         'no_blur = false' 'steam_app_' 'gamescope' 'cs2' 'mpv' 'fullscreen = true' '[Pp]icture' 'opacity = "0.94 0.90"' 'BAT0'; do
    grep -qF -- "$k" "$M" || bad "mac.lua missing: $k"
done
grep -qE 'class = "\.\*" *\}, *no_blur = true' "$R" && bad "rules.lua still has blanket no_blur"
grep -qE '^background_opacity 0\.85$' "$K" || bad "kitty background_opacity != 0.85"
grep -qF 'blurContrast: 0.74' "$REPO/shell/services/AdaptiveColor.qml" || bad "AdaptiveColor contrast out of sync"
# stub eval: record rules/config; no_blur=false must precede opt-outs
lua - "$M" <<'LUA' || bad "stub eval of mac.lua"
local noop=function() end
local order, blur = {}, nil
hl=setmetatable({config=function(t) if t.decoration and t.decoration.blur then blur=t.decoration.blur end end,
 curve=noop,animation=noop,bind=noop,unbind=noop,on=noop,exec_cmd=noop,workspace_rule=noop,
 window_rule=function(r) order[#order+1]=r end,
 dsp={exec_cmd=noop,layout=noop},plugin=setmetatable({}, {__index=function() error("no plugin") end})},{})
assert(loadfile(arg[1]))()
assert(blur and blur.vibrancy==0.45 and blur.passes>=2, "blur cfg")
local first, optout
for i,r in ipairs(order) do
  if r.no_blur==false then first=first or i end
  if r.no_blur==true and r.match.fullscreen then optout=i end
end
assert(first and optout and first<optout, "no_blur=false must come before opt-outs")
LUA
[ "$fail" = 0 ] && echo "check ok"
exit $fail
