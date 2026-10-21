#!/usr/bin/env bash
# Region-select a screenshot and open it in Google Lens via a throwaway image
# host. Uploads the image to a third party (uguu.se) -- opt out by removing
# the SUPER+SHIFT+A binding in hyprland/keybinds.lua if you don't want that.
grim -g "$(slurp)" /tmp/image.png
imageLink=$(curl -sF files[]=@/tmp/image.png 'https://uguu.se/upload' | jq -r '.files[0].url')
xdg-open "https://lens.google.com/uploadbyurl?url=${imageLink}"
rm /tmp/image.png
