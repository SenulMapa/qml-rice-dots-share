# mac-apps (Layer 3: consistent apps)

What it does:

- **Electron/CEF native Wayland** for Slack, Discord and Spotify, using the flags
  `--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations`. Slack and
  Discord also get `--password-store=gnome-libsecret` (Electron keyring, see
  `electron-flags.conf` in the rice notes).
- **macOS cursor theme** (`ful1e5/apple_cursor` v2.0.1, XCursor only) at size 24,
  set as the XCursor theme for Hyprland, the GTK `settings.ini` files and gsettings.
- **Qt consistency:** `kdeglobals` and `qt6ct.conf` both get icon theme
  `qml-rice-mac` and UI font `system-ui,11`. The Qt platform theme stays `kde`
  unless you pass `--qt6ct`.

Files:

| File | Role |
|---|---|
| `apply.sh [--qt6ct]` | Targeted, idempotent edits to the live HOME. Backs up first. |
| `revert.sh [STAMP]` | Exact restore from a backup. Default is the newest un-reverted one. |
| `check.sh [--home DIR] [--live]` | Automated pass/fail. `--live` is read-only (`hyprctl clients -j`). |
| `fetch-cursor.sh [DEST]` | Downloads the pinned cursor tarball, checks sha256, installs `DEST/macOS`. |
| `merge.py` | The text merges (flag lists, `.desktop` Exec lines, ini keys, `env.lua`). Stdout only. |
| `../../dots/macapps/` | Repo defaults that `install.sh` deploys (`--modules macapps`). |

## Electron flag mechanism (evidence, 12 Oct 2026)

| App | Launcher on this box | Does it read a flags file? | Hook used |
|---|---|---|---|
| Slack 4.49.89 | `/usr/bin/slack` is a symlink to `/usr/lib/slack/slack`, the raw Electron binary (its version file reads 41.2.2). No wrapper. | No. The binary never names `electron-flags.conf` or `slack-flags.conf`. | `.desktop` `Exec=` line |
| Discord 1.0.156 | `/usr/bin/discord` is a POSIX shell. It execs `~/.config/discord/app-*/Discord "$@"`. | No. The script reads no flags file. | `.desktop` `Exec=` line |
| Spotify 1.2.92 | `/usr/bin/spotify` is a bash wrapper. It reads `~/.config/spotify-flags.conf` line by line (`grep -v '^#'`, `mapfile`), then execs `/opt/spotify/spotify` (CEF). | Yes. | `~/.config/spotify-flags.conf` |

Consequences:

- A `*-flags.conf` file for Slack or Discord would do nothing, so none is written.
  The override is a user `.desktop` file, which takes precedence over
  `/usr/share/applications/`. Terminal launches of `slack`/`discord` won't get the
  flags.
- `apply.sh` merges into the existing user `slack.desktop` and `discord.desktop`
  (they already carry `--password-store=gnome-libsecret`). It keeps existing values
  and unions `--enable-features`.
- Strings in the binaries: `ozone-platform-hint` does not appear in the Slack,
  Discord or Spotify binaries (`grep -a`). `libcef.so` (Spotify) does contain
  `ozone-platform=wayland`. So the spec flag names are not confirmed by strings.
  Only a live run can confirm them, via `check.sh --live`.

## Qt platform theme decision

- `QT_QPA_PLATFORMTHEME=kde` is set in `hypr/hyprland/env.lua`. The effective
  value is `kde`. The live `hypr/modules/env.lua` says `qt6ct`, but nothing loads
  that file.
- `plasma-integration` 6.7.4 provides the KDE platform theme. `kdeglobals` carries
  the live Qt widget style (`widgetStyle=Darkly`) and colours, so switching changes
  Qt widget styling.
- Nothing in the repo requires `kde` specifically. The matugen `kde_colors` output
  goes to quickshell state, not `kdeglobals`.
- Default: keep `kde`, because switching is riskier. `--qt6ct` switches to `qt6ct`
  and sets `style=kvantum` in `qt6ct.conf`. `qt6ct-kde` and `kvantum` are installed.

## Apply and revert

```
tools/mac-apps/apply.sh            # or: apply.sh --qt6ct
tools/mac-apps/check.sh
tools/mac-apps/revert.sh           # newest backup; or revert.sh <stamp>
```

Backups go to `~/.local/state/qml-rice/mac-apps/<stamp>/` (`manifest.tsv` plus the
copied files). A run that changes nothing makes no backup, so repeated `apply` runs
don't overwrite the original backup. `revert` renames the used backup to
`<stamp>.reverted`.

Tested in a throwaway HOME with the real files copied in: apply, apply again (no-op),
check, revert, then `diff -r` against the baseline. Result: exact restore, except the
`~/.local/state/qml-rice/mac-apps` backup record itself. Also tested with `--qt6ct`,
with a missing Discord desktop file, and with a pre-existing `spotify-flags.conf`.

## Known limits

- **Relogin needed:** `hl.env` values and `XCURSOR_*` apply at Hyprland start. Restart
  Slack, Discord and Spotify to pick up their flags.
- **Cursor:** v2.0.1 ships XCursor only. There is no hyprcursor variant, so Hyprland
  gets XCursor. The tarball digest is pinned from the download itself (GitHub exposes
  no digest for this asset).
- **Icon theme:** `qml-rice-mac` is Layer 2's. Until it exists, Qt and GTK fall back
  and `check.sh` warns.
- **Colour scheme:** `apply.sh` does not change the palette. `kdeglobals` names
  `Impasto`, and `qt6ct` loads `colors/impasto.conf`, which is dark. GTK already has
  `prefer-dark`. Revisit if a light variant is ever wanted.
- **GTK 4 file:** `check.sh` fails if `~/.config/gtk-4.0/settings.ini` is missing,
  because the GTK module owns that file. `apply.sh` skips it.
- **Client-side decorations:** `WaylandWindowDecorations` may make Electron draw its
  own title bar. Layer 4 should give these apps a no-bar rule.
- **Spotify wrapper:** a trailing newline in `spotify-flags.conf` makes the Arch
  wrapper pass one empty argument. Harmless, but don't add blank lines.
- **Live acceptance is not run.** Slack, Discord and Spotify weren't running during
  the build, and nothing was launched on the live desktop. Relaunch them after apply
  and run `check.sh --live`.
