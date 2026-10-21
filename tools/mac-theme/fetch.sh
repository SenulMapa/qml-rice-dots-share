#!/usr/bin/env bash
# fetch.sh DEST [--browser] -- download the pinned artifacts into DEST (created if
# missing; reuse an existing one to skip downloads) and verify every sha256.
# Only curl + sha256sum run. Nothing downloaded is executed.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=pins.env
. "$HERE/pins.env"
DEST="${1:?usage: fetch.sh DEST [--browser]}"; shift || true
BROWSER=0; [ "${1:-}" = --browser ] && BROWSER=1
mkdir -p "$DEST"

get() { # get FILENAME URL SHA256
    local f="$DEST/$1"
    if [ ! -f "$f" ]; then
        echo "  fetch $1"
        curl -fsSL --retry 3 -o "$f.part" "$2"
        mv "$f.part" "$f"
    fi
    local got; got=$(sha256sum "$f" | cut -d' ' -f1)
    if [ "$got" != "$3" ]; then
        rm -f "$f"
        echo "fetch: sha256 mismatch for $1 (got $got, pinned $3); removed" >&2
        exit 1
    fi
}

GTK_RAW="https://raw.githubusercontent.com/vinceliuice/WhiteSur-gtk-theme/$WS_GTK_COMMIT/release"
KDE_RAW="https://raw.githubusercontent.com/vinceliuice/WhiteSur-kde/$WS_KDE_COMMIT/Kvantum/WhiteSur"
get "$WS_GTK_FILE"            "$GTK_RAW/$WS_GTK_FILE"           "$WS_GTK_SHA256"
get "$WS_KV_THEME.kvconfig"   "$KDE_RAW/$WS_KV_THEME.kvconfig"  "$WS_KV_CONFIG_SHA256"
get "$WS_KV_THEME.svg"        "$KDE_RAW/$WS_KV_THEME.svg"       "$WS_KV_SVG_SHA256"
if [ "$BROWSER" = 1 ]; then
    get "$WS_SRC_FILE" "https://codeload.github.com/vinceliuice/WhiteSur-gtk-theme/tar.gz/refs/tags/$WS_GTK_TAG" "$WS_SRC_SHA256"
fi
echo "fetch: all artifacts verified in $DEST"
