#!/usr/bin/env bash
# apply.sh -- WhiteSur (macOS) dark theme for GTK3, GTK4/libadwaita and Qt (Kvantum).
#
#   tools/mac-theme/apply.sh [--browser CHROME_DIR] [--cache DIR]
#
#   --browser CHROME_DIR  ALSO install WhiteSur's Firefox/Zen userChrome into CHROME_DIR
#                         (a profile's chrome/ directory). Off by default.
#   --cache DIR           reuse/fill DIR with the pinned downloads instead of a temp dir
#
# Pinned prebuilt data only (see pins.env); no downloaded script is executed. Targeted and
# idempotent: only the keys/files it owns change, and everything it touches is first copied
# to ~/.local/state/qml-rice/mac-theme/<stamp>/ with a manifest. A run that would change
# nothing writes no backup, so apply -> apply -> revert restores the original state.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=pins.env
. "$HERE/pins.env"
INI="$HERE/ini.py"
H="${HOME:?HOME must be set}"
STATE="$H/.local/state/qml-rice/mac-theme"
STAMP=$(date +%Y%m%dT%H%M%S)
GTK_THEME="$WS_GTK_NAME"
MARK=".qml-rice-mac-theme"
LAYOUT="close,minimize,maximize:"
ICON_THEME="qml-rice-mac"

BROWSER_DIR=""
CACHE=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --browser) BROWSER_DIR="${2:?--browser needs the profile chrome dir}"; shift ;;
        --cache) CACHE="${2:?--cache needs a dir}"; shift ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "apply: unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

say() { printf '  %s\n' "$*"; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/mac-theme-apply.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# ------------------------------------------------------------------ fetch --
ART="${CACHE:-$TMP/dl}"
bash "$HERE/fetch.sh" "$ART" ${BROWSER_DIR:+--browser}

# ------------------------------------------------------------------ stage --
# Extract into a fresh dir under $TMP. Archives are untrusted data: tar without owner or
# permission restoration, then sanity-check the top level.
S="$TMP/stage"; mkdir -p "$S/gtk"
tar --no-same-owner --no-same-permissions -C "$S/gtk" -xf "$ART/$WS_GTK_FILE"
[ "$(ls -A "$S/gtk")" = "$WS_GTK_NAME" ] || { echo "apply: unexpected archive layout" >&2; exit 1; }
[ -f "$S/gtk/$WS_GTK_NAME/index.theme" ] || { echo "apply: archive has no index.theme" >&2; exit 1; }
printf '%s %s\n' "$WS_GTK_TAG" "$WS_GTK_SHA256" > "$S/gtk/$WS_GTK_NAME/$MARK"

# libadwaita: the prebuilt gtk-4.0/gtk.css is a stub importing a gresource, which libadwaita
# never registers. Unpack that gresource (data) to the same files WhiteSur's `install.sh -l`
# would put in ~/.config/gtk-4.0: gtk.css, gtk-dark.css and assets/.
GR="$S/gtk/$WS_GTK_NAME/gtk-4.0/gtk.gresource"
command -v gresource >/dev/null || { echo "apply: gresource (glib2) is required" >&2; exit 1; }
mkdir -p "$S/gtk4"
while IFS= read -r res; do
    case "$res" in
        /org/gnome/theme/*) ;;
        *) echo "apply: unexpected gresource path: $res" >&2; exit 1 ;;
    esac
    rel="${res#/org/gnome/theme/}"
    case "$rel" in *..*) echo "apply: bad gresource path: $res" >&2; exit 1 ;; esac
    mkdir -p "$S/gtk4/$(dirname "$rel")"
    gresource extract "$GR" "$res" > "$S/gtk4/$rel"
done < <(gresource list "$GR")
[ -s "$S/gtk4/gtk.css" ] && [ -s "$S/gtk4/gtk-dark.css" ] && [ -d "$S/gtk4/assets" ] \
    || { echo "apply: gresource unpack incomplete" >&2; exit 1; }

# Kvantum folder is named after the theme (Kvantum looks up <name>/<name>.kvconfig).
mkdir -p "$S/kv"
cp "$ART/$WS_KV_THEME.kvconfig" "$ART/$WS_KV_THEME.svg" "$S/kv/"

STUB3="/* mac-theme: WhiteSur-Dark owns GTK3 colours. matugen now writes matugen-gtk3.css next to this
   file (unused) so it cannot override the theme. Revert: tools/mac-theme/revert.sh */"
printf '%s\n' "$STUB3" > "$S/gtk3-stub.css"

# ---------------------------------------------------------------- planning --
PLANNED_FILES=(); declare -A FILE_SRC=()
PLANNED_DIRS=();  declare -A DIR_SRC=()
n=0
plan_file() { local dst="$1" src="$2"; [ -n "${FILE_SRC[$dst]:-}" ] || PLANNED_FILES+=("$dst"); FILE_SRC[$dst]="$src"; }
plan_dir()  { local dst="$1" src="$2"; [ -n "${DIR_SRC[$dst]:-}" ]  || PLANNED_DIRS+=("$dst");  DIR_SRC[$dst]="$src"; }
plan_edit() { # plan_edit DST PYARGS...   (chains on any earlier planned content)
    local dst="$1"; shift
    local src="${FILE_SRC[$dst]:-$dst}"
    n=$((n + 1)); local out; out=$(printf '%s/e%03d' "$TMP" "$n")
    python3 -I "$INI" "$1" "$src" "${@:2}" > "$out"
    plan_file "$dst" "$out"
}

# 1. GTK3/GTK4 theme dir (also what non-libadwaita GTK4 apps read).
plan_dir "$H/.themes/$GTK_THEME" "$S/gtk/$WS_GTK_NAME"

# 2. libadwaita overrides in ~/.config/gtk-4.0 (only the three things WhiteSur's -l owns).
plan_file "$H/.config/gtk-4.0/gtk.css"      "$S/gtk4/gtk.css"
plan_file "$H/.config/gtk-4.0/gtk-dark.css" "$S/gtk4/gtk-dark.css"
plan_dir  "$H/.config/gtk-4.0/assets"       "$S/gtk4/assets"

# 3. GTK3 user CSS would sit above the theme: neutralise the old colour file.
plan_file "$H/.config/gtk-3.0/gtk.css" "$S/gtk3-stub.css"

# 4. matugen must stop writing the two files WhiteSur now owns.
MCONF="$H/.config/matugen/config.toml"
if [ -e "$MCONF" ]; then
    plan_edit "$MCONF" toml-output templates.gtk3 "~/.config/gtk-3.0/matugen-gtk3.css"
    plan_edit "$MCONF" toml-output templates.gtk4 "~/.config/gtk-4.0/matugen-gtk4.css"
fi

# 5. settings.ini: theme + Mac button side; icon/font/cursor keys are left as they are.
for g in gtk-3.0 gtk-4.0; do
    f="$H/.config/$g/settings.ini"
    plan_edit "$f" ini Settings gtk-theme-name "$GTK_THEME"
    plan_edit "$f" ini Settings gtk-decoration-layout "$LAYOUT"
    plan_edit "$f" ini Settings gtk-application-prefer-dark-theme 1
done

# 6. Qt: Kvantum theme + KDE platform theme's widget style.
plan_dir  "$H/.config/Kvantum/$WS_KV_THEME" "$S/kv"
plan_edit "$H/.config/Kvantum/kvantum.kvconfig" ini General theme "$WS_KV_THEME"
plan_edit "$H/.config/kdeglobals" ini KDE widgetStyle kvantum-dark

# 7. Optional: browser userChrome.
if [ -n "$BROWSER_DIR" ]; then
    mkdir -p "$S/src"
    tar --no-same-owner --no-same-permissions -C "$S/src" -xzf "$ART/$WS_SRC_FILE" --wildcards '*/other/firefox/*'
    FF=$(echo "$S"/src/*/other/firefox)
    [ -d "$FF/WhiteSur" ] || { echo "apply: firefox sources missing in archive" >&2; exit 1; }
    C="$S/chrome"; mkdir -p "$C"
    # Mirrors lib-install.sh install_firefox_theme() for the default WhiteSur/standard variant.
    cp -r "$FF/WhiteSur" "$C/"
    cp "$FF/customChrome.css" "$C/"
    cp -r "$FF/common/icons" "$FF/common/pages" "$C/WhiteSur/"
    cp -r "$FF/common/titlebuttons" "$C/WhiteSur/"
    cp "$FF"/common/*.css "$C/WhiteSur/"
    cp "$FF"/common/parts/*.css "$C/WhiteSur/parts/"
    cp "$FF/userChrome-WhiteSur.css" "$C/userChrome.css"
    cp "$FF/userContent-WhiteSur.css" "$C/userContent.css"
    printf '%s %s\n' "$WS_GTK_TAG" "$WS_SRC_SHA256" > "$C/$MARK"
    # Overlay semantics: only files the theme ships are replaced, the rest of chrome/ stays.
    for rel in userChrome.css userContent.css customChrome.css "$MARK"; do plan_file "$BROWSER_DIR/$rel" "$C/$rel"; done
    plan_dir "$BROWSER_DIR/WhiteSur" "$C/WhiteSur"
fi

# gsettings: GVariant text is stored/restored verbatim.
GS=()  # entries "schema|key|wanted"
GS_PENDING=(); GS_OLD=()
if command -v gsettings >/dev/null 2>&1; then
    GS=("org.gnome.desktop.interface|gtk-theme|'$GTK_THEME'"
        "org.gnome.desktop.wm.preferences|button-layout|'$LAYOUT'")
    for e in "${GS[@]}"; do
        IFS='|' read -r sch key want <<< "$e"
        old=$(gsettings get "$sch" "$key" 2>/dev/null || true)
        if [ -n "$old" ] && [ "$old" != "$want" ]; then GS_PENDING+=("$e"); GS_OLD+=("$old"); fi
    done
fi

# ------------------------------------------------------------------ apply --
PEND_FILES=(); PEND_DIRS=()
for dst in ${PLANNED_FILES[@]+"${PLANNED_FILES[@]}"}; do
    if [ -f "$dst" ] && cmp -s "${FILE_SRC[$dst]}" "$dst"; then continue; fi
    PEND_FILES+=("$dst")
done
for dst in ${PLANNED_DIRS[@]+"${PLANNED_DIRS[@]}"}; do
    if [ -d "$dst" ] && diff -rq "${DIR_SRC[$dst]}" "$dst" >/dev/null 2>&1; then continue; fi
    PEND_DIRS+=("$dst")
done

if [ "${#PEND_FILES[@]}" -eq 0 ] && [ "${#PEND_DIRS[@]}" -eq 0 ] && [ "${#GS_PENDING[@]}" -eq 0 ]; then
    echo "mac-theme: already applied, nothing to change"
    exit 0
fi

BK="$STATE/$STAMP"
[ -e "$BK" ] && { echo "apply: backup dir $BK already exists; retry in a second" >&2; exit 1; }
mkdir -p "$BK/files"
MANIFEST="$BK/manifest.tsv"
printf '# mac-theme backup %s (HOME=%s)\n' "$STAMP" "$H" > "$MANIFEST"

# Paths are stored absolute (--browser may live outside HOME).
record_missing_dirs() { # PATH about to be created: remember parents that don't exist yet
    local d missing=() i
    d=$(dirname "$1")
    while [ "$d" != "$H" ] && [ "$d" != "/" ] && [ ! -e "$d" ]; do missing+=("$d"); d=$(dirname "$d"); done
    for ((i = ${#missing[@]} - 1; i >= 0; i--)); do printf 'mkdir\tdir\t%s\n' "${missing[i]}" >> "$MANIFEST"; done
}
snapshot() { # snapshot PATH TYPE(file|dir)
    local p="$1" t="$2"
    record_missing_dirs "$p"
    if [ -e "$p" ]; then
        mkdir -p "$BK/files/$(dirname "$p")"
        cp -a "$p" "$BK/files/$p"
        printf 'keep\t%s\t%s\n' "$t" "$p" >> "$MANIFEST"
    else
        printf 'absent\t%s\t%s\n' "$t" "$p" >> "$MANIFEST"
    fi
}

echo "mac-theme: backup -> $BK"
for p in ${PEND_FILES[@]+"${PEND_FILES[@]}"}; do snapshot "$p" file; done
for p in ${PEND_DIRS[@]+"${PEND_DIRS[@]}"};  do snapshot "$p" dir; done
for i in "${!GS_PENDING[@]}"; do
    IFS='|' read -r sch key _want <<< "${GS_PENDING[$i]}"
    printf 'gsettings\t%s\t%s\t%s\n' "$sch" "$key" "${GS_OLD[$i]}" >> "$MANIFEST"
done

for dst in ${PEND_DIRS[@]+"${PEND_DIRS[@]}"}; do
    mkdir -p "$(dirname "$dst")"
    rm -rf "$dst"
    cp -r "${DIR_SRC[$dst]}" "$dst"
    say "wrote ${dst#"$H"/}/"
done
for dst in ${PEND_FILES[@]+"${PEND_FILES[@]}"}; do
    mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ]; then cat "${FILE_SRC[$dst]}" > "$dst"; else install -m 644 "${FILE_SRC[$dst]}" "$dst"; fi
    say "wrote ${dst#"$H"/}"
done
for e in ${GS_PENDING[@]+"${GS_PENDING[@]}"}; do
    IFS='|' read -r sch key want <<< "$e"
    gsettings set "$sch" "$key" "$want"
    say "gsettings $sch $key = $want"
done

[ -d "$H/.local/share/icons/$ICON_THEME" ] || say "NOTE: icon theme $ICON_THEME not installed yet (mac-icons layer)"
[ -f /usr/lib/qt6/plugins/styles/libkvantum.so ] || say "NOTE: Qt6 Kvantum style plugin not found (install kvantum)"
echo "mac-theme: applied (stamp $STAMP). Restart GTK apps (and Qt apps) to see it; no relogin needed."
[ -z "$BROWSER_DIR" ] || echo "mac-theme: browser: set toolkit.legacyUserProfileCustomizations.stylesheets=true in about:config, restart the browser."
