#!/usr/bin/env bash
# Installs the qml-rice SDDM theme (ported from impasto's own SDDM theme,
# system/sddm/qml-rice/ in this repo) to /usr/share/sddm/themes/qml-rice.
#
# This script does NOT run automatically as part of any other tooling in
# this repo, and does not touch /etc/sddm.conf* itself -- it only copies
# files under /usr/share/sddm/themes/ and then prints the snippet the user
# needs to add themselves. Per this port's brief, it must be run manually,
# with sudo, by the user.
#
# Usage: sudo ./scripts/install-sddm-theme.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$REPO_ROOT/system/sddm/qml-rice"
DEST="/usr/share/sddm/themes/qml-rice"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "This installs into /usr/share/sddm/themes, which needs root." >&2
    echo "Run it again with sudo:" >&2
    echo "  sudo $0" >&2
    exit 1
fi

if [[ ! -f "$SRC/metadata.desktop" ]]; then
    echo "Cannot find the theme at $SRC (expected metadata.desktop there)." >&2
    exit 1
fi

echo "Installing qml-rice SDDM theme:"
echo "  $SRC -> $DEST"

mkdir -p "$DEST"
# rsync mirrors deletions of files removed from the source on a re-run;
# fall back to cp -r if rsync isn't installed.
if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$SRC/" "$DEST/"
else
    rm -rf "$DEST"
    mkdir -p "$DEST"
    cp -r "$SRC/." "$DEST/"
fi

chmod -R go+rX "$DEST"

echo
echo "Installed. To make SDDM use it, create /etc/sddm.conf.d/theme.conf"
echo "with:"
echo
echo "  [Theme]"
echo "  Current=qml-rice"
echo
echo "For example:"
echo "  sudo mkdir -p /etc/sddm.conf.d"
echo "  printf '[Theme]\\nCurrent=qml-rice\\n' | sudo tee /etc/sddm.conf.d/theme.conf"
echo
echo "This machine already has /etc/sddm.conf.d/theme.conf set to"
echo "'ltmnight' -- overwrite it (as above) or edit it by hand to switch."
echo "This script does not touch /etc itself."
