# Layer 5 -- macOS-style dock

Code: `shell/dock/` (`Dock.qml` layer surface, `DockSurface.qml` drawing and
gestures, `DockItem.qml`, `DockModel.qml`, pure `magnify.js` and `model.js`,
`DockMetrics.qml` tunables). Wired into `shell/shell.qml` behind the setting
`dock.enabled` (default true). The island is untouched.

## What it does

- Bottom dock per monitor, namespace `qml-rice:dock`, glass shelf via real
  Hyprland layer blur (rule in `hypr/hyprland/glass.lua`).
- Pinned apps (setting `dock.pins`, default brave, kitty, code, spotify,
  discord, slack, thunar -- only the ones with a `.desktop`), then running
  unpinned apps, then a separator and minimised windows
  (`special:minimized`).
- Magnification (cosine bell, peak 2x, radius 2.5 tile pitches), critically
  damped pointer follow, launch bounce until the window maps, running dot,
  hover label, press darken, drag to reorder pins, drag off to unpin (poof),
  right-click menu, middle-click new instance, click-focused cycles windows.
- Autohide by default (hover the bottom edge). `dock.autohide=false` reserves
  space and shows the dock on every monitor. Settings: `dock.enabled`,
  `dock.autohide`, `dock.scale` (0.6-1.6), `dock.pins`.

## Apply / revert

    tools/mac-dock/apply.sh     # appends the blur rule to ~/.config/hypr/hyprland/glass.lua (backup first)
    hyprctl reload              # orchestrator: Hyprland re-reads the layer rule
    qml-rice restart-shell      # or: pkill -f '^qs -p ./shell.qml' and relaunch
    tools/mac-dock/revert.sh    # restore glass.lua from the newest backup (or pass a stamp)
    tools/mac-dock/check.sh     # unit tests + render harness + tool selftests, offscreen

Backups: `~/.local/state/qml-rice/mac-dock/<stamp>/`. apply.sh is idempotent.
Disable the dock without reverting: `dock.enabled=false` in the shell settings.

## Making the feel exact: record the real macOS dock

Every number in `DockMetrics.qml` is marked `src: pending reference capture`:
best-known macOS behaviour, not measured. Record the real thing on the
Hackintosh, then:

    python3 -I analyze_capture.py --sweep sweep.mov --bounce bounce.mov \
        --autohide autohide.mov --arrival-t 1.4 --leave-t 5.2 \
        --crop X,Y,W,H --pixel-ratio 2 --out metrics.json
    python3 -I apply-metrics.py metrics.json        # edits shell/dock/DockMetrics.qml
    git diff shell/dock/DockMetrics.qml             # review, then commit

Needs `ffmpeg`, `ffprobe` and `numpy`. `--selftest` on both scripts proves the
estimators against synthetic recordings with known answers.

### Set-up before recording (all three)

1. System Settings > Desktop & Dock: Position **Bottom**, **Magnification ON**
   at the size you want to copy (note the slider position), Size at your
   normal setting, **Show indicators for open applications OFF**, **Show
   suggested and recent apps OFF** (dots and extra icons confuse the
   measurement).
2. Desktop wallpaper: a **plain solid colour** (mid grey is good), no
   widgets, no stage manager. Menu bar auto-hide ON is fine.
3. Remove every Dock icon you do not need; keep 8 to 12 apps pinned and make
   sure none of them is running (except for the autohide clip).
4. QuickTime Player > File > New Screen Recording, **Options > Show Mouse
   Clicks: off**, record the **whole screen at native resolution** (a Retina
   capture is 2x: that is what `--pixel-ratio 2` means; use 1 for a
   non-Retina display).

### Clip 1 -- sweep (`--sweep`)

Magnification on, autohide **off**. Start recording, keep the pointer **away
from the dock for 2 seconds** (rest frames are the reference), then move the
pointer in at the left end of the dock and sweep slowly left to right along
the icons (about 6 to 8 seconds end to end, at constant height over the
icons), then leave. Stop. Pick `--crop X,Y,W,H` (video pixels) as a strip
that contains the whole dock plus at least 40 px of plain wallpaper **above
the tallest magnified icon** and nothing else.

Measures `tileSize`, `peakScale`, `radiusTiles` (fit of a cosine bell to icon
height versus rest-position distance from the pointer).

### Clip 2 -- launch bounce (`--bounce`)

Magnification **off** (or pointer parked well away), autohide off. Start
recording, wait 2 seconds, click a pinned app that is not running and has a
slow start (any heavy app), and let it bounce for at least 5 seconds. Stop.
Use the same crop. Measures `bounceHeight` (fraction of the icon height),
`bouncePeriod`, `bounceRestFraction`.

### Clip 3 -- autohide (`--autohide`)

Autohide **on**. Start recording with the pointer mid-screen and the dock
hidden. Move the pointer straight down to the bottom edge, rest there until
the dock is fully in (about 2 s), then move the pointer straight up to
mid-screen and wait until the dock is fully out. Stop. Use a crop containing
the whole bottom strip down to the screen edge (so the crop bottom is the
screen bottom). Open the clip in QuickTime and read two times off the
timeline: when the pointer first touches the bottom edge (`--arrival-t`) and
when it leaves the dock area (`--leave-t`), in seconds from the start.
Measures `slideDuration` (a fit of an eased slide), `revealDelay`,
`hideDelay`.

## Known limits

- Only the DockMetrics numbers can be measured. Pixel layout of the shelf
  (corner radius, padding) is still eyeballed; edit `shelfRadius`,
  `shelfPadding`, `slotGap`, `bottomMargin` by hand from a screenshot.
- The analyzer assumes a solid wallpaper and a cosine bell; the fit reports
  its rms so you can see when the assumption is wrong. `--selftest` shows the
  estimator's own bias on synthetic data (peak within about 3 percent, radius
  within about 10 percent).
- "Open at Login" is not offered in the menu (no autostart integration yet).
  "Show All Windows" focuses the app's first window; the window titles are
  listed at the top of the menu instead of an Expose view.
- Icons come from the icon theme by name (`image://icon/`); the Layer 2 theme
  `qml-rice-mac` must be the active icon theme for the Mac icons to show.
- Hyprland dispatch strings (`hl.dsp.focus`, `hl.dsp.window.move`,
  `hl.dsp.window.close`) are the 0.56 Lua API names and are unit-tested as
  strings only; they have not been run against the live compositor.
