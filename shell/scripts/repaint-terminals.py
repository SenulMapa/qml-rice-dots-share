#!/usr/bin/env python3

# ported from impasto scripts/theme_manager.py, verbatim except:
#  - input is THIS shell's matugen Material palette.json (dark/light keys),
#    not impasto's own flat 13-key palette, so a mapping step
#    (`impasto_colors_from_material`) sits in front of everything else.
#  - impasto pushes kitty and ~20 other programs (btop, cava, yazi, GTK,
#    Qt/KDE, Vesktop, Spotify, VSCodium, neovim, imv, Zen, Papirus...); this
#    port is scoped to what the task asked for -- kitty and foot -- since
#    porting the rest 1:1 would mean carrying impasto's entire application
#    inventory into a shell that doesn't manage most of those programs.
#  - generated output always lands under Config.appearance.cacheRoot
#    (~/.cache/qml-rice/palette/), matching this repo's existing convention
#    (generate-palette.sh writes beside it) rather than impasto's
#    $XDG_STATE_HOME/quickshell/. Writing into ~/.config (a kitty/foot
#    include) only happens with --apply, which only WallpaperService passes,
#    and only when Config.appearance.repaintApps is on.
#  - the colour math (mix/lift/brighten/contrast, TERMINAL_TINT and the
#    ANSI-slot mapping) is copied unmodified: it has no external
#    dependencies and is the actual "port impasto's code 1:1" surface of
#    this feature.
#
# github.com/andreumassanet/impasto

"""kitty/foot palette push for this shell's wallpaper-repaint pipeline.

Usage: repaint-terminals.py PALETTE_JSON [--apply]

PALETTE_JSON is this shell's own matugen-format palette (the file
generate-palette.sh writes: {"mode": "...", "dark": {...}, "light": {...}}).
Without --apply, only the generated fragments under
~/.cache/qml-rice/palette/ are (re)written -- side-effect-free, safe to run
by hand. With --apply, the kitty/foot includes under ~/.config are also
written; this is gated by the shell on Config.appearance.repaintApps and is
never invoked by anything other than the shell itself.
"""

import colorsys
import glob
import json
import os
import shutil
import subprocess
import sys

XDG_CONFIG_HOME = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
XDG_CACHE_HOME = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
XDG_RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"

CACHE_DIR = os.path.join(XDG_CACHE_HOME, "qml-rice", "palette")
KITTY_GENERATED = os.path.join(CACHE_DIR, "kitty.conf")
FOOT_GENERATED = os.path.join(CACHE_DIR, "foot.ini")

# Only touched with --apply. kitty/foot both resolve `include` relative to
# their own config directory, so the include line the user adds is a single
# relative path; the shell never rewrites kitty.conf/foot.ini itself.
KITTY_CONFIG_INCLUDE = os.path.join(XDG_CONFIG_HOME, "kitty", "qml-rice-palette.conf")
FOOT_CONFIG_INCLUDE = os.path.join(XDG_CONFIG_HOME, "foot", "qml-rice-palette.ini")

KITTY_SOCKETS = os.path.join(XDG_RUNTIME_DIR, "kitty.sock*")

# ── ported verbatim from impasto scripts/theme_manager.py ──────────────────

TERMINAL_TINT = 0.22
TERMINAL_BACKGROUND_FALLBACK = "#000000"

TERMINAL_NORMAL = (("color1", "red"), ("color2", "green"), ("color3", "yellow"),
                   ("color4", "blue"), ("color6", "accent"), ("color7", "textMuted"))
TERMINAL_BRIGHT = (("color9", "red"), ("color10", "green"), ("color11", "yellow"),
                   ("color12", "blue"), ("color14", "accent"), ("color15", "text"))
TERMINAL_ACCENT = ("selection_background", "active_tab_background")

MIN_CONTRAST = 4.5
MIN_CONTRAST_BRIGHT = 7.0
CONTRAST_PIVOT = 0.179


def rgb_to_hex(red, green, blue):
    clamp = lambda value: int(max(0, min(255, value)))
    return f"#{clamp(red):02x}{clamp(green):02x}{clamp(blue):02x}"


def hex_to_rgb(value):
    value = value.lstrip("#")
    return tuple(int(value[index:index + 2], 16) for index in (0, 2, 4))


def mix(value, other, amount):
    """`value` taken `amount` of the way towards `other`."""
    return rgb_to_hex(*(one + (two - one) * amount
                        for one, two in zip(hex_to_rgb(value), hex_to_rgb(other))))


def relative_luminance(red, green, blue):
    def channel(value):
        value /= 255
        return value / 12.92 if value <= 0.03928 else ((value + 0.055) / 1.055) ** 2.4

    return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)


def contrast_on_terminal(value, background):
    pair = sorted((relative_luminance(*hex_to_rgb(value)),
                   relative_luminance(*hex_to_rgb(background))), reverse=True)
    return (pair[0] + 0.05) / (pair[1] + 0.05)


def away(background):
    return -1 if relative_luminance(*hex_to_rgb(background)) > CONTRAST_PIVOT else 1


def lift(value, minimum, background):
    if contrast_on_terminal(value, background) >= minimum:
        return value

    step = 0.01 * away(background)
    hue, lightness, sat = colorsys.rgb_to_hls(*(c / 255 for c in hex_to_rgb(value)))
    for _ in range(100):
        lightness = min(1.0, max(0.0, lightness + step))
        candidate = rgb_to_hex(*(c * 255 for c in colorsys.hls_to_rgb(hue, lightness, sat)))
        if contrast_on_terminal(candidate, background) >= minimum:
            return candidate
        if lightness in (0.0, 1.0):
            break
    return "#ffffff" if step > 0 else "#000000"


def brighten(value, background):
    hue, lightness, sat = colorsys.rgb_to_hls(*(c / 255 for c in hex_to_rgb(value)))
    stepped = rgb_to_hex(*(c * 255 for c in colorsys.hls_to_rgb(
        hue, min(1.0, max(0.0, lightness + 0.12 * away(background))), sat)))
    return lift(stepped, MIN_CONTRAST_BRIGHT, background)


def terminal_background(colors):
    return rgb_to_hex(*(channel * TERMINAL_TINT for channel in hex_to_rgb(colors["accent"])))


def build_terminal_palette(colors):
    """The kitty conf fragment for a palette, slot by slot. Ported verbatim."""
    lines = [
        "# GENERATED by scripts/repaint-terminals.py on every palette change.",
        "# Included by kitty.conf; edits here are lost at the next theme switch.",
        "#",
        "# ported from impasto scripts/theme_manager.py build_terminal_palette()",
        "",
    ]
    background = terminal_background(colors)
    lines.append(f"background {background}")
    lines.append(f"color0 {background}")
    lines.append("")
    for slot, key in TERMINAL_NORMAL:
        lines.append(f"{slot} {lift(colors[key], MIN_CONTRAST, background)}")
    for slot, key in TERMINAL_BRIGHT:
        lines.append(f"{slot} {brighten(colors[key], background)}")

    accent = lift(colors["accent"], MIN_CONTRAST, background)
    lines.append("")
    for slot in TERMINAL_ACCENT:
        lines.append(f"{slot} {accent}")
    lines.append(f"selection_foreground {background}")
    lines.append(f"active_tab_foreground {background}")
    lines.append(f"inactive_tab_background {background}")
    lines.append(f"inactive_tab_foreground {lift(colors['textMuted'], MIN_CONTRAST, background)}")
    return "\n".join(lines) + "\n"


def build_foot_ini(colors):
    """foot's [colors] section: same slots, foot's own hex-without-# syntax."""
    background = terminal_background(colors)

    def strip(value):
        return value.lstrip("#")

    lines = [
        "# GENERATED by scripts/repaint-terminals.py on every palette change.",
        "# Included by foot.ini's [colors] section (`include=`); edits here",
        "# are lost at the next theme switch.",
        "",
        "[colors]",
        f"background={strip(background)}",
        f"foreground={strip(lift(colors['text'], MIN_CONTRAST, background))}",
    ]
    slot_index = {"color1": 1, "color2": 2, "color3": 3, "color4": 4,
                  "color6": 6, "color7": 7, "color9": 9, "color10": 10,
                  "color11": 11, "color12": 12, "color14": 14, "color15": 15}
    # foot names slots 0-7 "regularN" and 8-15 "brightN" (bright is N-8).
    for slot, key in TERMINAL_NORMAL:
        index = slot_index[slot]
        lines.append(f"regular{index}={strip(lift(colors[key], MIN_CONTRAST, background))}")
    for slot, key in TERMINAL_BRIGHT:
        index = slot_index[slot] - 8
        lines.append(f"bright{index}={strip(brighten(colors[key], background))}")
    return "\n".join(lines) + "\n"


# ── mapping from THIS shell's matugen Material palette to impasto's ────────
# flat terminal-facing key set. Not part of impasto: Material has no direct
# red/green/yellow/blue, so those come from the custom error/success/warning
# keys this repo's matugen/palette.json template already defines, and "blue"
# (impasto's cyan-carries-accent slot's neighbour) is Material's tertiary,
# the closest thing to a second hue in the scheme.
def impasto_colors_from_material(material):
    return {
        "accent": material["primary"],
        "accentText": material["onPrimary"],
        "background": material["surface"],
        "surfaceHover": material.get("surfaceContainerHigh", material["surface"]),
        "border": material.get("outlineVariant", material["outline"]),
        "text": material["onSurface"],
        "textMuted": material.get("onSurfaceVariant", material["onSurface"]),
        "red": material.get("error", "#ff453a"),
        "green": material.get("success", "#32d74b"),
        "yellow": material.get("warning", "#ffd60a"),
        "blue": material.get("tertiary", material["primary"]),
    }


def write_generated(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)


def push_kitty(colors, apply):
    kitten = shutil.which("kitten")
    if not kitten or not apply:
        return
    for socket_path in sorted(glob.glob(KITTY_SOCKETS)):
        subprocess.run(
            [kitten, "@", "--to", f"unix:{socket_path}", "set-colors", "--all",
             "--configured", KITTY_CONFIG_INCLUDE],
            capture_output=True, text=True)


def main():
    if len(sys.argv) < 2:
        sys.stderr.write(__doc__ + "\n")
        return 2
    apply = "--apply" in sys.argv[2:]

    with open(sys.argv[1], encoding="utf-8") as handle:
        palette = json.load(handle)
    mode = palette.get("mode", "dark")
    material = palette.get(mode) or palette.get("dark") or palette.get("light")
    if not material:
        sys.stderr.write("palette JSON has neither a resolved mode nor dark/light\n")
        return 1

    colors = impasto_colors_from_material(material)

    kitty_conf = build_terminal_palette(colors)
    foot_ini = build_foot_ini(colors)

    write_generated(KITTY_GENERATED, kitty_conf)
    write_generated(FOOT_GENERATED, foot_ini)

    if apply:
        write_generated(KITTY_CONFIG_INCLUDE, kitty_conf)
        write_generated(FOOT_CONFIG_INCLUDE, foot_ini)
        push_kitty(colors, apply)

    return 0


if __name__ == "__main__":
    sys.exit(main())
