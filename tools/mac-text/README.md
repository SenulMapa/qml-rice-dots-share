# mac-text (Layer 1): macOS-like text rendering

What it does: one fontconfig drop-in (`dots/fontconfig/.config/fontconfig/conf.d/60-qml-rice-mac-text.conf`)
turns on grayscale AA with slight hinting and aliases `system-ui`, `-apple-system`, `BlinkMacSystemFont`
and `sans-serif` to SF Pro Text -> SF Pro -> Inter -> Noto Sans. Toolkits name `system-ui` (GTK 3/4 settings.ini,
gsettings, qt6ct, kdeglobals). FreeType stem darkening is set in `hypr/hyprland/env.lua`.

Files
- `fetch-sf-pro.sh [--dest DIR]`: downloads Apple's SF Pro .dmg, extracts the OTFs to `~/.local/share/fonts/sf-pro`
  (default). Never committed. Exit 2 = unavailable; the installer treats that as "Inter fallback" (non-fatal).
- `check.sh [--conf-dir DIR]`: fontconfig checks against a candidate conf dir; `CHECK_LIVE=1` adds the live
  session checks (env.lua, GTK, gsettings, kdeglobals, qt6ct).
- `apply.sh`: targeted, idempotent edits to the LIVE files (keys only, never whole-file overwrite). Backs up each
  touched file to `~/.local/state/qml-rice/mac-text/<stamp>/` first, and records files that did not exist.
- `revert.sh [stamp]`: restores exactly from a stamp (default: latest) and removes files that apply created.

Apply / revert (owner-triggered only)
- `bash tools/mac-text/apply.sh`, then log out and back in (FREETYPE_PROPERTIES needs a fresh session).
- `bash tools/mac-text/revert.sh` (or pass a stamp), then log out and back in.
- Fresh installs: `bash install.sh --modules=fontconfig,fonts,gtk,qt` (repo defaults; no apply needed).

Known limits
- Without SF Pro, every alias resolves to Inter and checks still pass.
- `gsettings` values are restored by value; the GLib keyfile store itself is not removed by revert.
- Hyprland `hl.env` changes need a session restart (no `hyprctl reload` for env).
