#!/usr/bin/env python3
"""Grid of every built icon at 48px -> $CACHE/contact-sheet.png. Usage: contact_sheet.py [THEME_DIR] [OUT.png]"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from PIL import Image, ImageDraw

theme = sys.argv[1] if len(sys.argv) > 1 else os.path.join(lib.HOME, ".local/share/icons/qml-rice-mac")
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(lib.CACHE, "contact-sheet.png")
d = os.path.join(theme, "48x48", "apps")
files = sorted(f for f in os.listdir(d) if f.endswith(".png") and not os.path.islink(os.path.join(d, f)))
cols = 12
cell_w, cell_h, pad = 96, 92, 12
rows = max(1, -(-len(files) // cols))
sheet = Image.new("RGBA", (cols * cell_w, rows * cell_h + pad), (32, 33, 38, 255))
dr = ImageDraw.Draw(sheet)
for i, f in enumerate(files):
    x, y = (i % cols) * cell_w, (i // cols) * cell_h + pad
    im = Image.open(os.path.join(d, f)).convert("RGBA")
    sheet.alpha_composite(im, (x + (cell_w - 48) // 2, y + 6))
    dr.text((x + 4, y + 60), f[:-4][:15], fill=(200, 200, 205, 255))
os.makedirs(os.path.dirname(out), exist_ok=True)
sheet.save(out)
print("%d icons -> %s" % (len(files), out))
