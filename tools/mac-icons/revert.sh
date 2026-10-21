#!/usr/bin/env bash
# Restore everything apply.sh changed. Usage: revert.sh [stamp]  (default: the stamp apply.sh recorded)
set -euo pipefail
THEME=qml-rice-mac
ICONS="$HOME/.local/share/icons"
STATE="$HOME/.local/state/qml-rice/mac-icons"
STAMP="${1:-$(cat "$STATE/applied" 2>/dev/null || ls -1 "$STATE" | grep -v '^applied$' | tail -1)}"
B="$STATE/$STAMP"
[ -d "$B" ] || { echo "no backup $B" >&2; exit 1; }
for f in .config/gtk-3.0/settings.ini .config/gtk-4.0/settings.ini .config/kdeglobals .config/qt6ct/qt6ct.conf; do
    if [ -e "$B/files/$f" ]; then mkdir -p "$HOME/$(dirname "$f")"; cp -a "$B/files/$f" "$HOME/$f"
    elif grep -qxF "$f" "$B/absent.txt" 2>/dev/null; then rm -f "$HOME/$f"; fi
done
rm -rf "$ICONS/$THEME"
[ -e "$B/theme" ] && cp -a "$B/theme" "$ICONS/$THEME"
if [ -s "$B/gsettings-icon-theme" ] && command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface icon-theme "$(tr -d "'" < "$B/gsettings-icon-theme")" || true
fi
rm -f "$STATE/applied"
echo "reverted from $B"
