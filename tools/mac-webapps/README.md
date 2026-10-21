# Layer 6: web-app overlays (Gemini first)

Gemini desktop's main feature is a window you summon and dismiss from anywhere.
This layer does the same with Brave's `--app=` mode: each web app gets its own
Brave profile, its own window class, and a Hyprland special workspace that acts
as a floating overlay. One global key shows or hides it.

## Files

| Path | Source | Purpose |
| --- | --- | --- |
| `tools/mac-webapps/webapps.json` | hand-written | The manifest: the only file you edit to add an app. |
| `tools/mac-webapps/gen.sh` | hand-written | Generates everything below from the manifest (needs `jq`). |
| `dots/webapps/.local/bin/webapp-<id>` | generated | Launcher: `brave --app=<url> --class=webapp-<id> --user-data-dir=~/.local/share/qml-rice/webapps/<id>`. |
| `dots/webapps/.local/bin/webapp-<id>-toggle` | generated | Toggle: if no matching window exists, launch it and reveal it; otherwise show or hide `special:webapp-<id>`. |
| `dots/webapps/.local/share/applications/webapp-<id>.desktop` | generated | Launcher-menu entry. `Icon=webapp-<id>`. |
| `hypr/hyprland/webapps.lua` | generated | Window rules (float, `special:webapp-<id> silent`, size, centre) and the toggle bind. |
| `hypr/hyprland.lua` | hand-written | One `require("hyprland.webapps")` guarded by `is_file_exists`, placed after the glass blur. |
| `tools/mac-webapps/apply.sh` / `revert.sh` | hand-written | Live-desktop apply and exact restore. |
| `tools/mac-webapps/check.sh` | hand-written | Self-test. Runs in a throwaway HOME with stubbed `hyprctl` and `brave`. |

The `dots/webapps` files are committed, so `install.sh --modules=webapps` (or the default set) installs them on both machines.

## Keybind

**Gemini: `SUPER + ALT + G`.**

- `SUPER + G` is taken: `hypr/hyprland/keybinds.lua` binds it to `quickshell:overlayToggle` (widget overlay).
- `SUPER + Space` is taken by a live custom bind (`~/.config/hypr/custom/keybinds.lua`).
- `SUPER + ALT + G` is free in the repo and in the live config, and keeps the G mnemonic.

`check.sh` fails if a manifest key is already bound in the repo.

## Apply and revert

```sh
tools/mac-webapps/apply.sh --dry-run   # show what would change
tools/mac-webapps/apply.sh             # install, idempotent, backed up
tools/mac-webapps/revert.sh            # restore the newest backup exactly
tools/mac-webapps/revert.sh <stamp>    # or a specific one
```

`apply.sh` writes only:

- `~/.local/bin/webapp-*` and `~/.local/share/applications/webapp-*.desktop`
- `~/.config/hypr/hyprland/webapps.lua`
- one 4-line block in `~/.config/hypr/hyprland.lua`, inserted after `require("hyprland.glass")`

Backups go to `~/.local/state/qml-rice/mac-webapps/<stamp>/` (`manifest.tsv` plus `files/`). The manifest records created directories too, so revert removes them. The apply does **not** reload Hyprland. Run `hyprctl reload` or log out and back in before the bind exists.

## Adding an app

1. Add an object to `webapps.json`: `id` (lowercase, dashes), `name`, `url` (https), `key` (`MOD + KEY`, unbound), `size` (`WxH`).
2. `tools/mac-webapps/gen.sh`
3. `tools/mac-webapps/check.sh`
4. Re-run `apply.sh` on the live desktop.

## Window class on Wayland

`--class=webapp-<id>` sets the X11 `WM_CLASS`, which only matters under XWayland. On native Wayland, Chromium derives `app_id` for `--app` windows from the URL, typically `brave-<host>__<path>-<profile>` (for example `brave-gemini.google.com__app-Default`). **This has not been verified on this machine**: no Brave window was opened, because the desktop is live. The generated rules and the toggle therefore match both forms. If a window still shows up under another class, check `hyprctl clients -j | jq '.[].class'` after launching and add that class to `CLASS_RE` in the generator.

## Known limits

- The `.desktop` file runs `webapp-<id>-toggle` by bare name, so `~/.local/bin` must be on the launcher's `PATH`. The Hyprland bind uses an absolute `$HOME` path and does not depend on this.
- The toggle issues `hyprctl dispatch 'hl.dsp.workspace.toggle_special("webapp-<id>")'`. This follows the Lua-expression style of `hypridle.conf`, and has not been run against a live compositor.
- `Icon=webapp-<id>` has no image shipped here. Layer 2 (icon theme `qml-rice-mac`) is expected to provide it. Until then the entry shows the generic icon.
- Brave must be installed (`brave-bin`, listed in `packages/modules/webapps.aur.txt`). The launcher exits with an error if `brave` is missing.
- Each launch is a separate Brave profile, so Gemini logins are kept apart from the main browser.

## Later: Windows-only apps (not built)

WinApps (a Windows VM whose apps appear as normal Hyprland windows) is the planned path for Windows-only apps. It costs about 4 GB of the 16 GB RAM, so it is deferred until the owner names a specific app that needs it.
