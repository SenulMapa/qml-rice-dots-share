#!/usr/bin/env bash
# apply.sh -- make Slack, Discord, Spotify native Wayland and give Qt/GTK/Hyprland
# one cursor and one set of Qt font/icon settings.
#
#   tools/mac-apps/apply.sh            # default: keeps QT_QPA_PLATFORMTHEME=kde
#   tools/mac-apps/apply.sh --qt6ct    # also switch the Qt platform theme to qt6ct (+Kvantum)
#
# Targeted and idempotent: it only edits the lines it owns and merges into existing
# files. Before it changes anything it copies every file it will touch (and the
# cursor theme dir and gsettings value) into
#   ~/.local/state/qml-rice/mac-apps/<stamp>/
# and writes manifest.tsv. A run that would change nothing creates no backup, so
# apply -> apply -> revert returns to the original state. revert.sh undoes it.
#
# Needs a Hyprland relogin (or restarting the affected apps) for env changes; see
# tools/mac-apps/README.md.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
MERGE="$HERE/merge.py"
H="${HOME:?HOME must be set}"
STATE="$H/.local/state/qml-rice/mac-apps"
ICON_THEME="qml-rice-mac"
UI_FONT="system-ui,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,Regular"
CURSOR_NAME="macOS"
CURSOR_SIZE="24"
STAMP=$(date +%Y%m%dT%H%M%S)

QT6CT=0
for arg in "$@"; do
    case "$arg" in
        --qt6ct) QT6CT=1 ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "apply: unknown argument: $arg" >&2; exit 2 ;;
    esac
done

say() { printf '  %s\n' "$*"; }

# The cursor pin lives in fetch-cursor.sh; read it so the two can't drift.
CUR_VERSION=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$HERE/fetch-cursor.sh")
CUR_SHA=$(sed -n 's/^SHA256="\(.*\)"$/\1/p' "$HERE/fetch-cursor.sh")

# Electron/CEF flags. Slack and Discord get --password-store too (Electron keyring,
# see ~/.config/electron-flags.conf); Spotify does not need it.
ELECTRON_FLAGS=(--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations)
KEYRING_FLAG=--password-store=gnome-libsecret

# ---------------------------------------------------------------- planning --
# PENDING_DST[i] is written from PENDING_SRC[i]. Nothing is written until the
# plan is complete, so a no-op run stays a no-op.
# Several edits can target one file (kdeglobals gets two keys). Each plan step
# reads the previous planned content, so they chain instead of overwriting.
PLANNED_DST=()             # unique targets, in order
declare -A PLANNED=()      # target -> file holding its planned content
TMP=$(mktemp -d "${TMPDIR:-/tmp}/mac-apps-apply.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
n=0

plan() { # plan DST NEWCONTENT_FILE
    local dst="$1" new="$2"
    if [ -z "${PLANNED[$dst]:-}" ]; then PLANNED_DST+=("$dst"); fi
    PLANNED[$dst]="$new"
}

NEWFILE=""
newfile() { n=$((n + 1)); NEWFILE=$(printf '%s/n%03d' "$TMP" "$n"); }  # sets NEWFILE; not a subshell

plan_merge() { # plan_merge DST MERGE_CMD ARGS...  (input = planned-or-on-disk DST)
    local dst="$1" cmd="$2"; shift 2
    local src="${PLANNED[$dst]:-$dst}"
    newfile
    python3 -I "$MERGE" "$cmd" "$src" "$@" > "$NEWFILE"
    plan "$dst" "$NEWFILE"
}

# 1. Spotify: wrapper reads ~/.config/spotify-flags.conf (verified in /usr/bin/spotify).
SPOT="$H/.config/spotify-flags.conf"
if [ -e "$SPOT" ]; then
    plan_merge "$SPOT" flags-conf "${ELECTRON_FLAGS[@]}"
else
    newfile; cp "$REPO/dots/macapps/.config/spotify-flags.conf" "$NEWFILE"; plan "$SPOT" "$NEWFILE"
fi

# 2. Slack and Discord: no flags-file reader, so the flags go on a .desktop Exec line.
for app in slack discord; do
    case "$app" in
        slack)   bin=/usr/bin/slack ;;
        discord) bin=/usr/bin/discord ;;
    esac
    dst="$H/.local/share/applications/$app.desktop"
    if [ -e "$dst" ]; then
        plan_merge "$dst" desktop "$bin" "${ELECTRON_FLAGS[@]}" "$KEYRING_FLAG"
    else
        newfile; cp "$REPO/dots/macapps/.local/share/applications/$app.desktop" "$NEWFILE"; plan "$dst" "$NEWFILE"
    fi
done

# 3. Cursor: XCURSOR_THEME in Hyprland env, GTK settings.ini, gsettings.
CURSOR_DIR="$H/.local/share/icons/$CURSOR_NAME"
CURSOR_NEEDED=0
if [ "$(cat "$CURSOR_DIR/.qml-rice-cursor" 2>/dev/null)" != "$CUR_VERSION $CUR_SHA" ]; then
    CURSOR_NEEDED=1
fi

for gtk in gtk-3.0 gtk-4.0; do
    f="$H/.config/$gtk/settings.ini"
    if [ -e "$f" ]; then
        plan_merge "$f" ini Settings gtk-cursor-theme-name "$CURSOR_NAME"
        plan_merge "$f" ini Settings gtk-cursor-theme-size "$CURSOR_SIZE"
    else
        say "skip $f (missing; the gtk module installs it)"
    fi
done

ENV_LUA="$H/.config/hypr/hyprland/env.lua"
[ -e "$ENV_LUA" ] || { echo "apply: $ENV_LUA missing; the hypr module must be installed first" >&2; exit 1; }
plan_merge "$ENV_LUA" env-cursor

GS_CUR_OLD=""
GS_CHANGE=0
if command -v gsettings >/dev/null 2>&1; then
    GS_CUR_OLD=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null || true)
    [ "$GS_CUR_OLD" = "'$CURSOR_NAME'" ] || GS_CHANGE=1
fi

# 4. Qt: one icon theme, one UI font, in kdeglobals (KDE platform theme) and qt6ct.
KDEG="$H/.config/kdeglobals"
if [ -e "$KDEG" ]; then
    plan_merge "$KDEG" ini Icons Theme "$ICON_THEME"
    plan_merge "$KDEG" ini General font "$UI_FONT"
else
    say "skip $KDEG (missing)"
fi

QT6CTC="$H/.config/qt6ct/qt6ct.conf"
if [ -e "$QT6CTC" ]; then
    plan_merge "$QT6CTC" ini Appearance icon_theme "$ICON_THEME"
    plan_merge "$QT6CTC" ini Fonts general "\"$UI_FONT\""
    if [ "$QT6CT" = 1 ]; then
        plan_merge "$QT6CTC" ini Appearance style kvantum
    fi
else
    say "skip $QT6CTC (missing)"
fi

if [ "$QT6CT" = 1 ]; then
    plan_merge "$ENV_LUA" env-qt qt6ct
fi

# ------------------------------------------------------------------ apply --
PENDING_DST=()
PENDING_SRC=()
for dst in ${PLANNED_DST[@]+"${PLANNED_DST[@]}"}; do
    if [ -e "$dst" ] && cmp -s "${PLANNED[$dst]}" "$dst"; then continue; fi
    PENDING_DST+=("$dst")
    PENDING_SRC+=("${PLANNED[$dst]}")
done

if [ "${#PENDING_DST[@]}" -eq 0 ] && [ "$CURSOR_NEEDED" = 0 ] && [ "$GS_CHANGE" = 0 ]; then
    echo "mac-apps: already applied, nothing to change"
    exit 0
fi

BK="$STATE/$STAMP"
[ -e "$BK" ] && { echo "apply: backup dir $BK already exists; retry in a second" >&2; exit 1; }
mkdir -p "$BK/files"
MANIFEST="$BK/manifest.tsv"
printf '# mac-apps backup %s (HOME=%s)\n' "$STAMP" "$H" > "$MANIFEST"

# Directories this run creates (not the files in them) are recorded so revert can
# rmdir them, top-most first in the manifest, deepest removed first on revert.
record_missing_dirs() { # record_missing_dirs PATH  (PATH is a file or dir about to be created)
    local d missing=() i
    d=$(dirname "$1")
    while [ "$d" != "$H" ] && [ "$d" != "/" ] && [ ! -e "$d" ]; do
        missing+=("$d")
        d=$(dirname "$d")
    done
    for ((i = ${#missing[@]} - 1; i >= 0; i--)); do
        printf 'mkdir	dir	%s
' "${missing[i]#"$H"/}" >> "$MANIFEST"
    done
}

snapshot_file() {
    local dst="$1" rel="${1#"$H"/}"
    if [ -e "$dst" ]; then
        mkdir -p "$BK/files/$(dirname "$rel")"
        cp -a "$dst" "$BK/files/$rel"
        printf 'keep\tfile\t%s\n' "$rel" >> "$MANIFEST"
    else
        printf 'absent\tfile\t%s\n' "$rel" >> "$MANIFEST"
    fi
}

echo "mac-apps: backup -> $BK"
for dst in ${PENDING_DST[@]+"${PENDING_DST[@]}"}; do
    record_missing_dirs "$dst"
    snapshot_file "$dst"
done

if [ "$CURSOR_NEEDED" = 1 ]; then
    record_missing_dirs "$CURSOR_DIR/x"
    rel="${CURSOR_DIR#"$H"/}"
    if [ -e "$CURSOR_DIR" ]; then
        mkdir -p "$BK/files/$(dirname "$rel")"
        cp -a "$CURSOR_DIR" "$BK/files/$rel"
        printf 'keep\tdir\t%s\n' "$rel" >> "$MANIFEST"
    else
        printf 'absent\tdir\t%s\n' "$rel" >> "$MANIFEST"
    fi
fi

if [ "$GS_CHANGE" = 1 ]; then
    # Stored verbatim (GVariant text) so revert can pass it straight back to gsettings.
    printf 'gsettings\torg.gnome.desktop.interface\tcursor-theme\t%s\n' "$GS_CUR_OLD" >> "$MANIFEST"
fi

for i in "${!PENDING_DST[@]}"; do
    dst="${PENDING_DST[$i]}"
    mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ]; then
        cat "${PENDING_SRC[$i]}" > "$dst"        # keep the existing file mode
    else
        install -m 644 "${PENDING_SRC[$i]}" "$dst"
    fi
    say "wrote ${dst#"$H"/}"
done

if [ "$CURSOR_NEEDED" = 1 ]; then
    bash "$HERE/fetch-cursor.sh" "$H/.local/share/icons"
    say "installed cursor theme $CURSOR_NAME $CUR_VERSION"
fi

if [ "$GS_CHANGE" = 1 ]; then
    gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_NAME"
    say "gsettings cursor-theme $CURSOR_NAME (was $GS_CUR_OLD)"
fi

if [ ! -d "$H/.local/share/icons/$ICON_THEME" ]; then
    say "NOTE: icon theme $ICON_THEME is not installed yet (Layer 2 installs it); Qt/GTK fall back until then"
fi

echo "mac-apps: applied (stamp $STAMP). Relog or restart Hyprland for env changes; restart Slack, Discord, Spotify."
