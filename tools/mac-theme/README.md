# mac-theme: WhiteSur dark for GTK3, GTK4/libadwaita and Qt

Makes app windows look like macOS dark mode: traffic lights on the left of GTK header bars, Mac
buttons/switches/sidebars, subtle translucency. Uses vinceliuice's WhiteSur, from **pinned prebuilt
files only**. No third-party script is ever run (`pins.env` holds every URL commit and sha256;
`fetch.sh` fails closed on a mismatch).

```
tools/mac-theme/apply.sh [--browser CHROME_DIR] [--cache DIR]
tools/mac-theme/revert.sh [STAMP]
tools/mac-theme/check.sh [--home DIR] [--browser CHROME_DIR]
```

## What is pinned and why

| Part | Source | Pin |
|---|---|---|
| GTK theme | `WhiteSur-gtk-theme` repo `release/WhiteSur-Dark.tar.xz` (the GitHub releases have no assets; the prebuilt archives are committed in `release/`) | tag `2026-09-10`, commit `99247ecd`, sha256 `98ac7545...be75f` |
| Kvantum | `WhiteSur-kde` `Kvantum/WhiteSur/WhiteSurDark.{kvconfig,svg}` | commit `cf4df59c`, per-file sha256 in `pins.env` |
| Browser (optional) | `other/firefox` from the tag's source tarball | sha256 `65516c8f...a1a2` |

**Variant: `WhiteSur-Dark`** = dark, translucent (not the `-solid` build), default blue accent (`#0860F2`),
standard scheme (not `-nord`). WhiteSur ships no graphite/neutral accent in the prebuilt set (that is only
produced by the installer's `-a` flag, which needs sassc and running its script), so blue it is. Kvantum
`WhiteSurDark` is the translucent one (`translucent_windows=true`, blur on); `WhiteSur-opaque*` is the solid twin.

## What apply.sh changes (everything is backed up first)

Backup: `~/.local/state/qml-rice/mac-theme/<stamp>/` (+ `manifest.tsv`). A run that changes nothing writes no
backup, so apply, apply, revert returns to the exact original state.

- `~/.themes/WhiteSur-Dark/` (whole dir, marker file records tag+sha).
- libadwaita: `~/.config/gtk-4.0/{gtk.css,gtk-dark.css,assets/}`. WhiteSur's `install.sh -l` does this by compiling
  Sass; the prebuilt theme instead embeds the finished CSS in `gtk-4.0/gtk.gresource` (its `gtk.css` is only a
  stub importing it, which libadwaita would never load). We unpack that gresource with `gresource extract`
  (data only) into exactly those three paths. Other files in `gtk-4.0/` and `settings.ini` content are kept.
- `settings.ini` (gtk-3.0 and gtk-4.0), targeted keys only: `gtk-theme-name=WhiteSur-Dark`,
  `gtk-decoration-layout=close,minimize,maximize:` (Mac button order, left side),
  `gtk-application-prefer-dark-theme=1`. Icon theme `qml-rice-mac`, font `system-ui`, cursor `macOS` stay as
  the other layers set them.
- gsettings: `org.gnome.desktop.interface gtk-theme='WhiteSur-Dark'` and
  `org.gnome.desktop.wm.preferences button-layout='close,minimize,maximize:'` (old values restored on revert).
  `color-scheme` is not touched (it is already `prefer-dark` on this rice).
- Qt: `~/.config/Kvantum/WhiteSurDark/` (folder named after the theme, which is how Kvantum finds it),
  `~/.config/Kvantum/kvantum.kvconfig` `[General] theme=WhiteSurDark`, and `~/.config/kdeglobals`
  `[KDE] widgetStyle=kvantum-dark`. Under `QT_QPA_PLATFORMTHEME=kde` that key is what selects the style (it was
  `Darkly`); `kvantum-dark` is Kvantum's dark-palette flavour. Qt6 only: Arch's `kvantum` ships the Qt6 plugin
  here, there is no Qt5 Kvantum style on this machine, so Qt5 apps keep their fallback.

## The matugen interaction (decision: matugen stops writing the two `gtk.css` files)

matugen's `templates.gtk3` / `templates.gtk4` wrote `~/.config/gtk-{3,4}.0/gtk.css`. That file is the user
stylesheet that sits on top of everything, and the repo template is not only colours: it forces 999px pill
buttons, Material switches, and wallpaper-coloured accents. Layering it over WhiteSur would erase the Mac look,
and leaving it writing the same path would clobber WhiteSur's `gtk.css` on the next wallpaper change.

So: `config.toml` (repo `dots/matugen` and, by targeted edit, the live one) now sends those two templates to
`matugen-gtk3.css` / `matugen-gtk4.css` next to the originals. Nothing imports them; they are still generated,
so GTK colours can be re-enabled later by adding `@import "matugen-gtk4.css";` to `gtk.css`, accepting the
hybrid look. The old GTK3 `gtk.css` (stale generated colours) is replaced by a comment-only stub, because GTK3
reads it above the theme. Terminal/Hyprland/fuzzel/shell colours from matugen are unaffected.

## --browser CHROME_DIR (default off)

Copies WhiteSur's Firefox/Zen userChrome into the given profile `chrome/` directory, mirroring upstream's
`install_firefox_theme` for the default variant: `userChrome.css`, `userContent.css`, `customChrome.css`,
`WhiteSur/`. Existing files of the same name are backed up (and restored by revert); other files in `chrome/`
are untouched. Then, once: `about:config` -> `toolkit.legacyUserProfileCustomizations.stylesheets = true`, and
restart the browser. Zen note: its own UI differs from Firefox, so expect to tune `customChrome.css`.
This script never touches prefs and never runs against the live Zen profile unless you pass its path.

## Limits

- Libadwaita and GTK3 only recolour/restyle widgets; apps that draw their own header (Electron, Qt) keep their
  own. Traffic lights are what WhiteSur draws in GTK header bars, not window-manager buttons.
- Header-bar button order comes from `gtk-decoration-layout`/gsettings; some apps cache it until restarted.
- Needs `glib2` (`gresource`), `curl`, `python3`. Qt side needs the `kvantum` package for the plugin.
