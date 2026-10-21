#!/usr/bin/env bash
# Screenshot every panel inside a NESTED compositor, so verification never
# touches the real session (and never captures the user's screen).
set -uo pipefail
cd "$(dirname "$0")"
NESTED_DISPLAY="${NESTED_DISPLAY:-wayland-2}"
OUT="${1:-/tmp/qa}"
mkdir -p "$OUT"
shot() { WAYLAND_DISPLAY="$NESTED_DISPLAY" grim "$OUT/$1.png" 2>/dev/null && echo "  captured $1"; }
ipc()  { qs -p ./shell.qml ipc call $1 >/dev/null 2>&1; }

shot 00-rest
for p in "control-center open:control-center" \
         "launcher open:launcher" \
         "notifications open:notifications" \
         "clipboard open:clipboard" \
         "session-page open:power" \
         "settings open:settings" \
         "settings dashboard:dashboard" \
         "settings wallpaper:wallpaper" \
         "settings media:media"; do
  call="${p%%:*}"; name="${p##*:}"
  ipc "$call"; sleep 1.2; shot "$name"
  ipc "${call%% *} close"; sleep 0.6
done
echo "-> $OUT"
