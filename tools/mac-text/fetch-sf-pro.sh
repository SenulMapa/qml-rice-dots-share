#!/bin/bash
# Fetch Apple's SF Pro from developer.apple.com/fonts into the user font dir. Never committed (Apple licence).
set -euo pipefail
DEST="$HOME/.local/share/fonts/sf-pro"
[ "${1:-}" = --dest ] && DEST="$2"
URL=https://devimages-cdn.apple.com/design/resources/download/SF-Pro.dmg
if ls "$DEST"/SF-Pro-Text-Regular.otf >/dev/null 2>&1; then echo "SF Pro already in $DEST"; exit 0; fi
command -v 7z >/dev/null || { echo "7z missing; skipping SF Pro (Inter fallback)"; exit 2; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
curl -fsSL --max-time 300 -o "$W/sf.dmg" "$URL" || { echo "SF Pro download failed; Inter fallback"; exit 2; }
echo "SF-Pro.dmg sha256 $(sha256sum "$W/sf.dmg" | cut -d' ' -f1)"
7z x -y -o"$W/dmg" "$W/sf.dmg" >/dev/null
PKG=$(find "$W/dmg" -name '*.pkg' | head -1); [ -n "$PKG" ] || { echo "no pkg in dmg"; exit 2; }
7z x -y -o"$W/pkg" "$PKG" >/dev/null
PAY=$(find "$W/pkg" -name 'Payload*' | head -1)
7z x -y -o"$W/pay" "$PAY" >/dev/null
CPIO=$(find "$W/pay" -type f | head -1)
7z x -y -o"$W/fonts" "$CPIO" >/dev/null 2>&1 || (cd "$W/fonts" && cpio -idm < "$CPIO" 2>/dev/null)
mkdir -p "$DEST"
find "$W/fonts" \( -name 'SF-Pro*.otf' -o -name 'SF-Pro*.ttf' \) -exec cp -f {} "$DEST/" \;
ls "$DEST"/SF-Pro-Text-Regular.otf >/dev/null || { echo "extraction found no SF Pro Text"; exit 2; }
fc-cache -f "$DEST" >/dev/null 2>&1 || true
echo "SF Pro installed to $DEST ($(ls "$DEST" | wc -l) files)"
