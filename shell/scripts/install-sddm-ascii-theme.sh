#!/usr/bin/env bash
# Installs the qml-rice-ascii SDDM theme (system/sddm/qml-rice-ascii/ in this
# repo -- the ASCII lock's waving, hue-rotating clock reused as the login
# screen) to /usr/share/sddm/themes/qml-rice-ascii, and bakes the owner's
# CURRENT wallpaper-derived palette into that install's theme.conf.
#
# This script does NOT run automatically as part of any other tooling in
# this repo, and does not touch /etc/sddm.conf* itself -- it only copies
# files under /usr/share/sddm/themes/, writes a NEW zz-qml-rice.conf under
# /etc/sddm.conf.d/, and then prints what it did plus how to revert. Per
# this port's brief, it must be run manually, with sudo, by the owner.
#
# Usage:
#   sudo ./scripts/install-sddm-ascii-theme.sh
#
# Dry run (writes theme.conf to /tmp instead of /usr, skips /etc entirely,
# no root required) -- proves the palette extraction produces a valid
# theme.conf without touching the real system:
#   ./scripts/install-sddm-ascii-theme.sh --dry-run
#
# Palette source: core/Config.qml's Config.appearance.activePalettePath,
# i.e. $XDG_STATE_HOME/odyssey/palette.json (defaults to
# ~/.local/state/odyssey/palette.json) -- the same file core/Theme.qml reads
# for every other Theme.* colour token in this shell, including the lock's
# own colorA/colorB/colorC (Theme.error/Theme.warning/Theme.tertiary). This
# script reads whichever of palette.mode's "dark"/"light" sections is
# active and maps:
#   surface            -> ColorSurface
#   onSurface          -> ColorSurfaceText
#   onSurfaceVariant   -> ColorSurfaceVariantText
#   error              -> ColorError   (the lock's colorA)
#   warning            -> ColorWarning (the lock's colorB)
#   tertiary           -> ColorTertiary (the lock's colorC)
# into theme.conf's [General] section, which Main.qml reads back out
# through SDDM's `config` context object at greeter start. If the palette
# file is missing, unreadable, or not valid JSON, the packaged theme.conf
# defaults (same values Main.qml also hardcodes) are left untouched -- the
# greeter never fails to render for a palette problem.
#
# Fonts: JetBrains Mono is used for the ascii glyphs -- verified
# system-installed (readable by the `sddm` user, unlike anything under the
# owner's ~/.local/share/fonts) via:
#   fc-list | grep -i jetbrains | grep -v /home
# which lists it under /usr/share/fonts/TTF. The lock's own display font,
# Instrument Serif (core/Theme.qml's fontDisplay), is NOT system-wide --
# it only exists under ~/.local/share/fonts/qml-rice, unreadable by the
# `sddm` user -- so Main.qml falls back to the generic "serif" family for
# all display text (date, username, password hint, session, power), which
# fontconfig always resolves to an installed system serif.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$REPO_ROOT/system/sddm/qml-rice-ascii"
DEST="/usr/share/sddm/themes/qml-rice-ascii"
CONF_DIR="/etc/sddm.conf.d"
CONF_FILE="$CONF_DIR/zz-qml-rice.conf"

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

if [[ "$DRY_RUN" -eq 0 ]]; then
    if [[ "$(id -u)" -ne 0 ]]; then
        echo "This installs into /usr/share/sddm/themes and /etc/sddm.conf.d, which needs root." >&2
        echo "Run it again with sudo:" >&2
        echo "  sudo $0" >&2
        exit 1
    fi
    DEST_OUT="$DEST"
    THEME_CONF_OUT="$DEST/theme.conf"
else
    DEST_OUT="/tmp/qml-rice-ascii-dry-run/theme"
    THEME_CONF_OUT="/tmp/qml-rice-ascii-dry-run/theme.conf"
    mkdir -p "$(dirname "$THEME_CONF_OUT")"
    echo "--dry-run: writing to /tmp instead of /usr and /etc, no root needed."
fi

if [[ ! -f "$SRC/metadata.desktop" ]]; then
    echo "Cannot find the theme at $SRC (expected metadata.desktop there)." >&2
    exit 1
fi

# ---- palette extraction ---------------------------------------------------
#
# Mirrors core/Config.qml's Config.appearance.activePalettePath: same
# $XDG_STATE_HOME default core/Config.qml uses for stateRoot.
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
PALETTE_PATH="${QML_RICE_PALETTE_PATH:-$STATE_HOME/odyssey/palette.json}"

# Dark fallbacks -- identical to theme.conf's packaged defaults and to
# Main.qml's own hardcoded _cfg() fallbacks, so a missing/bad palette file
# never breaks the greeter.
COLOR_SURFACE="#0b0e10"
COLOR_SURFACE_TEXT="#e7eef0"
COLOR_SURFACE_VARIANT_TEXT="#a7b4b6"
COLOR_ERROR="#ffb4ab"
COLOR_WARNING="#f4c46b"
COLOR_TERTIARY="#9eccf1"

if command -v jq >/dev/null 2>&1 && [[ -r "$PALETTE_PATH" ]] && jq -e . "$PALETTE_PATH" >/dev/null 2>&1; then
    MODE="$(jq -r '.mode // "dark"' "$PALETTE_PATH")"
    [[ "$MODE" == "light" ]] || MODE="dark"
    if jq -e ".\"$MODE\"" "$PALETTE_PATH" >/dev/null 2>&1; then
        read_tok() {
            local val
            val="$(jq -r ".\"$MODE\".\"$1\" // empty" "$PALETTE_PATH")"
            [[ -n "$val" ]] && echo "$val"
        }
        v="$(read_tok surface)"; [[ -n "$v" ]] && COLOR_SURFACE="$v"
        v="$(read_tok onSurface)"; [[ -n "$v" ]] && COLOR_SURFACE_TEXT="$v"
        v="$(read_tok onSurfaceVariant)"; [[ -n "$v" ]] && COLOR_SURFACE_VARIANT_TEXT="$v"
        v="$(read_tok error)"; [[ -n "$v" ]] && COLOR_ERROR="$v"
        v="$(read_tok warning)"; [[ -n "$v" ]] && COLOR_WARNING="$v"
        v="$(read_tok tertiary)"; [[ -n "$v" ]] && COLOR_TERTIARY="$v"
        echo "Palette: read '$MODE' tokens from $PALETTE_PATH"
    else
        echo "Palette: $PALETTE_PATH has no '$MODE' section -- using packaged dark fallbacks." >&2
    fi
else
    echo "Palette: $PALETTE_PATH not found/readable/valid JSON (or jq missing) -- using packaged dark fallbacks." >&2
fi

# ---- install ---------------------------------------------------------------

echo "Installing qml-rice-ascii SDDM theme:"
echo "  $SRC -> $DEST_OUT"

mkdir -p "$DEST_OUT"
if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$SRC/" "$DEST_OUT/"
else
    rm -rf "$DEST_OUT"
    mkdir -p "$DEST_OUT"
    cp -r "$SRC/." "$DEST_OUT/"
fi

cat > "$THEME_CONF_OUT" <<EOF
# Generated by scripts/install-sddm-ascii-theme.sh -- do not hand-edit;
# re-run the installer after the owner's palette changes to refresh this.
[General]
ColorSurface=$COLOR_SURFACE
ColorSurfaceText=$COLOR_SURFACE_TEXT
ColorSurfaceVariantText=$COLOR_SURFACE_VARIANT_TEXT
ColorError=$COLOR_ERROR
ColorWarning=$COLOR_WARNING
ColorTertiary=$COLOR_TERTIARY
BackgroundEnabled=false
BackgroundImage=
EOF

echo "Wrote $THEME_CONF_OUT"

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo
    echo "--dry-run complete. Generated theme.conf:"
    echo "-----------------------------------------"
    cat "$THEME_CONF_OUT"
    exit 0
fi

chmod -R go+rX "$DEST_OUT"

# ---- /etc/sddm.conf.d/zz-qml-rice.conf -------------------------------------
#
# This machine already has BOTH /etc/sddm.conf.d/10-impasto.conf (Current=
# impasto) and /etc/sddm.conf.d/theme.conf (Current=ltmnight). SDDM reads
# /etc/sddm.conf.d/ in ALPHABETICAL order, each file overriding the ones
# before it, so whichever [Theme] Current= sorts LAST wins. "zz-" sorts
# after both "10-" and "t" (ASCII 'z' > '1' and 'z' > 't'), so
# zz-qml-rice.conf wins without touching either existing file.
mkdir -p "$CONF_DIR"
cat > "$CONF_FILE" <<EOF
[Theme]
Current=qml-rice-ascii
EOF

echo
echo "Installed, and wrote $CONF_FILE:"
echo "  [Theme]"
echo "  Current=qml-rice-ascii"
echo
echo "This machine still has /etc/sddm.conf.d/10-impasto.conf (Current=impasto)"
echo "and /etc/sddm.conf.d/theme.conf (Current=ltmnight) -- this script does NOT"
echo "delete or edit either. SDDM reads /etc/sddm.conf.d/ alphabetically, each"
echo "file overriding the ones before it, and 'zz-qml-rice.conf' sorts after"
echo "both, so it wins."
echo
echo "To revert to whichever of those was active before:"
echo "  sudo rm $CONF_FILE"
echo
echo "To preview safely first, in a window (not headless), without touching"
echo "/etc or /usr at all:"
echo "  sddm-greeter-qt6 --test-mode --theme $SRC"
