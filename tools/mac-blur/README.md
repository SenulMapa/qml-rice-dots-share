# macOS vibrancy blur

Translucent app surfaces over a saturated, slightly bright blur (not grey frost).

## What changes
- `hypr/hyprland/rules.lua`: blanket `class ".*" no_blur` removed.
- `hypr/hyprland/mac.lua` (block `mac-blur:begin..end`, loads last, overrides glass.lua):
  - blur size 10 / passes 3 (battery: 8 / 2), brightness 1.0, contrast 0.74, vibrancy 0.45,
    vibrancy_darkness 0.3, noise 0.01. glass.lua is untouched; its battery profile idea is kept (lighter on laptop).
  - `no_blur = false` for all windows, then opt-outs (later rule wins): mpv, vlc, steam_app_*, gamescope, cs2,
    libretro, Picture-in-picture, empty-class xwayland popups, and **any fullscreen window**.
  - opacity `0.94 0.90` (active/inactive) for Thunar, Nautilus, Dolphin, pavucontrol, nm-connection-editor, blueman.
    Browsers, Slack, Discord, Code stay opaque. No inactive dimming.
- `dots/kitty` `background_opacity 0.85`.
- `shell/services/AdaptiveColor.qml` `blurContrast` 0.74 (mirrors the global blur contrast).

## Performance guard
The repo has no gaming.lua / gamemode hook (only the games dashboard), so the guard is the fullscreen +
game-class opt-out rules above: games never pay for window blur. A windowed game with an unknown class
would still blur; add its class to the opt-out regex in mac.lua.

## Apply / revert
`tools/mac-blur/apply.sh` (idempotent; backs up to `~/.local/state/qml-rice/mac-blur/<stamp>`), then
`hyprctl reload` and `pkill -USR1 kitty`. `tools/mac-blur/revert.sh [stamp]` restores exactly. `check.sh` tests the repo.
Needs `tools/mac-windows` applied first (mac.lua must exist live).

## Limits
Window blur costs GPU per translucent window; 10/3 on a 5060 at 1080p is cheap, but many stacked kitty windows
at 240 Hz add up. Match key `fullscreen` is unverified against a running 0.56.2 (wrapped in pcall).
Existing kitty windows need the SIGUSR1 reload; `dynamic_background_opacity` can still override per-window.
