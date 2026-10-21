#!/usr/bin/env bash
# Generate a tasteful solid/gradient fallback wallpaper so first boot isn't
# gray, without any network access or bundled binary image. Prefers
# ImageMagick (`magick`/`convert`) if present, falls back to a pure-stdlib
# python3 PNG writer.
#
# Usage: generate-fallback-wallpaper.sh <output-path> [width] [height]
set -euo pipefail

OUT="${1:?usage: generate-fallback-wallpaper.sh <output-path> [width] [height]}"
W="${2:-1920}"
H="${3:-1080}"

mkdir -p "$(dirname "$OUT")"

# A calm dark-slate-to-near-black vertical gradient -- reads well as both a
# desktop background and a matugen seed image (it has enough tonal range
# to derive a Material You palette from, unlike a flat fill).
TOP="#1b1c22"
BOTTOM="#0b0b0f"

if command -v magick >/dev/null 2>&1; then
    magick -size "${W}x${H}" gradient:"$TOP"-"$BOTTOM" -depth 8 "$OUT"
    exit 0
elif command -v convert >/dev/null 2>&1; then
    convert -size "${W}x${H}" gradient:"$TOP"-"$BOTTOM" -depth 8 "$OUT"
    exit 0
fi

python3 - "$OUT" "$W" "$H" "$TOP" "$BOTTOM" <<'PY'
import struct, sys, zlib

out, w, h, top, bottom = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]

def hex_to_rgb(s):
    s = s.lstrip('#')
    return tuple(int(s[i:i+2], 16) for i in (0, 2, 4))

top_rgb = hex_to_rgb(top)
bot_rgb = hex_to_rgb(bottom)

def lerp(a, b, t):
    return int(a + (b - a) * t)

raw = bytearray()
for y in range(h):
    t = y / max(h - 1, 1)
    row = bytes(lerp(top_rgb[c], bot_rgb[c], t) for c in range(3))
    raw.append(0)  # no filter
    raw.extend(row * w)

def chunk(tag, data):
    return (struct.pack('>I', len(data)) + tag + data +
            struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff))

sig = b'\x89PNG\r\n\x1a\n'
ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
idat = zlib.compress(bytes(raw), 9)

with open(out, 'wb') as f:
    f.write(sig)
    f.write(chunk(b'IHDR', ihdr))
    f.write(chunk(b'IDAT', idat))
    f.write(chunk(b'IEND', b''))
PY
