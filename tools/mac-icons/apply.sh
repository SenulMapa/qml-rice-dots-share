#!/usr/bin/env bash
# Build the qml-rice-mac theme into ~/.local/share/icons and point GTK/gsettings/KDE/qt6ct at it.
# Idempotent. Backs up originals ONCE to ~/.local/state/qml-rice/mac-icons/<stamp>/ (revert.sh restores).
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
THEME=qml-rice-mac
ICONS="$HOME/.local/share/icons"
STATE="$HOME/.local/state/qml-rice/mac-icons"
MARK="$STATE/applied"
FILES=(".config/gtk-3.0/settings.ini" ".config/gtk-4.0/settings.ini" ".config/kdeglobals" ".config/qt6ct/qt6ct.conf")
mkdir -p "$STATE"

python3 -I "$D/scan.py" >/dev/null
if [ ! -f "$MARK" ]; then
    STAMP="$(date +%Y%m%d-%H%M%S)"; B="$STATE/$STAMP"; mkdir -p "$B/files"
    for f in "${FILES[@]}"; do
        if [ -e "$HOME/$f" ]; then mkdir -p "$B/files/$(dirname "$f")"; cp -a "$HOME/$f" "$B/files/$f"
        else echo "$f" >> "$B/absent.txt"; fi
    done
    if [ -e "$ICONS/$THEME" ] || [ -L "$ICONS/$THEME" ]; then cp -a "$ICONS/$THEME" "$B/theme"; else touch "$B/theme-absent"; fi
    if command -v gsettings >/dev/null 2>&1; then
        gsettings get org.gnome.desktop.interface icon-theme > "$B/gsettings-icon-theme" 2>/dev/null || true
    fi
    echo "$STAMP" > "$MARK"
    echo "backup: $B"
fi

mkdir -p "$ICONS"
python3 -I "$D/build_theme.py" --target "$ICONS/$THEME"
python3 -I "$D/set_refs.py" "$THEME"
if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface icon-theme "$THEME" || echo "gsettings set failed (no dconf?)"
fi
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -f -t "$ICONS/$THEME" >/dev/null 2>&1 || true
echo "applied. GTK apps pick it up on restart; Qt apps and the shell need a restart to reload icons."
