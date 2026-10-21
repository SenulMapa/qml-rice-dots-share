-- Mission Control (macOS F3): opens the shell's overlay (shell/missioncontrol).
--
-- Shortcut name exported for other branches: quickshell:missionControlToggle
--   (registered in shell/core/ShellCompatShortcuts.qml). The gestures branch
--   may dispatch the same global for a 3-finger swipe up. Do not add that
--   here; mac-gestures.lua and general.lua belong to that branch.
-- Super+Up is NOT touched: it stays "focus up".
--
-- Loaded from hyprland.lua behind an is_file_exists guard.

hl.bind("F3", hl.dsp.global("quickshell:missionControlToggle"),
    { description = "Shell: Mission Control" })
