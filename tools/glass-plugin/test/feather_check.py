#!/usr/bin/env python3
# Feather-mode check for test/glass_render_test.cpp (no Hyprland, software GL).
#   alpha 0            -> backdrop unchanged, exactly
#   alpha 0.22, gain 4.5 (weight 0.99) -> matches full blur (gain 100, weight 1) within a few levels
#   outside the surface box -> unchanged
# usage: python3 -I test/feather_check.py <outdir> <glass_render_test binary> <shaders dir>
# Needs numpy. Writes only inside <outdir>.
import os
import subprocess
import sys

import numpy as np

OUT, BIN, SH = sys.argv[1], sys.argv[2], sys.argv[3]
HERE = os.path.dirname(os.path.abspath(__file__))
os.makedirs(OUT, exist_ok=True)
W, H = 560, 600
BX, BY, BW, BH = 60, 40, 420, 520

subprocess.run([sys.executable, "-I", os.path.join(HERE, "make_alpha_fixture.py"), OUT], check=True, stdout=subprocess.DEVNULL)
bg_path = os.path.join(OUT, "backdrop.rgba")
bg = np.fromfile(bg_path, np.uint8).reshape(H, W, 4).astype(int)


def surface(name, alpha):
    a = np.zeros((BH, BW, 4), np.uint8)
    a[..., 3] = round(alpha * 255)  # premultiplied, rgb 0
    p = os.path.join(OUT, name)
    a.tofile(p)
    return p


def run(surf, gain, feather):
    out = os.path.join(OUT, f"out_{os.path.basename(surf)}_{gain}_{feather}.rgba")
    env = dict(os.environ, GLASS_FEATHER=str(feather), GLASS_FEATHER_GAIN=str(gain))
    subprocess.run([BIN, os.path.join(SH, "glass.frag"), os.path.join(SH, "glass_blur.frag"), bg_path, str(W), str(H), out,
                    str(BX), str(BY), str(BW), str(BH), "22", "22", "1.0", "0.35", "0.4", "100",
                    surf, os.path.join(SH, "glass_alpha.frag")],
                   env=env, check=True, stderr=subprocess.DEVNULL)
    return np.fromfile(out, np.uint8).reshape(H, W, 4).astype(int)


box = np.zeros((H, W), bool)
box[BY:BY + BH, BX:BX + BW] = True
failures = []

a0 = run(surface("surf_a0.rgba", 0.0), 4.5, 1)
if np.abs(a0 - bg).max() != 0:
    failures.append("alpha 0 changed the backdrop")

g45 = run(surface("surf_a022.rgba", 0.22), 4.5, 1)
g100 = run(surface("surf_a022b.rgba", 0.22), 100, 1)
diff = np.abs(g45 - g100)[box][..., :3].max()
if diff > 4:
    failures.append(f"alpha 0.22 gain 4.5 is not full blur (max diff {diff})")
if np.abs(g45 - bg)[box][..., :3].mean() < 20:
    failures.append("alpha 0.22 gain 4.5 looks sharp, not blurred")

if np.abs((g45 - bg)[~box]).max() != 0:
    failures.append("pixels outside the surface box changed")

if failures:
    print("FEATHER CHECK FAILED:\n  " + "\n  ".join(failures))
    sys.exit(1)
print(f"feather check ok: alpha0 exact, 0.22/g4.5 vs full blur max diff {diff}")
