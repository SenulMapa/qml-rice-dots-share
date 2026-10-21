#!/bin/bash
# tools/mac-text/check.sh — verifies Layer 1 text rendering.
set -u
CONF_DIR=""
[ "${1:-}" = --conf-dir ] && CONF_DIR=$(cd "$2" && pwd)  # absolute: fontconfig resolves includes relative to the temp file
if [ -n "$CONF_DIR" ]; then
  T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
  cat > "$T/fonts.conf" <<XEOF
<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig><include ignore_missing="no">/etc/fonts/fonts.conf</include>
<include ignore_missing="no">$CONF_DIR</include></fontconfig>
XEOF
  export FONTCONFIG_FILE="$T/fonts.conf"
fi
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1: $2"; fail=1; }
ui_re='^(SF Pro|Inter)'
for fam in system-ui -apple-system BlinkMacSystemFont sans-serif; do
  got=$(fc-match -f '%{family[0]}' -- "$fam")
  [[ "$got" =~ $ui_re ]] && ok "alias $fam -> $got" || bad "alias $fam" "got '$got'"
done
got=$(fc-match -f '%{family[0]}' monospace)
[[ "$got" == JetBrains* ]] && ok "monospace -> $got" || bad monospace "got '$got'"
v=$(fc-match -v system-ui)
grep -q 'antialias: True' <<<"$v"   && ok antialias || bad antialias "not True"
grep -q 'hintstyle: 1'    <<<"$v"   && ok hintslight || bad hintstyle "$(grep hintstyle <<<"$v")"
grep -q 'rgba: 5'         <<<"$v"   && ok "rgba none" || bad rgba "$(grep 'rgba:' <<<"$v")"
grep -q 'lcdfilter: 0'    <<<"$v"   && ok "lcdfilter none" || bad lcdfilter "$(grep lcdfilter <<<"$v")"
[ "${CHECK_LIVE:-0}" = 1 ] || exit $fail
# Live-session checks (Task 3 makes these pass)
grep -q 'FREETYPE_PROPERTIES' "$HOME/.config/hypr/hyprland/env.lua" && ok "env FREETYPE_PROPERTIES" || bad env "missing in env.lua"
for f in gtk-3.0 gtk-4.0; do
  grep -q '^gtk-font-name=system-ui 11$' "$HOME/.config/$f/settings.ini" && ok "$f font" || bad "$f font" "not system-ui 11"
done
grep -q '^gtk-xft-rgba=none$' "$HOME/.config/gtk-3.0/settings.ini" && ok "gtk3 rgba" || bad "gtk3 rgba" "not none"
[ "$(gsettings get org.gnome.desktop.interface font-name)" = "'system-ui 11'" ] && ok gsettings || bad gsettings "$(gsettings get org.gnome.desktop.interface font-name)"
grep -q '^font=system-ui,11' "$HOME/.config/kdeglobals" && ok kdeglobals || bad kdeglobals "font not system-ui"
grep -q '^general="system-ui,11' "$HOME/.config/qt6ct/qt6ct.conf" && ok qt6ct || bad qt6ct "general not system-ui"
exit $fail
