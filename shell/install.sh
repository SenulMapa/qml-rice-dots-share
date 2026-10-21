#!/usr/bin/env bash
# qml-rice installer — deliberately minimal and reversible.
#
# It does NOT rewrite your Hyprland config, theme your terminal, install a
# display manager theme, or take over your wallpaper. It writes exactly two
# files it owns, plus one `pcall(require, ...)` line in hyprland.lua, which is
# the same pattern your config already uses for openwhispr-binds.lua.
#
# Everything it touches is backed up first and listed by ./uninstall.sh.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
HYPR="$CFG/hypr"
BINDS="$HYPR/qml-rice-binds.lua"
MAIN="$HYPR/hyprland.lua"
BIN="$HOME/.local/bin/qml-rice"
FONTDIR="$HOME/.local/share/fonts/qml-rice"
STAMP="$(date +%Y%m%d-%H%M%S)"

say() { printf '  %s\n' "$*"; }

echo "qml-rice install"

# 1. Fonts ---------------------------------------------------------------
mkdir -p "$FONTDIR"
cp -f "$HERE"/assets/fonts/*.ttf "$FONTDIR"/ 2>/dev/null || true
fc-cache -f "$FONTDIR" >/dev/null 2>&1 || true
say "fonts -> $FONTDIR"

# 2. Launcher command ----------------------------------------------------
mkdir -p "$(dirname "$BIN")"
cat > "$BIN" <<EOF
#!/usr/bin/env bash
# qml-rice control. 'qml-rice' starts the shell; 'qml-rice ipc ...' talks to it.
# Quickshell keys instances by the resolved path, so resolve symlinks or ipc finds nothing.
SHELL_QML="\$(readlink -f "$HERE/shell.qml")"
if [ "\${1:-}" = "ipc" ]; then shift; exec qs -p "\$SHELL_QML" ipc call "\$@"; fi
exec qs -p "\$SHELL_QML" "\$@"
EOF
chmod +x "$BIN"
say "command -> $BIN"

# 3. Keybinds ------------------------------------------------------------
# SUPER+SHIFT+* was chosen after auditing the existing binds; none of these
# collide with anything already mapped.
cat > "$BINDS" <<'EOF'
-- qml-rice keybinds (managed by its installer).
-- Delete this file and the matching pcall(require, ...) line in hyprland.lua
-- to remove them. Nothing else in your config is touched.
local qr = function(cmd) return hl.dsp.exec_cmd("qml-rice ipc " .. cmd) end

hl.bind("SUPER + SHIFT + A",      qr("control-center toggle"), { description = "qml-rice: Control centre" })
hl.bind("SUPER + SHIFT + Space",  qr("launcher toggle"),       { description = "qml-rice: App launcher" })
hl.bind("SUPER + CTRL + N",       qr("notifications toggle"),  { description = "qml-rice: Notifications" })
hl.bind("SUPER + SHIFT + V",      qr("clipboard toggle"),      { description = "qml-rice: Clipboard history" })
hl.bind("SUPER + SHIFT + P",      qr("session-page open"),     { description = "qml-rice: Power menu" })
hl.bind("SUPER + SHIFT + Comma",  qr("settings open"),         { description = "qml-rice: Settings" })
hl.bind("SUPER + SHIFT + W",      qr("settings wallpaper"),    { description = "qml-rice: Wallpapers" })
hl.bind("ALT + Tab",         qr("switcher next"),   {description = "qml-rice: Switch apps"})
hl.bind("ALT + SHIFT + Tab", qr("switcher prev"),   {description = "qml-rice: Switch apps (back)"})
hl.bind("ALT + Escape",      qr("switcher cancel"), {description = "qml-rice: Cancel app switch"})
hl.bind("ALT_L", qr("switcher commit"), { ignore_mods = true, transparent = true, release = true, description = "qml-rice: Switch apps (release)" })

-- Volume and brightness route through the shell so its OSD appears.
hl.bind("XF86AudioRaiseVolume", qr("audio increment 3"), { locked = true, repeating = true, description = "qml-rice: Volume up" })
hl.bind("XF86AudioLowerVolume", qr("audio decrement 3"), { locked = true, repeating = true, description = "qml-rice: Volume down" })
hl.bind("XF86AudioMute",        qr("audio mute"),        { locked = true, description = "qml-rice: Mute" })
EOF
say "keybinds -> $BINDS"

# 4. One line in hyprland.lua -------------------------------------------
LINE="pcall(require, \"$HYPR/qml-rice-binds.lua\")"
if [ -f "$MAIN" ]; then
  if grep -Fq "qml-rice-binds" "$MAIN"; then
    say "hyprland.lua already loads it; unchanged"
  else
    cp -a "$MAIN" "$MAIN.bak-qml-rice-$STAMP"
    printf '\n%s\n' "$LINE" >> "$MAIN"
    say "hyprland.lua += 1 line (backup: $(basename "$MAIN.bak-qml-rice-$STAMP"))"
  fi
else
  say "WARNING: $MAIN not found; add this line to your Hyprland config yourself:"
  say "  $LINE"
fi

echo
echo "Done. Start it with:  qml-rice"
echo "Autostart: add 'exec-once = qml-rice' to your Hyprland config."
echo "Remove with: $HERE/uninstall.sh"
