#!/usr/bin/env python3
"""
One-off generator for the two static dither reference textures committed to
wallpaper/textures/:

  bayer8.png  -- 8x8 ordered Bayer threshold matrix, single-channel, value =
                 (index + 0.5) / 64 scaled to 0-255. Computed with the exact
                 bit-interleave formula from DitherVeil's `bayer(vec2 cell)`
                 (v = px^py; m = interleave(v, py)) -- Python has real
                 integer bitwise ops, GLSL 100es/120 on this NVIDIA GL
                 context does not, which is why the *shader* samples this as
                 a texture instead of computing it.

  noise64.png -- 64x64 blue-noise stipple (void-and-cluster), single-channel
                 rank-order threshold matrix (value = (rank + 0.5) / 4096).
                 Deterministic (fixed seed), so re-running this script
                 reproduces the same committed PNG bit-for-bit.

Run once with tools/.venv/bin/python3 (numpy + Pillow). Not part of the
runtime bake pipeline -- these two textures are static and committed, unlike
tools/dither-bake.py's per-wallpaper error-diffusion bakes.
"""
import numpy as np
from PIL import Image
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent.parent / "wallpaper" / "textures"
SEED = 20260926  # deterministic


def gen_bayer8() -> np.ndarray:
    size = 8
    m = np.zeros((size, size), dtype=np.float64)
    for py in range(size):
        for px in range(size):
            v = px ^ py
            val = (((v & 1) << 5) | ((py & 1) << 4) | ((v & 2) << 2)
                   | ((py & 2) << 1) | ((v & 4) >> 1) | ((py & 4) >> 2))
            m[py, px] = (val + 0.5) / 64.0
    return m


def gen_blue_noise_64(size: int = 64, sigma: float = 1.5) -> np.ndarray:
    """
    Void-and-cluster (Ulichney), simplified: toroidal Gaussian energy,
    incremental swap-based initial-pattern generation, then two ranking
    passes (cluster removal below the initial count, void filling above).
    """
    rng = np.random.default_rng(SEED)
    n = size * size

    # Precompute a small toroidal Gaussian kernel (radius ~4*sigma) used for
    # incremental energy updates -- avoids an O(n) recompute per swap.
    radius = int(np.ceil(sigma * 4))
    ky, kx = np.mgrid[-radius:radius + 1, -radius:radius + 1]
    kernel = np.exp(-(kx * kx + ky * ky) / (2 * sigma * sigma))

    def add_kernel(energy, y, x, sign):
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                yy = (y + dy) % size
                xx = (x + dx) % size
                energy[yy, xx] += sign * kernel[dy + radius, dx + radius]

    # ---- initial binary pattern (~10% density) via cluster-minimizing swaps
    initial_density = max(1, n // 10)
    flat_idx = rng.permutation(n)[:initial_density]
    pattern = np.zeros(n, dtype=bool)
    pattern[flat_idx] = True
    pattern = pattern.reshape(size, size)

    energy = np.zeros((size, size), dtype=np.float64)
    ys, xs = np.where(pattern)
    for y, x in zip(ys, xs):
        add_kernel(energy, y, x, 1.0)

    def tightest_cluster_true():
        e = np.where(pattern, energy, -np.inf)
        return np.unravel_index(np.argmax(e), e.shape)

    def largest_void_false():
        e = np.where(~pattern, energy, np.inf)
        return np.unravel_index(np.argmin(e), e.shape)

    for _ in range(400):
        ty, tx = tightest_cluster_true()
        vy, vx = largest_void_false()
        if (ty, tx) == (vy, vx):
            break
        add_kernel(energy, ty, tx, -1.0)
        pattern[ty, tx] = False
        add_kernel(energy, vy, vx, 1.0)
        pattern[vy, vx] = True

    rank = np.zeros((size, size), dtype=np.int64)

    # Phase 2: rank the initial pattern's "on" pixels downward from
    # initial_density-1 to 0 by repeatedly removing the tightest cluster.
    work = pattern.copy()
    work_energy = energy.copy()
    for r in range(initial_density - 1, -1, -1):
        e = np.where(work, work_energy, -np.inf)
        y, x = np.unravel_index(np.argmax(e), e.shape)
        rank[y, x] = r
        work[y, x] = False
        add_kernel(work_energy, y, x, -1.0)

    # Phase 3: rank the remaining voids upward from initial_density to n-1
    # by repeatedly inserting into the largest remaining void.
    work = pattern.copy()
    work_energy = energy.copy()
    for r in range(initial_density, n):
        e = np.where(~work, work_energy, np.inf)
        y, x = np.unravel_index(np.argmin(e), e.shape)
        rank[y, x] = r
        work[y, x] = True
        add_kernel(work_energy, y, x, 1.0)

    return (rank.astype(np.float64) + 0.5) / n


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    bayer = gen_bayer8()
    Image.fromarray((bayer * 255.0 + 0.5).astype(np.uint8), mode="L").save(
        OUT_DIR / "bayer8.png")

    noise = gen_blue_noise_64()
    Image.fromarray((noise * 255.0 + 0.5).astype(np.uint8), mode="L").save(
        OUT_DIR / "noise64.png")

    print(f"Wrote {OUT_DIR / 'bayer8.png'} and {OUT_DIR / 'noise64.png'}")


if __name__ == "__main__":
    main()
