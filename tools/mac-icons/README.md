# mac-icons (Layer 2)

Builds the `qml-rice-mac` icon theme (`Inherits=Papirus-Dark,Adwaita,hicolor`) so every app uses one
Mac-style icon. Only manifests/scripts are committed; downloaded images live in
`~/.cache/qml-rice/mac-icons/` (licence).

## macOSicons.com access
There IS an official API (documented at https://macosicons.com/developers): `POST https://api.macosicons.com/api/v1/search`,
headers `x-api-key` + `Content-Type: application/json`, body `{"query":"Safari"}`; hits carry `appName`,
`lowResPngUrl`, `icnsUrl`, `iOSUrl`, `credit`. It needs a free key (**50 requests/month**; 1000 on the paid tier).
Put the key in `MACOSICONS_API_KEY` or `~/.config/qml-rice/macosicons.key`. `fetch_candidates.py` caches per app and has a
`--max-requests` budget (default 40), so it resumes across months. The live endpoint was NOT exercised (no key available);
it was tested against a local mock of the documented shape.
**Fallback without a key:** add `"<desktop-id>": {"source":"url","url":"https://..."}` to `picks.json` by hand
(any https image URL, e.g. an `s3-new.macosicons.com` link copied from an icon page).

## Keyless sources (ranked official > Mac App Store > macOSicons > plated Papirus)
- `official_sources.json`: curated vendor-published icons (raw.githubusercontent.com .icns/.png) with pinned sha256
  (`fetch_official.py --record` pins on first verified fetch; a changed file is rejected until re-pinned). Matching is by exact
  normalised alias against the app's Icon=/desktop id/WM class/name. Not obtainable without huge installers, so skipped:
  Spotify, Discord, Steam, Vivaldi, Figma (no public icns). The vscode repo only ships the Code - OSS icon, not Microsoft's.
- `fetch_itunes.py`: iTunes Search API (`entity=macSoftware`, no key, ~18 req/min, cached per app). Strict match: trackName must equal
  the app name AND bundleId/seller must contain it, generic names (code, micro...) never match, plus a few bundleId overrides.
  Artwork is requested at 1024x1024bb.
- `.icns` is read with Pillow (largest embedded size; ic12/ic13 retina variants work). No external converter needed.
- Mac App Store artwork that is full-bleed gets the squircle mask and is scaled into the 824 box with a drop shadow.

## Pipeline
1. `scan.py` -> `apps.json` (non-NoDisplay .desktop files + `hyprctl clients -j` classes; read-only).
2. `fetch_candidates.py` -> candidate metadata cache.
3. `picker.py` -> http://127.0.0.1:7820 review grid; clicks persist at once to `picks.json`. Per app there is a
   "keep Papirus (plated)" tile. Unpicked apps use the first candidate (auto); with no candidates the Papirus icon is plated.
   `build_theme.py --freeze` writes the auto choices into `picks.json` so the second machine matches.
4. `build_theme.py [--target DIR] [--offline]` -> PNG 16..512 plus @2x under each app's `Icon=` name, `.desktop` id,
   `StartupWMClass` and known aliases (spotify, discord, slack, code, brave, kitty, zen...). Plated icons use a 824/1024
   superellipse (n=5) plate with a drop shadow. Needs python-pillow + rsvg-convert.
5. `contact_sheet.py [THEME] [OUT]` -> 48 px grid PNG (default `~/.cache/qml-rice/mac-icons/contact-sheet.png`).

## Apply / revert / check
- `apply.sh`: scans, builds into `~/.local/share/icons/qml-rice-mac`, sets gtk-3/4 `settings.ini`, gsettings, `kdeglobals [Icons]`,
  `qt6ct.conf`. Backs up once to `~/.local/state/qml-rice/mac-icons/<stamp>/`. Idempotent.
- `revert.sh [stamp]` restores exactly. `check.sh [THEME]` validates; `check.sh --selftest` builds into a temp dir first.
- `install.sh --modules=macicons` (in the default set) runs `apply.sh`.

## Limits
Running apps/shell must restart to pick the theme up. Icons with no source anywhere (e.g. `Icon=network-wired` in
`apps/`) fall through to inherited themes and show as warnings in check. Tiny source glyphs look small on their plate.
