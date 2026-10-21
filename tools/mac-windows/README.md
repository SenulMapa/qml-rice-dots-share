# Layer 4: windows, layout, traffic lights, motion

All in `hypr/hyprland/mac.lua`, loaded by `hyprland.lua` **after** `shellOverrides.main` and `glass`.
Why last: `shellOverrides/main.lua` (shell-managed) pins `general.layout = "dwindle"`, rounding 14, gaps 8/10 and
wins over `general.lua`; the live `general.lua` has also drifted (shadow range 40, etc.). mac.lua overrides
without editing either.

## What it does
- Layout: `master`, mfact 0.62, orientation left, new windows to the right stack, lone window fills the screen
  (workspace rules `w[tv1]`/`f[1]`: no gaps, no rounding, no shadow). Super+; / Super+' now do `mfact -/+0.05`.
  Window rules for dialogs (rules.lua) are untouched.
- Chrome: rounding 11, shadow range 48 / offset 0,16 / power 2, focused 40% black, inactive 15%. `border_size 0`.
- Motion: open ~200 ms ease-out popin 94%, close ~130 ms popin 96%, workspace slide ~350 ms with slight overshoot,
  special workspace (minimise) = fade (also changes the Super+S scratchpad from slide to fade).
- Minimise: **Super+Ctrl+M** = `mac-minimize.sh` (move active window silently to `special:minimized`);
  **Super+Ctrl+Shift+M** = `mac-restore.sh` (most recent minimised window back to the current workspace).
  `mac-restore.sh 0xADDR` restores a specific one (dock). Super+M (media), Super+Shift+M, Super+Alt+M (mutes) untouched.
- Traffic lights: hyprbars config, guarded by `pcall`/`hl.plugin.hyprbars`, so the config loads fine without the plugin.

## Hyprbars
Needs the plugin: run `tools/mac-windows/install-hyprbars.sh` (owner, interactive; hyprpm builds in
`~/.local/share/hyprpm`; `hyprpm update` may ask for sudo). It is not built yet (`hyprpm list` empty, headers present
at /usr/include/hyprland). mac.lua runs `hyprpm reload -n` on `hyprland.start`, and the plugin reloads the config
when it loads, which adds the bars.
Config uses hyprbars' Lua API (`hl.config{plugin={hyprbars=...}}`, `hl.plugin.hyprbars.add_button`, window rule
`hyprbars:no_bar`), verified against upstream README/source on `main`. hyprpm picks the tag matching the running
0.56.2; if the build fails, the plugin is unusable. No-bar classes: org.gnome.*, org.gtk.*, nautilus, code, discord,
slack, spotify, steam, quickshell/qs; extend the regex in mac.lua.
Known limits: button spacing is `bar_button_padding` (8); hover glyphs are text (x - +) at 62% of 12 px; the circles
are squares-with-rounding drawn by the plugin (not verified round); inactive buttons grey.
Fallback if hyprbars cannot be used (design note only, no code): a shell layer-shell overlay (Quickshell) that tracks the
focused window geometry from Hyprland IPC and draws three circles; clicks call the same close / mac-minimize.sh /
fullscreen actions. Cost: no reserved bar space, needs per-window geometry events.

## Apply / revert / check
`apply.sh` copies mac.lua + two scripts into `~/.config/hypr/hyprland/` and inserts one `require("hyprland.mac")` line after
`require("hyprland.glass")` in `~/.config/hypr/hyprland.lua` (backup in `~/.local/state/qml-rice/mac-windows/<stamp>/`).
It never reloads; run `hyprctl reload` afterwards. `revert.sh [stamp]` restores exactly. `check.sh` = syntax, keys, wiring.
install.sh already syncs `hypr/hyprland/` (incl. mac.lua and scripts) and the repo `hyprland.lua` requires it.
Untested live: `window = "address:..."` in `hl.dsp.window.move`, `w[tv1]` workspace-rule selector, `mfact` layout msg.
