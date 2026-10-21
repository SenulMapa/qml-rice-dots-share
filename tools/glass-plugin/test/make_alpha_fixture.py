#!/usr/bin/env python3
# Writes the offline alpha-mode fixture for test/glass_render_test.cpp:
#   backdrop.rgba  560 x 600, colourful stripes and text-like bars behind the window
#   surface.rgba   420 x 520 premultiplied RGBA, a Control-Center-like layer: several rounded
#                  modules with gaps, plus a soft shadow that stays below alpha 0.3
# usage: python3 -I test/make_alpha_fixture.py <outdir>
# Raw files are row 0 = top, like the test expects. Nothing here is part of the plugin build.
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)

BW, BH = 560, 600          # backdrop
SW, SH = 420, 520          # surface (the layer box)
SS = 4                     # supersampling for clean rounded edges
INK = (24, 26, 34)
INK_ALPHA = 0.86           # not fully opaque, like a real translucent module
SHADOW_MAX = 0.30          # soft shadow stays under the 0.35 silhouette floor

# --- backdrop: high-contrast content so refraction is visible -------------------------
bg = Image.new("RGB", (BW, BH), (30, 40, 90))
d = ImageDraw.Draw(bg)
for x in range(0, BW, 28):
    col = [(230, 60, 90), (250, 200, 60), (60, 200, 170), (120, 90, 230)][(x // 28) % 4]
    d.rectangle([x, 0, x + 13, BH], fill=col)
for y in range(0, BH, 44):
    d.rectangle([0, y, BW, y + 6], fill=(255, 255, 255))
try:
    font = ImageFont.load_default(size=44)
except TypeError:
    font = ImageFont.load_default()
for i, word in enumerate(["GLASS", "TEXT", "BEHIND"]):
    d.text((20, 90 + i * 150), word, fill=(15, 15, 25), font=font)
bg.save(os.path.join(OUT, "backdrop.png"))
open(os.path.join(OUT, "backdrop.rgba"), "wb").write(np.asarray(bg.convert("RGBA"), dtype=np.uint8).tobytes())

# --- surface: modules on a transparent canvas, supersampled ----------------------------
MODULES = [  # x0, y0, x1, y1, radius (logical px)
    (20, 20, 400, 170, 28),     # wide top module
    (20, 186, 200, 326, 24),    # tile
    (220, 186, 400, 326, 24),   # tile, 20 px gap to the left one
    (20, 342, 400, 384, 21),    # thin slider bar
    (20, 400, 400, 500, 28),    # bottom card
]


def rrect_mask(size, box, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m


big = (SW * SS, SH * SS)
mod = Image.new("L", big, 0)
for x0, y0, x1, y1, r in MODULES:
    mask = rrect_mask(big, (x0 * SS, y0 * SS, x1 * SS - 1, y1 * SS - 1), r * SS)
    mod = Image.fromarray(np.maximum(np.asarray(mod), np.asarray(mask)))

# shadow: the module union, offset down, blurred, scaled to SHADOW_MAX
sh = Image.new("L", big, 0)
off = 12 * SS
shifted = Image.new("L", big, 0)
shifted.paste(mod, (0, off))
sh = shifted.filter(ImageFilter.GaussianBlur(radius=14 * SS))
sh_a = np.asarray(sh, dtype=np.float32) / 255.0 * SHADOW_MAX
mod_a = np.asarray(mod, dtype=np.float32) / 255.0 * INK_ALPHA

# premultiplied over: module over shadow
a = mod_a + sh_a * (1.0 - mod_a)
rgb = np.zeros((SH * SS, SW * SS, 3), dtype=np.float32)
rgb[..., 0] = INK[0] * mod_a
rgb[..., 1] = INK[1] * mod_a
rgb[..., 2] = INK[2] * mod_a
out = np.zeros((SH, SW, 4), dtype=np.float32)
# box-downsample by SS
a_ds = a.reshape(SH, SS, SW, SS).mean(axis=(1, 3))
rgb_ds = rgb.reshape(SH, SS, SW, SS, 3).mean(axis=(1, 3))
out[..., :3] = rgb_ds
out[..., 3] = a_ds
surf = np.clip(np.round(out * 255.0), 0, 255).astype(np.uint8)
open(os.path.join(OUT, "surface.rgba"), "wb").write(surf.tobytes())
Image.fromarray(surf, "RGBA").save(os.path.join(OUT, "surface.png"))
print("alpha range: min %.3f max %.3f" % (a_ds.min(), a_ds.max()))
