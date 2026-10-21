#!/usr/bin/env bash
# check.sh -- verify the mac-theme layer is in place. Exit 0 = pass. Read-only.
#
#   tools/mac-theme/check.sh [--home DIR] [--browser CHROME_DIR]
#
#   --home DIR           check the files under DIR instead of $HOME (throwaway tests)
#   --browser CHROME_DIR also check the browser userChrome install
#
# Static checks only (files, settings keys, relative asset links); it never starts a GTK or Qt
# app. The gsettings check uses whatever backend the environment selects (set
# GSETTINGS_BACKEND=keyfile and XDG_CONFIG_HOME in tests).
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=pins.env
. "$HERE/pins.env"
H="${HOME:?HOME must be set}"
BROWSER_DIR=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --home) H="$2"; shift ;;
        --browser) BROWSER_DIR="$2"; shift ;;
        -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
        *) echo "check: unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

FAILS=0
pass() { printf '  PASS %s\n' "$*"; }
fail() { printf '  FAIL %s\n' "$*"; FAILS=$((FAILS + 1)); }
warn() { printf '  WARN %s\n' "$*"; }
ini_get() { # FILE SECTION KEY
    awk -v sec="[$2]" -v key="$3" '
        /^\[/ { insec = ($0 == sec); next }
        insec && $0 ~ "^[ \t]*" key "[ \t]*=" { sub(/^[^=]*=/, ""); print; exit }
    ' "$1" 2>/dev/null
}
want_ini() { # LABEL FILE SECTION KEY VALUE
    local v; v=$(ini_get "$2" "$3" "$4")
    if [ "$v" = "$5" ]; then pass "$1 $4=$5"; else fail "$1 $4 is '${v:-unset}' (want $5)"; fi
}
keep_ini() { # LABEL FILE SECTION KEY VALUE  -- owned by another layer (mac-apps/mac-icons/mac-text): informational
    local v; v=$(ini_get "$2" "$3" "$4")
    if [ "$v" = "$5" ]; then pass "$1 $4=$5 (kept)"
    elif [ -z "$v" ]; then warn "$1 $4 unset (other layer sets it)"
    else warn "$1 $4 is '$v' (final value $5 comes from its own layer; this layer never edits it)"; fi
}

echo "mac-theme check (HOME=$H)"

# --- pins sanity ----------------------------------------------------------
for v in WS_GTK_SHA256 WS_KV_CONFIG_SHA256 WS_KV_SVG_SHA256 WS_SRC_SHA256; do
    [[ "${!v}" =~ ^[0-9a-f]{64}$ ]] && pass "pins.env $v is a sha256" || fail "pins.env $v malformed"
done
[[ "$WS_GTK_COMMIT" =~ ^[0-9a-f]{40}$ && "$WS_KDE_COMMIT" =~ ^[0-9a-f]{40}$ ]] && pass "pins.env commits pinned" || fail "pins.env commit pins malformed"

# --- GTK theme dir ----------------------------------------------------------
T="$H/.themes/$WS_GTK_NAME"
if [ -f "$T/index.theme" ] && grep -q "^Name=$WS_GTK_NAME\$" "$T/index.theme"; then pass "$WS_GTK_NAME/index.theme present"; else fail "$T/index.theme missing or wrong Name"; fi
for f in gtk-3.0/gtk.css gtk-3.0/gtk.gresource gtk-4.0/gtk.css gtk-4.0/gtk.gresource; do
    [ -s "$T/$f" ] && pass "theme has $f" || fail "theme lacks $f"
done
if [ "$(cat "$T/.qml-rice-mac-theme" 2>/dev/null)" = "$WS_GTK_TAG $WS_GTK_SHA256" ]; then pass "theme marker = $WS_GTK_TAG"; else fail "theme marker missing/stale (not the pinned release)"; fi

# --- libadwaita overrides ---------------------------------------------------
G4="$H/.config/gtk-4.0"
for f in gtk.css gtk-dark.css; do
    if [ -s "$G4/$f" ] && ! grep -q 'resource:///' "$G4/$f" && grep -q '@define-color accent_bg_color' "$G4/$f"; then
        pass "gtk-4.0/$f is the full WhiteSur stylesheet"
    else fail "gtk-4.0/$f missing, a gresource stub, or not WhiteSur"; fi
done
missing=0; total=0
while IFS= read -r u; do
    total=$((total + 1))
    [ -f "$G4/$u" ] || { missing=$((missing + 1)); printf '       missing asset: %s\n' "$u"; }
done < <(grep -oh 'url("assets/[^"]*")' "$G4/gtk.css" "$G4/gtk-dark.css" 2>/dev/null | sed 's/^url("//; s/")$//' | sort -u)
if [ "$total" -gt 0 ] && [ "$missing" -eq 0 ]; then pass "all $total url(assets/...) links resolve in gtk-4.0"; else fail "$missing of $total gtk-4.0 asset links broken"; fi

# --- GTK3 user css + matugen -----------------------------------------------
if [ -f "$H/.config/gtk-3.0/gtk.css" ] && ! grep -q '@define-color' "$H/.config/gtk-3.0/gtk.css"; then pass "gtk-3.0/gtk.css carries no colour overrides"; else fail "gtk-3.0/gtk.css missing or still overrides theme colours"; fi
M="$H/.config/matugen/config.toml"
if [ -f "$M" ]; then
    if grep -E "^output_path *= *'~/\.config/gtk-[34]\.0/gtk\.css'" "$M" >/dev/null; then fail "matugen still writes a gtk.css (would clobber WhiteSur)"; else pass "matugen no longer writes gtk-3.0/gtk.css or gtk-4.0/gtk.css"; fi
else warn "no matugen config under $H (nothing to retarget)"; fi

# --- settings.ini -----------------------------------------------------------
for g in gtk-3.0 gtk-4.0; do
    f="$H/.config/$g/settings.ini"
    if [ ! -f "$f" ]; then fail "$g/settings.ini missing"; continue; fi
    want_ini "$g" "$f" Settings gtk-theme-name "$WS_GTK_NAME"
    want_ini "$g" "$f" Settings gtk-decoration-layout "close,minimize,maximize:"
    keep_ini "$g" "$f" Settings gtk-icon-theme-name qml-rice-mac
    keep_ini "$g" "$f" Settings gtk-font-name "system-ui 11"
    keep_ini "$g" "$f" Settings gtk-cursor-theme-name macOS
done
if command -v gsettings >/dev/null 2>&1; then
    v=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null)
    [ "$v" = "'$WS_GTK_NAME'" ] && pass "gsettings gtk-theme=$v" || fail "gsettings gtk-theme is $v"
    v=$(gsettings get org.gnome.desktop.wm.preferences button-layout 2>/dev/null)
    [ "$v" = "'close,minimize,maximize:'" ] && pass "gsettings button-layout=$v" || fail "gsettings button-layout is $v"
else warn "gsettings not installed; skipped"; fi

# --- Qt / Kvantum -------------------------------------------------------------
KV="$H/.config/Kvantum/$WS_KV_THEME"
[ "$(sha256sum "$KV/$WS_KV_THEME.kvconfig" 2>/dev/null | cut -d' ' -f1)" = "$WS_KV_CONFIG_SHA256" ] && pass "Kvantum $WS_KV_THEME.kvconfig matches pin" || fail "Kvantum $WS_KV_THEME.kvconfig missing/different"
[ "$(sha256sum "$KV/$WS_KV_THEME.svg" 2>/dev/null | cut -d' ' -f1)" = "$WS_KV_SVG_SHA256" ] && pass "Kvantum $WS_KV_THEME.svg matches pin" || fail "Kvantum $WS_KV_THEME.svg missing/different"
grep -q '^translucent_windows=true' "$KV/$WS_KV_THEME.kvconfig" 2>/dev/null && pass "Kvantum theme is the translucent one" || fail "Kvantum theme lacks translucent_windows=true"
want_ini kvantum.kvconfig "$H/.config/Kvantum/kvantum.kvconfig" General theme "$WS_KV_THEME"
want_ini kdeglobals "$H/.config/kdeglobals" KDE widgetStyle kvantum-dark
[ -f /usr/lib/qt6/plugins/styles/libkvantum.so ] && pass "Qt6 Kvantum style plugin installed" || warn "Qt6 Kvantum plugin not found on this machine (install kvantum)"

# --- optional browser -----------------------------------------------------------
if [ -n "$BROWSER_DIR" ]; then
    if grep -q '@import "WhiteSur/theme.css"' "$BROWSER_DIR/userChrome.css" 2>/dev/null && [ -f "$BROWSER_DIR/WhiteSur/theme.css" ] && [ -d "$BROWSER_DIR/WhiteSur/titlebuttons" ]; then pass "browser userChrome imports WhiteSur/theme.css and its files exist"; else fail "browser userChrome not installed in $BROWSER_DIR"; fi
    bad=0
    while IFS= read -r imp; do [ -f "$BROWSER_DIR/$imp" ] || { bad=1; echo "       missing import: $imp"; }; done < <(grep -oh '^@import "[^"]*"' "$BROWSER_DIR/userChrome.css" "$BROWSER_DIR/userContent.css" 2>/dev/null | sed 's/^@import "//; s/"$//' | sort -u)
    [ "$bad" = 0 ] && pass "every active @import in userChrome/userContent resolves" || fail "dangling userChrome @import"
fi

if [ "$FAILS" -eq 0 ]; then echo "mac-theme: all checks passed"; else echo "mac-theme: $FAILS check(s) FAILED"; fi
[ "$FAILS" -eq 0 ]
