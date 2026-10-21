"""Squircle plate compositing (Apple 1024 canvas, 824 content box, continuous-corner superellipse)."""
import io, os, subprocess
from PIL import Image, ImageDraw, ImageFilter

CANVAS, BOX, N = 1024, 824, 5.0

def squircle_mask(box=BOX, canvas=CANVAS, ss=2):
    import math
    S = canvas * ss
    a = box * ss / 2.0
    c = S / 2.0
    pts = []
    steps = 1440
    for i in range(steps):
        t = 2 * math.pi * i / steps
        ct, st = math.cos(t), math.sin(t)
        x = a * (abs(ct) ** (2 / N)) * (1 if ct >= 0 else -1)
        y = a * (abs(st) ** (2 / N)) * (1 if st >= 0 else -1)
        pts.append((c + x, c + y))
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m.resize((canvas, canvas), Image.LANCZOS)

_MASK = None
def mask():
    global _MASK
    if _MASK is None:
        _MASK = squircle_mask()
    return _MASK

def load_any(path, px=1024):
    """Open svg (rsvg-convert) or raster as RGBA."""
    if path.endswith(".svg"):
        out = subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), "-a", path],
                             capture_output=True, check=True, timeout=30).stdout
        return Image.open(io.BytesIO(out)).convert("RGBA")
    return Image.open(path).convert("RGBA")

_GRAD = None
def _gradient():
    global _GRAD
    if _GRAD is None:
        top, bot = (253, 253, 255), (216, 217, 224)
        ramp = Image.linear_gradient("L").resize((CANVAS, CANVAS))
        a = Image.new("RGB", (CANVAS, CANVAS), top)
        b = Image.new("RGB", (CANVAS, CANVAS), bot)
        _GRAD = Image.composite(b, a, ramp).convert("RGBA")
    return _GRAD

def plate_icon(src_path, glyph_frac=0.68):
    """Return a 1024x1024 RGBA master: plate + shadow + the source glyph centred."""
    m = mask()
    grad = _gradient()
    body = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    body.paste(grad, (0, 0), m)
    # glyph
    g = load_any(src_path, 1024)
    bbox = g.getbbox()
    if bbox:
        g = g.crop(bbox)
    side = int(BOX * glyph_frac)
    g.thumbnail((side, side), Image.LANCZOS)
    body.alpha_composite(g, ((CANVAS - g.width) // 2, (CANVAS - g.height) // 2))
    # keep everything inside the plate
    a = body.getchannel("A")
    from PIL import ImageChops
    body.putalpha(ImageChops.multiply(a, m))
    # shadow
    sh = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    sh.putalpha(m.point(lambda v: int(v * 0.30)))
    sh_black = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 255))
    sh_black.putalpha(m.point(lambda v: int(v * 0.30)))
    sh_black = sh_black.filter(ImageFilter.GaussianBlur(14))
    off = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    off.alpha_composite(sh_black, (0, 12))
    off.alpha_composite(body)
    return off

def fit_square(path):
    """Normalise a downloaded icon to a 1024 square RGBA master."""
    im = Image.open(path).convert("RGBA")
    if im.width != im.height:
        s = max(im.size)
        c = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        c.alpha_composite(im, ((s - im.width) // 2, (s - im.height) // 2))
        im = c
    return im.resize((1024, 1024), Image.LANCZOS)

def _shadowed(icon_box):
    """Place an RGBA icon (already BOX-sized, shaped) on the 1024 canvas with the standard drop shadow."""
    out = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    off = ((CANVAS - icon_box.width) // 2, (CANVAS - icon_box.height) // 2)
    a = Image.new("L", (CANVAS, CANVAS), 0)
    a.paste(icon_box.getchannel("A"), off)
    sh = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 255))
    sh.putalpha(a.point(lambda v: int(v * 0.30)))
    sh = sh.filter(ImageFilter.GaussianBlur(14))
    out.alpha_composite(sh, (0, 12))
    out.alpha_composite(icon_box, off)
    return out

def mas_icon(path):
    """Mac App Store artwork: full-bleed squares get the squircle mask; full-canvas icons are shrunk to the 824 box
    (so they sit at the same visual size as native/plated ones), then the drop shadow is added."""
    im = Image.open(path).convert("RGBA")
    if im.width != im.height:
        return fit_square(path)
    im = im.resize((CANVAS, CANVAS), Image.LANCZOS)
    a = im.getchannel("A")
    corner_opaque = a.getpixel((4, 4)) > 200 and a.getpixel((CANVAS - 5, CANVAS - 5)) > 200
    bbox = a.getbbox()
    full = bbox and (bbox[2] - bbox[0]) >= CANVAS * 0.95
    if corner_opaque:
        from PIL import ImageChops
        im.putalpha(ImageChops.multiply(a, squircle_mask(CANVAS, CANVAS)))
    elif not full:
        return im                      # already padded like a native macOS icon
    im = im.resize((BOX, BOX), Image.LANCZOS)
    return _shadowed(im)
