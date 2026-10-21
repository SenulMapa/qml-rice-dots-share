# wallpapers/

This repo intentionally ships **no personal wallpapers** -- the original
desktop's `~/Pictures/wallpapers` has unclear licensing and isn't ours to
redistribute.

## What the installer does instead

On first install, if `~/Pictures/wallpapers` (or wherever you point it) is
empty, `install.sh` (with the `matugen` and/or `hypr` modules selected)
generates a single tasteful fallback wallpaper locally -- a dark vertical
gradient PNG, no network or GPU required -- and runs `matugen image` against
it, so the terminal/GTK/Hyprland-border colours are populated immediately
instead of the desktop looking gray/untheemd on first boot.

The generator lives at `scripts/generate-fallback-wallpaper.sh` in this repo
and needs only `python3` (stdlib, no Pillow) or, if present, `magick`
(ImageMagick) as a faster path.

## Adding your own set

Drop a small (3-8 image), properly-licensed default set here as
`wallpapers/default/*.{jpg,png}` -- e.g. your own photography, or wallpapers
under a license that permits redistribution (CC0, CC-BY with attribution
kept in this README, etc). `install.sh --modules wallpapers` will then offer
to copy them to `~/Pictures/wallpapers` and let you pick one interactively.

If you add third-party wallpapers, list their source/license/attribution
below:

| File | Source | License |
|------|--------|---------|
| _(none yet)_ | | |
