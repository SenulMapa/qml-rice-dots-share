#!/usr/bin/env bash
# Layer 6 (web-app overlays): applies the Gemini-style web-app launchers to the
# LIVE desktop. Targeted, idempotent, backed up. Does NOT reload Hyprland.
#
# Installs:
#   ~/.local/bin/webapp-<id>, ~/.local/bin/webapp-<id>-toggle
#   ~/.local/share/applications/webapp-<id>.desktop
#   ~/.config/hypr/hyprland/webapps.lua            (copied, generated rules + binds)
#   ~/.config/hypr/hyprland.lua                    (ONE line added after require("hyprland.glass"))
#
# Backups: ~/.local/state/qml-rice/mac-webapps/<stamp>/ (manifest.tsv + files/).
# Undo with tools/mac-webapps/revert.sh [stamp].
#
# Usage: apply.sh [--dry-run]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

STATE_ROOT="$HOME/.local/state/qml-rice/mac-webapps"
STAMP="$(date +%Y%m%d-%H%M%S)"
BK="$STATE_ROOT/$STAMP"
HYPR_LUA="$HOME/.config/hypr/hyprland.lua"
SRC_BIN="$REPO/dots/webapps/.local/bin"
SRC_APP="$REPO/dots/webapps/.local/share/applications"
LUA_REQ='require("hyprland.webapps")'
ANCHOR='require("hyprland.glass")'

[ -f "$HYPR_LUA" ] || { echo "apply: $HYPR_LUA not found; BLOCKED (is the hypr module installed?)" >&2; exit 3; }
grep -qF "$ANCHOR" "$HYPR_LUA" || { echo "apply: anchor '$ANCHOR' not in $HYPR_LUA; BLOCKED (edit by hand)" >&2; exit 3; }

changes=0
bk_ready=0
ensure_bk() {
    if [ "$bk_ready" -eq 0 ]; then
        mkdir -p "$BK/files"
        : > "$BK/manifest.tsv"
        bk_ready=1
    fi
}
# Records how to undo one target before it is touched.
record() {
    local target="$1" n
    ensure_bk
    if [ -e "$target" ] || [ -L "$target" ]; then
        n="$(wc -l < "$BK/manifest.tsv")"
        cp -a "$target" "$BK/files/$n"
        printf 'restore\t%s\t%s\n' "$target" "$BK/files/$n" >> "$BK/manifest.tsv"
    else
        printf 'remove\t%s\t-\n' "$target" >> "$BK/manifest.tsv"
    fi
}
# Records directories that do not exist yet (shallowest first) so revert can remove them.
record_new_dirs() {
    local d chain=() x
    d="$(dirname "$1")"
    while [ ! -d "$d" ]; do
        chain=("$d" "${chain[@]}")
        d="$(dirname "$d")"
    done
    ensure_bk
    for x in "${chain[@]}"; do
        printf 'rmdir\t%s\t-\n' "$x" >> "$BK/manifest.tsv"
    done
}
do_install() { # src dst mode
    local src="$1" dst="$2" mode="$3"
    if [ -f "$dst" ] && cmp -s "$src" "$dst" && [ "$(stat -c %a "$dst")" = "${mode#0}" ]; then
        echo "  keep    $dst"
        return 0
    fi
    changes=$((changes + 1))
    if [ "$DRY" -eq 1 ]; then echo "  would install $dst"; return 0; fi
    record_new_dirs "$dst"
    record "$dst"
    install -D -m "$mode" "$src" "$dst"
    echo "  install $dst"
}

echo "mac-webapps apply (stamp $STAMP)"
shopt -s nullglob
for f in "$SRC_BIN"/webapp-*; do
    do_install "$f" "$HOME/.local/bin/$(basename "$f")" 755
done
for f in "$SRC_APP"/webapp-*.desktop; do
    do_install "$f" "$HOME/.local/share/applications/$(basename "$f")" 644
done
shopt -u nullglob
do_install "$REPO/hypr/hyprland/webapps.lua" "$HOME/.config/hypr/hyprland/webapps.lua" 644

# One targeted line in the live hyprland.lua (the live file has drifted from the repo).
if grep -qF "$LUA_REQ" "$HYPR_LUA"; then
    echo "  keep    $HYPR_LUA (webapps line present)"
else
    changes=$((changes + 1))
    if [ "$DRY" -eq 1 ]; then
        echo "  would add webapps require after '$ANCHOR' in $HYPR_LUA"
    else
        record "$HYPR_LUA"
        tmp="$(mktemp "$HYPR_LUA.webapps.XXXXXX")"
        awk -v anchor="$ANCHOR" '
            { print }
            index($0, anchor) && !done {
                print "-- Layer 6 web-app overlays (tools/mac-webapps; generated webapps.lua)."
                print "if is_file_exists(HOME .. \"/.config/hypr/hyprland/webapps.lua\") then"
                print "    require(\"hyprland.webapps\")"
                print "end"
                done = 1
            }' "$HYPR_LUA" > "$tmp"
        cat "$tmp" > "$HYPR_LUA"   # keeps the live file's inode and mode
        rm -f "$tmp"
        echo "  edit    $HYPR_LUA (+4 lines after $ANCHOR)"
    fi
fi

if [ "$DRY" -eq 1 ]; then
    echo "dry run: $changes change(s) pending; nothing written"
elif [ "$changes" -eq 0 ]; then
    echo "already applied; nothing changed"
else
    echo "applied $changes change(s); backup $BK"
    echo "NOTE: Hyprland must reload (hyprctl reload or relogin) before SUPER+ALT+G exists."
    echo "NOTE: needs brave on PATH (package brave-bin) and jq for the toggle script."
fi
