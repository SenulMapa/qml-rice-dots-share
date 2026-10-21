#!/usr/bin/env bash
# check.sh -- verify the mac-apps layer is in place. Exit 0 = pass.
#
#   tools/mac-apps/check.sh [--home DIR] [--live]
#
#   --home DIR  check the files under DIR instead of $HOME (throwaway-HOME tests)
#   --live      read-only: ask Hyprland (hyprctl clients -j) which running Slack /
#               Discord / Spotify windows are XWayland. Changes nothing. Exits 1 if
#               any running one is XWayland. Not-running apps are reported, not failed.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
MERGE="$HERE/merge.py"
H="${HOME:?HOME must be set}"
LIVE=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --home) H="$2"; shift ;;
        --live) LIVE=1 ;;
        -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
        *) echo "check: unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

CUR_VERSION=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$HERE/fetch-cursor.sh")
CUR_SHA=$(sed -n 's/^SHA256="\(.*\)"$/\1/p' "$HERE/fetch-cursor.sh")
ELECTRON_FLAGS=(--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations)
KEYRING_FLAG=--password-store=gnome-libsecret

FAILS=0
pass() { printf '  PASS %s\n' "$*"; }
fail() { printf '  FAIL %s\n' "$*"; FAILS=$((FAILS + 1)); }
warn() { printf '  WARN %s\n' "$*"; }

# ini_get FILE SECTION KEY -> value on stdout (empty if absent)
ini_get() {
    awk -v sec="[$2]" -v key="$3" '
        /^\[/ { insec = ($0 == sec); next }
        insec && index($0, key "=") == 1 { sub(/^[^=]*=/, ""); print; exit }
    ' "$1" 2>/dev/null
}

echo "mac-apps check (HOME=$H)"

# --- Electron / CEF native Wayland -----------------------------------------
SPOT="$H/.config/spotify-flags.conf"
if [ -f "$SPOT" ] && python3 -I "$MERGE" check-flags "$SPOT" "${ELECTRON_FLAGS[@]}" >/dev/null; then
    pass "spotify-flags.conf has the Wayland flags"
else
    fail "spotify-flags.conf missing or lacks ${ELECTRON_FLAGS[*]}"
fi

for app in slack discord; do
    f="$H/.local/share/applications/$app.desktop"
    if [ -f "$f" ] && python3 -I "$MERGE" check-flags "$f" "${ELECTRON_FLAGS[@]}" "$KEYRING_FLAG" >/dev/null; then
        pass "$app.desktop Exec has the Wayland flags + $KEYRING_FLAG"
    else
        fail "$app.desktop missing or its Exec lacks the Wayland flags / $KEYRING_FLAG"
    fi
done

# --- Cursor -----------------------------------------------------------------
CDIR="$H/.local/share/icons/macOS"
if [ "$(cat "$CDIR/.qml-rice-cursor" 2>/dev/null)" = "$CUR_VERSION $CUR_SHA" ] && [ -f "$CDIR/cursors/arrow" ]; then
    pass "macOS cursor theme $CUR_VERSION installed (XCursor)"
else
    fail "macOS cursor theme $CUR_VERSION not installed under $H/.local/share/icons/macOS"
fi

for gtk in gtk-3.0 gtk-4.0; do
    f="$H/.config/$gtk/settings.ini"
    v=$(ini_get "$f" Settings gtk-cursor-theme-name)
    if [ "$v" = "macOS" ]; then pass "$gtk gtk-cursor-theme-name=macOS"; else fail "$gtk gtk-cursor-theme-name is '${v:-unset}' (want macOS)"; fi
done

ENV_LUA="$H/.config/hypr/hyprland/env.lua"
nx=$(grep -c 'hl\.env("XCURSOR_THEME"' "$ENV_LUA" 2>/dev/null || true)
ns=$(grep -c 'hl\.env("XCURSOR_SIZE", "24")' "$ENV_LUA" 2>/dev/null || true)
if [ "$nx" = 1 ] && [ "$ns" = 1 ] && grep -q 'hl\.env("XCURSOR_THEME", "macOS")' "$ENV_LUA"; then
    pass "hypr env.lua sets XCURSOR_THEME=macOS and XCURSOR_SIZE=24 exactly once"
else
    fail "hypr env.lua XCURSOR lines wrong (XCURSOR_THEME x$nx, XCURSOR_SIZE x$ns)"
fi

if command -v gsettings >/dev/null 2>&1; then
    g=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null || true)
    if [ "$g" = "'macOS'" ]; then pass "gsettings cursor-theme = macOS"; else fail "gsettings cursor-theme is ${g:-unreadable} (want 'macOS')"; fi
else
    warn "gsettings not installed; cursor-theme not checked"
fi

# --- Qt ----------------------------------------------------------------------
KDEG="$H/.config/kdeglobals"
qi=$(ini_get "$KDEG" Icons Theme)
qf=$(ini_get "$KDEG" General font)
[ "$qi" = "qml-rice-mac" ] && pass "kdeglobals [Icons] Theme=qml-rice-mac" || fail "kdeglobals [Icons] Theme is '${qi:-unset}' (want qml-rice-mac)"
case "$qf" in system-ui,11,*) pass "kdeglobals font is system-ui 11" ;; *) fail "kdeglobals [General] font is '${qf:-unset}' (want system-ui,11,...)" ;; esac

Q6="$H/.config/qt6ct/qt6ct.conf"
ti=$(ini_get "$Q6" Appearance icon_theme)
tf=$(ini_get "$Q6" Fonts general)
[ "$ti" = "qml-rice-mac" ] && pass "qt6ct icon_theme=qml-rice-mac" || fail "qt6ct icon_theme is '${ti:-unset}' (want qml-rice-mac)"
case "$tf" in '"system-ui,11,'*) pass "qt6ct font is system-ui 11" ;; *) fail "qt6ct [Fonts] general is '${tf:-unset}' (want \"system-ui,11,...\")" ;; esac

# Platform theme: kde (default) or qt6ct (after apply --qt6ct). Either is valid; report which.
pt=$(sed -n 's/^hl\.env("QT_QPA_PLATFORMTHEME", *"\([^"]*\)").*/\1/p' "$ENV_LUA" | tail -n 1)
case "$pt" in
    kde)   pass "QT_QPA_PLATFORMTHEME=kde (default path; kdeglobals is the source)" ;;
    qt6ct) pass "QT_QPA_PLATFORMTHEME=qt6ct (--qt6ct path); qt6ct.conf style should be kvantum"
           [ "$(ini_get "$Q6" Appearance style)" = "kvantum" ] || fail "platform theme qt6ct but qt6ct.conf style is not kvantum" ;;
    *)     fail "QT_QPA_PLATFORMTHEME is '${pt:-unset}' (want kde or qt6ct)" ;;
esac

[ -d "$H/.local/share/icons/qml-rice-mac" ] && pass "icon theme qml-rice-mac installed" \
    || warn "icon theme qml-rice-mac not installed yet (Layer 2)"

# --- Live (read-only) ---------------------------------------------------------
if [ "$LIVE" = 1 ]; then
    echo "live: XWayland state of running Electron/CEF windows (read-only)"
    clients=$(timeout 5 hyprctl clients -j 2>/dev/null || true)
    if [ -z "$clients" ]; then
        warn "hyprctl clients -j returned nothing (is Hyprland running?)"
    else
        printf '%s' "$clients" | python3 -I -c '
import json, sys
want = {"slack": "slack", "discord": "discord", "spotify": "spotify"}
found = {k: [] for k in want}
for c in json.load(sys.stdin):
    cls = (c.get("class") or "").lower()
    for app in want:
        if cls == want[app] or cls.startswith(app):
            found[app].append(c.get("xwayland"))
bad = 0
for app, flags in found.items():
    if not flags:
        print("  INFO %s not running" % app)
    for x in flags:
        print("  %s %s xwayland=%s" % ("FAIL" if x else "PASS", app, x))
        bad += 1 if x else 0
sys.exit(1 if bad else 0)
' || FAILS=$((FAILS + 1))
    fi
fi

echo
if [ "$FAILS" -eq 0 ]; then echo "mac-apps check: PASS"; exit 0; fi
echo "mac-apps check: FAIL ($FAILS)"
exit 1
