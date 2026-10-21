#!/usr/bin/env bash
# Layer 5 (dock) automated check. Exit 0 = pass. Everything runs offscreen:
# no windows on the live desktop, no input grabbed, no system state toggled.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
fail=0
for t in test-dock-magnify test-dock-model test-dock-surface; do
  out="$(cd "$repo/shell" && QT_QPA_PLATFORM=offscreen timeout 90 qs -p "$t.qml" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
  summary="$(printf '%s\n' "$out" | grep -E '=== [0-9]+/[0-9]+ passed ===' | tail -n1)"
  printf '%-20s %s\n' "$t" "${summary:-NO RESULT}"
  printf '%s\n' "$out" | grep -E 'FAIL ' && fail=1
  [ -n "$summary" ] || fail=1
  n="$(printf '%s' "$summary" | sed -E 's/.*=== ([0-9]+)\/([0-9]+) passed.*/\1 \2/')"
  set -- $n
  [ "${1:-0}" = "${2:-1}" ] || fail=1
done
# render harness must load and write frames (into a temp dir)
rd="$(mktemp -d)"
(cd "$repo/shell" && DOCK_RENDER_OUT="$rd" QT_QPA_PLATFORM=offscreen timeout 90 qs -p render-dock.qml >/dev/null 2>&1)
frames="$(ls "$rd"/*.png 2>/dev/null | wc -l)"
printf '%-20s %s frames\n' render-dock "$frames"
[ "$frames" -ge 10 ] || fail=1
rm -rf "$rd"
# capture tooling
python3 -I "$here/analyze_capture.py" --selftest || fail=1
python3 -I "$here/apply-metrics.py" --selftest || fail=1
# the rule block must be in the repo glass.lua
grep -qx -- '-- mac-dock:begin' "$repo/hypr/hyprland/glass.lua" || { echo "glass.lua block missing"; fail=1; }
[ "$fail" = 0 ] && echo "dock check: PASS" || echo "dock check: FAIL"
exit "$fail"
