# qml-rice-dots

A minimalistic, contextual Hyprland desktop for people starting out with
Hyprland: a [Quickshell](https://quickshell.org) shell (`shell/`), a cleaned
generic [Hyprland](https://hyprland.org) Lua config (`hypr/`), a beautiful
terminal, and a handful of opt-in `dots/` modules (zsh, fastfetch, GTK/Qt
theming, matugen wallpaper-colour pipeline) that together reproduce one
consistent look end to end. An Arch Linux installer and a `qml-rice` updater
TUI (Go, [Bubble Tea](https://github.com/charmbracelet/bubbletea)) tie it all
together so a fresh laptop install visually matches the reference desktop.

Arch Linux only. Everything the installer touches is backed up first.

Gaming: Hyprland latency rules and a Steam/CS2 launch setup for NVIDIA are in
[`gaming/`](gaming/README.md).

## Screenshots

_placeholder — add screenshots of the shell (control centre, launcher,
dashboard, notifications), the terminal, and the GTK/Qt look here once
available._

## What the desktop looks like

| Layer | Look | Module |
|---|---|---|
| Terminal | kitty, dark low-saturation palette, CaskaydiaCove Nerd Font | `kitty` |
| Shell | zsh + starship prompt + fzf/zoxide, eza/bat/btop aliases | `zsh` |
| Greeting | fastfetch with a width-aware ASCII logo | `fastfetch` |
| GTK 3/4 | adw-gtk3-dark theme, Papirus-Dark icons, dark preference | `gtk` |
| Qt | qt5ct/qt6ct + Kvantum (KvArcDark) so Qt apps match GTK | `qt` |
| Cursor | Bibata-Modern-Classic, 24px | `gtk` |
| Colour pipeline | matugen derives terminal/GTK/Hyprland-border colours from your wallpaper | `matugen` |
| Files | Thunar with generic `$HOME`-relative bookmarks | `thunar` |
| Wallpaper | a locally-generated fallback gradient on first boot; bring your own set after | `wallpapers` |
| Login screen (optional, off by default) | SDDM + the `ltmnight-sddm-theme` AUR theme | `sddm` |

See [`dots/`](dots/) for the module sources and
[`packages/modules/`](packages/modules/) for their package lists.

## Requirements

- Arch Linux (or an Arch derivative with pacman + the AUR)
- An AUR helper (`paru` or `yay`) -- the installer offers to build `paru` if
  neither is present
- `go` (for building the `qml-rice` TUI from source; installed automatically
  as part of `packages/arch.txt` unless you pass `--no-deps`)
- Not root -- `install.sh` refuses to run as root

Every other dependency (Hyprland, Quickshell, fonts, etc.) is listed in
[`packages/arch.txt`](packages/arch.txt) and
[`packages/aur.txt`](packages/aur.txt) and installed for you.

## Install

```sh
git clone <this-repo-url> qml-rice-dots
cd qml-rice-dots
./install.sh
```

Flags:

- `--dry-run` -- print every action without touching the filesystem or
  running pacman/paru/go/chsh/sudo. Safe to run to see what would happen.
- `--yes` -- don't prompt for confirmation. Without `--modules`/`--all`, this
  picks the default module set (everything except `sddm`).
- `--no-deps` -- skip package installation (assume dependencies are already
  present).
- `--all` -- select every module, including `sddm`.
- `--modules kitty,zsh,gtk,...` -- comma-separated module list, skips the
  interactive checklist. Valid names: `hypr`, `shell`, `kitty`, `zsh`,
  `fastfetch`, `gtk`, `qt`, `matugen`, `thunar`, `wallpapers`, `sddm`.

Without any of `--yes`/`--all`/`--modules`, the installer shows an
interactive numbered checklist (plain `read`, no dependencies) so you can
pick modules by hand; Enter alone selects the default set.

### First login

1. Run `./install.sh` (or pick modules interactively).
2. If you selected the `zsh` module, the installer offers to `chsh` you into
   zsh -- say yes, or run it later yourself.
3. Log out and back in (or `hyprctl reload`) to pick up the Hyprland config.
4. Open a terminal -- fastfetch runs automatically and the wallpaper module
   has already seeded a fallback gradient + matugen colours so nothing looks
   gray on first boot. Drop your own wallpapers into `~/Pictures/wallpapers`
   and re-run `matugen image <file>` (or the shell's wallpaper picker, once
   `shell/` is vendored) whenever you want to change the palette.

What it does, in order: checks you're on Arch and not root, installs
dependencies (offering to bootstrap `paru` if you have no AUR helper), backs
up any existing `~/.config/hypr` to `~/.config/hypr.backup-<timestamp>`,
clones itself to `~/.local/share/qml-rice` (the canonical install location --
if you already cloned there, it's used in place), copies the Hyprland config
into `~/.config/hypr` (never overwriting your `custom/*.lua` overrides,
`monitors.lua`, or `hyprlock/colors.conf` if they already exist), installs
bundled fonts, drops `~/.config/hypr/qml-rice-binds.lua` (already wired up by
`hyprland.lua`, no manual edit needed), and builds+installs the `qml-rice`
TUI to `~/.local/bin/qml-rice`.

Reload Hyprland (`hyprctl reload`) or re-login afterwards.

### Install location

- **Shell**: `~/.local/share/qml-rice/shell` (the `shell/` subtree of the
  git clone at `~/.local/share/qml-rice`).
- **Hyprland config**: **copied** into `~/.config/hypr`, not symlinked.

Why a copy and not a symlink: `custom/*.lua` under `~/.config/hypr/custom/`
is explicitly the user-override layer (see `hyprland/lib/init.lua`) and is
expected to diverge from the repo per-machine. Symlinking the whole
`~/.config/hypr` directory back into the git clone would mean either (a) your
local edits live inside the tracked clone, where `qml-rice update`'s `git
pull` could stomp them, or (b) you can't edit `custom/*.lua` without editing
the "package". Copying keeps the deployed config and the git clone
independent: `qml-rice update` re-deploys only the *managed* files
(`hyprland.lua`, `hyprland/**`) and always leaves `custom/**`, `monitors.lua`,
and `hyprlock/colors.conf` alone unless they're untouched since the last
deploy (tracked via a checksum manifest -- see `tui/internal/manifest`).

## Updating

```sh
qml-rice            # interactive TUI: status / update / rollback / modules / doctor
qml-rice status      # print install status and exit
qml-rice doctor       # environment checks (binaries, shell running, hyprctl configerrors)
qml-rice update --yes # fetch, show changelog, back up, pull, re-sync packages, restart shell
qml-rice rollback --yes # restore the newest backup + the commit before HEAD
```

Before overwriting anything under `~/.config/hypr`, `qml-rice update` checks
each managed file's checksum against the manifest recorded at the last
deploy. If a file changed since then (you edited it, or something else did),
it's left alone and reported instead of silently overwritten -- rerun with
the in-TUI overwrite toggle (`o` on the Update screen) if you want it
replaced anyway.

`qml-rice ipc <args>` and `qml-rice restart-shell` are thin passthroughs used
by the shipped keybinds (`qml-rice ipc control-center toggle`, etc.) and by
`CTRL+SUPER+R` -- you shouldn't need to call them directly.

## Uninstall

```sh
./uninstall.sh
```

Removes `qml-rice-binds.lua`, the `qml-rice` binary, and the bundled fonts,
then restores the newest `~/.config/hypr.backup-*` (if any) over
`~/.config/hypr`. Leaves the git clone at `~/.local/share/qml-rice` in place
in case you want to reinstall; remove it yourself if you don't.

## Keybind cheat sheet

Generated from `hypr/hyprland/keybinds.lua` and
`hypr/qml-rice-binds.lua` (installed by `install.sh`).

### qml-rice shell

| Bind | Action |
|---|---|
| `SUPER + SHIFT + A` | Control centre |
| `SUPER + SHIFT + Space` | App launcher |
| `SUPER + CTRL + N` | Notifications |
| `SUPER + SHIFT + V` | Clipboard history |
| `SUPER + SHIFT + P` | Power menu |
| `SUPER + SHIFT + Comma` | Settings |
| `SUPER + W` | Wallpaper picker (press again to close) |
| `SUPER + SHIFT + W` | Wallpapers |
| `XF86AudioRaiseVolume` / `XF86AudioLowerVolume` | Volume up/down (with OSD) |
| `XF86AudioMute` | Mute |

### Base Hyprland config

| Bind | Action |
|---|---|
| `SUPER + SUPER_L` | Toggle search |
| `SUPER + Tab` | Toggle overview |
| `SUPER + A` | Toggle left sidebar |
| `SUPER + N` | Toggle right sidebar |
| `SUPER + Slash` | Toggle cheatsheet |
| `SUPER + K` | Toggle on-screen keyboard |
| `SUPER + M` | Toggle media controls |
| `SUPER + G` | Toggle widget overlay |
| `SUPER + J` | Toggle bar |
| `CTRL + ALT + Delete` | Toggle session menu |
| `CTRL + SUPER + T` | Change wallpaper |
| `CTRL + SUPER + ALT + T` | Random wallpaper |
| `CTRL + SUPER + SHIFT + D` | Toggle light/dark mode |
| `CTRL + SUPER + R` | Restart the qml-rice shell |
| `CTRL + SUPER + P` | Cycle panel family |
| `SUPER + SHIFT + S` | Screen snip |
| `SUPER + SHIFT + A` | Reverse image search (uploads to a third party, uguu.se) |
| `SUPER + SHIFT + X` | OCR selection -> clipboard |
| `SUPER + SHIFT + C` | Pick a color -> clipboard |
| `Print` / `CTRL + Print` | Screenshot -> clipboard / clipboard + file |
| `SUPER + arrows` | Focus window in direction |
| `SUPER + SHIFT + arrows` | Move window in direction |
| `SUPER + 0-9` | Focus workspace |
| `SUPER + ALT + 0-9` | Move window to workspace |
| `SUPER + Q` | Close window |
| `SUPER + D` / `SUPER + F` | Maximize / fullscreen |
| `SUPER + ALT + Space` | Float/tile |
| `SUPER + S` | Toggle scratchpad |
| `SUPER + L` | Lock session |
| `SUPER + SHIFT + L` | Suspend |
| `SUPER + Return` | Terminal (kitty) |
| `SUPER + T` / `SUPER + E` / `SUPER + C` / `SUPER + X` / `SUPER + I` | Terminal / files / editor / text editor / settings (first-available fallback chain, see `hyprland/variables.lua`) |
| `XF86MonBrightness{Up,Down}` | Brightness |
| `XF86Audio{Next,Prev,Play,Pause}` | Media transport |

Everything under `custom/*.lua.example` is yours to copy to `custom/*.lua`
and extend -- it's never overwritten by `qml-rice update`.

## Fonts

The `fonts` module (on by default) installs every font family the shell and
dots reference, so a fresh install never falls back to a substitute face.
It's split between packages and files vendored directly in this repo under
[`fonts/`](fonts/):

| Family | Where it's used | Source | Licence |
| --- | --- | --- | --- |
| Gamja Flower | shell `fontFamily`/`handFontFamily` default, hyprlock | AUR: `ttf-gamja-flower` | OFL |
| Geist | shell general UI (alt font) | AUR: `ttf-geist` | OFL-1.1 |
| Geist Mono | shell `monoFontFamily` default | AUR: `ttf-geist-mono` | OFL-1.1 |
| Instrument Serif | shell `displayFontFamily` (dashboard clock) | vendored: [`fonts/Instrument-Serif/`](fonts/Instrument-Serif/) | OFL-1.1 |
| Bitcount Single | shell `clockFontFamily` default | vendored: [`fonts/Bitcount-Single/`](fonts/Bitcount-Single/) | OFL-1.1 |
| Fraunces | shell typography option | vendored: [`fonts/Fraunces/`](fonts/Fraunces/) | OFL-1.1 |
| Newsreader | shell typography option | vendored: [`fonts/Newsreader/`](fonts/Newsreader/) | OFL-1.1 |
| JetBrainsMono Nerd Font (+ NL/Mono/Propo variants) | shell icon glyphs (wifi/volume `md-*` codepoints) | official repo: `ttf-jetbrains-mono-nerd` | OFL-1.1 |
| CaskaydiaCove Nerd Font | `dots/kitty/kitty.conf` terminal font | official repo: `ttf-cascadia-code-nerd` | OFL-1.1 |
| Symbols Nerd Font | fontconfig fallback glyph source | official repo: `ttf-nerd-fonts-symbols` | OFL-1.1 |
| Material Symbols Rounded | `hypr/hyprlock/colors.conf`'s `$font_material_symbols` | official repo: `ttf-material-symbols-variable` | Apache-2.0 |

The four vendored families are Google Fonts (SIL Open Font License 1.1);
each `fonts/<Family>/` directory carries the exact `.ttf`(s) plus that
family's `OFL.txt`, with the copyright line matched to what's embedded in
the font's own `name` table. `install.sh`'s `fonts` module (and `qml-rice
update`, via the same `Fonts` module flag) copies every `fonts/*/*.ttf` into
`${XDG_DATA_HOME:-~/.local/share}/fonts/qml-rice/` and runs `fc-cache -f` on
it; `uninstall.sh` removes that whole directory. Gamja
Flower/Geist/Geist Mono and the Nerd/Material Symbols packages are declared
in `packages/modules/fonts.aur.txt` and `packages/modules/fonts.arch.txt`
respectively, so they only install when the `fonts` module is selected.

## Troubleshooting

- **Nothing happens on Hyprland reload / config errors banner**: run
  `hyprctl configerrors` (also checked by `qml-rice doctor`).
- **Lockscreen didn't lock / shell crashed and `SUPER+L` does nothing**: fall
  back to a direct dispatch, bypassing the shell's `quickshell:lock` global:
  ```sh
  hyprctl --instance 0 dispatch 'hl.dsp.exec_cmd("hyprlock")'
  ```
- **Monitor layout wrong after using `nwg-displays`**: the Lua config only
  re-applies monitor rules to *newly connected* outputs on reload; the
  watcher in `custom/scripts/nwg-monitor-apply.sh` (started by
  `hyprland/execs.lua`) re-applies `monitors.lua` live whenever nwg-displays
  saves it. If it's not running, `pkill -f nwg-monitor-apply` and Hyprland's
  `hyprland.start` hook will start a fresh one on next reload/relogin.
  Alternatively, `hyprctl dispatch '(function() dofile("$HOME/.config/hypr/monitors.lua") end)()'`.
  See `hyprland/general.lua`'s note about why an empty `output=""` rule
  otherwise wins.
- **`qml-rice` command not found after install**: `go` wasn't installed when
  `install.sh` ran (check with `pacman -Q go`). Install it and build
  manually: `(cd ~/.local/share/qml-rice/tui && go build -o ~/.local/bin/qml-rice ./cmd/qml-rice)`.
- **A file I edited got overwritten**: it shouldn't -- `qml-rice update`
  checksums every managed file against the manifest from the last deploy and
  skips anything that changed, reporting it instead. If you deliberately
  want the repo's version back, use the overwrite toggle in the Update
  screen, or `rm` the file and rerun `install.sh`.

## Credits

- [end4 / illogical-impulse (dots-hyprland)](https://github.com/end-4/dots-hyprland) --
  the original Hyprland Lua config and Quickshell shell this project's
  Hyprland config is derived from. GPL-3.0.
- The Odyssey Quickshell shell fork -- the direct upstream of `shell/`
  (vendored separately; see `shell/README.md`).
- [Quickshell](https://quickshell.org) -- the shell toolkit.
- [Hyprland](https://hyprland.org) -- the compositor.
- [Bubble Tea](https://github.com/charmbracelet/bubbletea),
  [bubbles](https://github.com/charmbracelet/bubbles), and
  [lipgloss](https://github.com/charmbracelet/lipgloss) -- the `qml-rice` TUI.

## License

GPL-3.0 (see [`LICENSE`](LICENSE)). `shell/` (once vendored) carries its own
GPL-3.0 `LICENSE`, matching this repo's, because it derives from end4's
GPL-3.0 dots-hyprland/Quickshell config.
