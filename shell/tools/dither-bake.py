#!/usr/bin/env python3
"""
CPU error-diffusion bake for wallpaper/DitherWallpaper.qml's `floyd` and
`atkinson` dither patterns.

Error diffusion is inherently sequential per scanline (serpentine), so it
cannot run per-pixel in a GLSL fragment shader the way `bayer`/`noise`/
`lines` do -- this bakes a "cells" texture, one texel per dither CELL (not
per screen pixel), holding the quantized level in [0,1], which the shader
then samples with NEAREST filtering (see shaders/dither.frag) so cells snap
to crisp, non-antialiased blocks instead of grey dots.

Usage:
    dither-bake.py <image_path> <out_w> <out_h> <cell> <pattern> <levels> \
        <contrast> <brightness> <crop_x> <crop_y> <crop_w> <crop_h> <out_png>

All of crop_x/y/w/h are in SOURCE image pixel space, identical to the crop
rect wallpaper/DitherWallpaper.qml computes as `imageCropRect` and feeds to
Image.sourceClipRect -- using the same rect here is what keeps the baked
cell grid aligned 1:1 with what the QML side renders, per the module
contract in DitherWallpaper.qml's imageCropRect comment.

<pattern> is "floyd" or "atkinson". <out_w>/<out_h> are the SCREEN pixel
dimensions; the cell grid is out_w/cell x out_h/cell, rounded up.

Grade (matches shaders/dither.frag / the DitherVeil spec):
    luma = 0.2126 R + 0.7152 G + 0.0722 B
    graded = pow(clamp((luma - 0.5) * contrast + 0.5 + brightness, 0, 1), 1.6)
then quantized to `levels` steps via serpentine error diffusion.

Output: single-channel PNG, one pixel per cell, value = quantized level
mapped to 0-255 (level / (levels-1) * 255), written atomically (temp file +
rename) so a concurrent QML read never sees a half-written file.
"""
import sys
import os
import numpy as np
from PIL import Image

FLOYD_KERNEL = [(1, 0, 7 / 16), (-1, 1, 3 / 16), (0, 1, 5 / 16), (1, 1, 1 / 16)]
ATKINSON_KERNEL = [(1, 0, 1 / 8), (2, 0, 1 / 8), (-1, 1, 1 / 8),
                    (0, 1, 1 / 8), (1, 1, 1 / 8), (0, 2, 1 / 8)]


def grade(luma: np.ndarray, contrast: float, brightness: float) -> np.ndarray:
    g = (luma - 0.5) * contrast + 0.5 + brightness
    g = np.clip(g, 0.0, 1.0)
    return np.power(g, 1.6)


def error_diffuse(cells: np.ndarray, levels: int, pattern: str) -> np.ndarray:
    """
    cells: float32 array in [0,1], shape (rows, cols). Serpentine
    Floyd-Steinberg / Atkinson error diffusion, quantized to `levels` steps.
    Returns quantized levels in [0,1] (level index / (levels-1)).
    """
    kernel = FLOYD_KERNEL if pattern == "floyd" else ATKINSON_KERNEL
    steps = max(levels - 1, 1)
    rows, cols = cells.shape
    buf = cells.astype(np.float64).copy()
    out = np.zeros_like(buf)

    for y in range(rows):
        serpentine = (y % 2 == 1)
        xrange = range(cols - 1, -1, -1) if serpentine else range(cols)
        for x in xrange:
            old = buf[y, x]
            level = round(np.clip(old, 0.0, 1.0) * steps)
            new = level / steps
            out[y, x] = new
            err = old - new
            for (dx, dy, w) in kernel:
                ex = -dx if serpentine else dx
                nx, ny = x + ex, y + dy
                if 0 <= nx < cols and 0 <= ny < rows:
                    buf[ny, nx] += err * w
    return out


def main():
    if len(sys.argv) != 14:
        print(__doc__, file=sys.stderr)
        sys.exit(2)

    (image_path, out_w, out_h, cell, pattern, levels, contrast, brightness,
     crop_x, crop_y, crop_w, crop_h, out_png) = sys.argv[1:14]

    out_w, out_h, cell = int(out_w), int(out_h), max(1, int(round(float(cell))))
    levels = max(2, int(levels))
    contrast, brightness = float(contrast), float(brightness)
    crop_x, crop_y, crop_w, crop_h = (float(crop_x), float(crop_y),
                                       float(crop_w), float(crop_h))

    img = Image.open(image_path).convert("RGB")
    if crop_w > 0 and crop_h > 0:
        img = img.crop((int(round(crop_x)), int(round(crop_y)),
                         int(round(crop_x + crop_w)), int(round(crop_y + crop_h))))

    cols = max(1, -(-out_w // cell))  # ceil
    rows = max(1, -(-out_h // cell))
    # Resize straight to the cell grid resolution -- each output pixel here
    # IS one dither cell, matching how the shader samples one cellsTex
    # texel per (floor(px/cell)) cell.
    small = img.resize((cols, rows), Image.BOX)
    arr = np.asarray(small, dtype=np.float64) / 255.0

    luma = 0.2126 * arr[..., 0] + 0.7152 * arr[..., 1] + 0.0722 * arr[..., 2]
    graded = grade(luma, contrast, brightness)

    quantized = error_diffuse(graded, levels, pattern)

    out_arr = np.clip(quantized * 255.0 + 0.5, 0, 255).astype(np.uint8)
    out_img = Image.fromarray(out_arr, mode="L")

    out_dir = os.path.dirname(out_png)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    tmp_path = out_png + ".tmp"
    out_img.save(tmp_path, format="PNG")
    os.replace(tmp_path, out_png)
    print(f"Baked {cols}x{rows} cells ({pattern}, {levels} levels) -> {out_png}")


if __name__ == "__main__":
    main()
