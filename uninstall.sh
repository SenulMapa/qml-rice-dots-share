#!/usr/bin/env bash
# Removes what install.sh added and restores the newest hypr config backup,
# if any. Does not touch backups themselves (they stay under ~/.config/).
set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
    [ "$arg" = "--dry-run" ] && DRY_RUN=1
done

CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
HYPR_CFG="$CFG/hypr"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
INSTALL_DIR="$DATA/qml-rice"
FONT_DIR="$DATA/fonts/qml-rice"
BIN="$HOME/.local/bin/qml-rice"

run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '  [dry-run] %s\n' "$*"
    else
        printf '  %s\n' "$*"
        "$@"
    fi
}

echo "qml-rice-dots uninstall"

run rm -f "$HYPR_CFG/qml-rice-binds.lua"
run rm -f "$BIN"
# Removes every font install.sh put here: the fonts/ module's vendored OFL
# faces and shell/assets/fonts, if that was ever copied too.
run rm -rf "$FONT_DIR"

shopt -s nullglob
BACKUP_CANDIDATES=("$CFG"/hypr.backup-*)
shopt -u nullglob
LATEST_BACKUP=""
if [ "${#BACKUP_CANDIDATES[@]}" -gt 0 ]; then
    LATEST_BACKUP="${BACKUP_CANDIDATES[-1]}"
fi
if [ -n "$LATEST_BACKUP" ]; then
    echo "Restoring newest backup: $LATEST_BACKUP -> $HYPR_CFG"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  [dry-run] would: rm -rf '$HYPR_CFG' && cp -a '$LATEST_BACKUP' '$HYPR_CFG'"
    else
        rm -rf "$HYPR_CFG"
        cp -a "$LATEST_BACKUP" "$HYPR_CFG"
    fi
else
    echo "No hypr config backup found under $CFG; leaving $HYPR_CFG as-is"
    echo "(you can remove $HYPR_CFG/hyprland, hyprland.lua, hypridle.conf, etc. by hand)"
fi

echo "Note: $INSTALL_DIR (the git clone) is left in place so you can reinstall later."
echo "      Remove it yourself with: rm -rf '$INSTALL_DIR'"
pkill -f "shell.qml" 2>/dev/null || true
echo "Done."
