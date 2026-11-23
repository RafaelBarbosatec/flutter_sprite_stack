"""Render before/after previews of the F1 kerb rasterisation.

Replicates Track._classify (rounded-rect ring) and TrackTileset's palette so the
PNG shows what the Dart tileset will generate:

* "before": every cell painted with the classification of its centre
  (kerb cells = full 32 px checker squares, which is the staircase).
* "after": cells crossed by the kerb boundary are rasterised per pixel.

Usage: python3 tool/preview_kerb.py out.png
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'skills'
                   / 'flutter-sprite-stack-assets' / 'scripts'))

from png_rw import write_png  # noqa: E402

TILE = 32
COLS, ROWS = 108, 80
OUTER = dict(left=14.0, top=14.0, right=94.0, bottom=66.0, r=18.0)
INNER = dict(left=24.0, top=24.0, right=84.0, bottom=56.0, r=8.0)

PALETTE = {
    'a': (0x3A, 0x3F, 0x4B),
    'b': (0x35, 0x3A, 0x46),
    'c': (0x2B, 0x30, 0x3A),
    's': (0x4A, 0x52, 0x61),
    'g': (0x4C, 0x9A, 0x4A),
    'h': (0x47, 0x92, 0x45),
    'd': (0x3C, 0x7C, 0x3A),
    'l': (0x5A, 0xA9, 0x58),
    'e': (0x3F, 0x8A, 0x41),
    'f': (0x3B, 0x84, 0x3D),
    'm': (0x33, 0x75, 0x36),
    'n': (0x4B, 0x9C, 0x4D),
    'r': (0xD0, 0x20, 0x28),
    'w': (0xF2, 0xF4, 0xF8),
    'W': (0xB9, 0xC0, 0xCC),
    'D': (0x88, 0x92, 0xA4),
}


def in_rrect(s, x, y, grow=0.0):
    left = s['left'] - grow
    top = s['top'] - grow
    right = s['right'] + grow
    bottom = s['bottom'] + grow
    r = max(0.0, s['r'] + grow)
    if x < left or x >= right or y < top or y >= bottom:
        return False
    cx = left + r if x < left + r else (right - r if x > right - r else x)
    cy = top + r if y < top + r else (bottom - r if y > bottom - r else y)
    dx, dy = x - cx, y - cy
    return dx * dx + dy * dy <= r * r


def classify(x, y):
    o0 = in_rrect(OUTER, x, y, 0)
    i0 = in_rrect(INNER, x, y, 0)
    if o0 and not i0:
        return 'asphalt'
    if i0:
        if not in_rrect(INNER, x, y, -2):
            return 'kerb'
        if not in_rrect(INNER, x, y, -6):
            return 'grass'
        if not in_rrect(INNER, x, y, -8):
            return 'wall'
        return 'scenery'
    if in_rrect(OUTER, x, y, 2):
        return 'kerb'
    if in_rrect(OUTER, x, y, 6):
        return 'grass'
    if in_rrect(OUTER, x, y, 8):
        return 'wall'
    return 'scenery'


def textured(a, b, dark, light, x, y, phase, dark_every, light_every):
    n = x * 7 + y * 13 + phase * 11
    if dark_every and n % dark_every == 0:
        return dark
    if light_every and n % light_every == 0:
        return light
    return a if (x + y + phase) % 2 == 0 else b


def code(cell, px, py, phase):
    if cell == 'asphalt':
        return textured('a', 'b', 'c', 's', px, py, phase, 97, 61)
    if cell == 'grass':
        return textured('g', 'h', 'd', 'l', px, py, phase, 83, 71)
    if cell == 'scenery':
        return textured('e', 'f', 'm', 'n', px, py, phase, 89, 67)
    if cell == 'kerb':
        return 'r' if ((px // 16) + (py // 16)) % 2 == 0 else 'w'
    return 'W' if ((px // 16) + (py // 16)) % 2 == 0 else 'D'


def is_kerb_edge(c, r):
    edge = 0.001
    samples = {
        classify(c + edge, r + edge),
        classify(c + 1 - edge, r + edge),
        classify(c + edge, r + 1 - edge),
        classify(c + 1 - edge, r + 1 - edge),
    }
    if len(samples) == 1:
        return False
    return 'kerb' in samples and ('asphalt' in samples or 'grass' in samples)


def render(cols, rows, per_pixel, scale=1):
    w, h = cols[1] - cols[0], rows[1] - rows[0]
    width, height = w * TILE * scale, h * TILE * scale
    out = bytearray(width * height * 4)

    for ty in range(rows[0], rows[1]):
        for tx in range(cols[0], cols[1]):
            phase = 1 if (tx + ty) % 2 else 0
            custom = per_pixel and is_kerb_edge(tx, ty)
            center = classify(tx + 0.5, ty + 0.5)
            for py in range(TILE):
                for px in range(TILE):
                    if custom:
                        cell = classify(
                            tx + (px + 0.5) / TILE,
                            ty + (py + 0.5) / TILE,
                        )
                        ch = code(cell, px, py, phase)
                    else:
                        ch = code(center, px, py, phase)
                    r_, g_, b_ = PALETTE[ch]
                    ix = (ty - rows[0]) * TILE + py
                    iy = (tx - cols[0]) * TILE + px
                    for sy in range(scale):
                        for sx in range(scale):
                            o = ((ix * scale + sy) * width + iy * scale + sx) * 4
                            out[o:o + 4] = bytes((r_, g_, b_, 255))
    return width, height, out


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else 'kerb_preview.png'
    cols = (14, 56)
    rows = (10, 44)

    w1, h1, before = render(cols, rows, per_pixel=False)
    w2, h2, after = render(cols, rows, per_pixel=True)
    assert (w1, h1) == (w2, h2)

    gap = 6
    width = w1
    height = h1 + gap + h2
    canvas = bytearray([24, 26, 32, 255] * (width * height))

    for y in range(h1):
        start = y * w1 * 4
        canvas[start:start + w1 * 4] = before[start:start + w1 * 4]

    offset = (h1 + gap) * width * 4
    canvas[offset:offset + len(after)] = after

    write_png(out_path, width, height, canvas)
    print(f'wrote {out_path} ({width}x{height}) — top: before, bottom: after')


if __name__ == '__main__':
    main()
