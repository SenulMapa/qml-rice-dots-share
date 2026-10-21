#!/bin/bash
# Restore exactly the files and gsettings saved by apply.sh (latest backup, or the given stamp).
# Files that did not exist before apply are removed again.
set -euo pipefail
B="$HOME/.local/state/qml-rice/mac-text"
ST="$B/${1:-$(ls -1 "$B" | sort | tail -1)}"
[ -d "$ST" ] || { echo "no backup at $ST"; exit 1; }
if [ -d "$ST/files" ]; then
  ( cd "$ST/files" && find . -type f -print0 ) | while IFS= read -r -d '' rel; do
    dst="$HOME/${rel#./}"; mkdir -p "$(dirname "$dst")"; cp -a "$ST/files/${rel#./}" "$dst"; done
fi
while IFS= read -r rel; do [ -n "$rel" ] && rm -f "$HOME$rel"; done < "$ST/absent"
for k in font-name font-antialiasing font-hinting; do
  gsettings set org.gnome.desktop.interface "$k" "$(tr -d "'" < "$ST/gsettings-$k")"; done
fc-cache -f >/dev/null 2>&1 || true
echo "reverted from $ST"
