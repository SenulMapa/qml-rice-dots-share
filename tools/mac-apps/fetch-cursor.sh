#!/usr/bin/env bash
# fetch-cursor.sh -- install the macOS cursor theme (ful1e5/apple_cursor) as an
# XCursor theme. Nothing third-party is committed: this downloads the pinned
# release asset, checks its sha256, and extracts it.
#
#   tools/mac-apps/fetch-cursor.sh [DEST]     # DEST defaults to ~/.local/share/icons
#
# Result: DEST/macOS/{index.theme,cursor.theme,cursors/}  (theme name "macOS")
#
# Hyprcursor: the v2.0.1 release ships XCursor only (no hyprcursor variant),
# so Hyprland gets XCURSOR_THEME=macOS and the GTK/gsettings names. Nothing here
# converts the theme to hyprcursor.
#
# Test hook: MAC_APPS_CURSOR_TARBALL=/path/to/macOS.tar.xz skips the download
# (the sha256 is still verified).
set -euo pipefail

VERSION="v2.0.1"
URL="https://github.com/ful1e5/apple_cursor/releases/download/${VERSION}/macOS.tar.xz"
# Pinned from the v2.0.1 download on 12 Oct 2026. GitHub's API exposes no digest
# for this asset, so this pin is trust-on-first-use against the release page.
SHA256="9c6e5e13b068ce51a9e90a9abd6ce232ec7d25d4ceb05aa8ac76efbb99c76762"

DEST="${1:-$HOME/.local/share/icons}"
MARKER=".qml-rice-cursor"
THEME="macOS"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/mac-apps-cursor.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

tarball="$tmp/macOS.tar.xz"
if [ -n "${MAC_APPS_CURSOR_TARBALL:-}" ]; then
    cp -f "$MAC_APPS_CURSOR_TARBALL" "$tarball"
else
    curl -fsSL --max-time 300 -o "$tarball" "$URL"
fi

got=$(sha256sum "$tarball" | cut -d' ' -f1)
if [ "$got" != "$SHA256" ]; then
    echo "fetch-cursor: sha256 mismatch for $URL" >&2
    echo "  want $SHA256" >&2
    echo "  got  $got" >&2
    exit 1
fi

# Extract into a private staging dir, never into DEST directly.
stage="$tmp/stage"
mkdir -p "$stage"
tar -xJf "$tarball" -C "$stage"
[ -f "$stage/$THEME/cursors/arrow" ] || { echo "fetch-cursor: archive has no $THEME/cursors/arrow" >&2; exit 1; }

mkdir -p "$DEST"
rm -rf "$DEST/$THEME.new"
cp -a "$stage/$THEME" "$DEST/$THEME.new"
printf '%s %s\n' "$VERSION" "$SHA256" > "$DEST/$THEME.new/$MARKER"
rm -rf "$DEST/$THEME.old"
[ -e "$DEST/$THEME" ] && mv "$DEST/$THEME" "$DEST/$THEME.old"
mv "$DEST/$THEME.new" "$DEST/$THEME"
rm -rf "$DEST/$THEME.old"

echo "fetch-cursor: installed $THEME $VERSION into $DEST/$THEME"
