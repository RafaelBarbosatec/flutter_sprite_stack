"""Render a preview of the F1 corner kerbs and white track-limit lines.

Replicates ``Track._classify`` (rounded-rect ring, kerbs only inside the four
corners) and ``TrackTileset``'s palette so the PNG shows what the Dart tileset
generates:

* kerbs are a 48 px band (three 16 px checker blocks) on the infield side of
  the four corners; the straights have none;
* the white lines mark both asphalt edges, two pixels wide;
* cells crossed by the kerb or by the outer asphalt/grass edge are rasterised
  per pixel, so both the kerb band and the green curve follow the real
  geometry instead of stepping in 32 px squares.

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
KERB_WIDTH = 1.5
LINE = 2 / TILE
CORNERS = [
    (32.0, 32.0, -1.0, -1.0),  # top-left
    (76.0, 32.0, 1.0, -1.0),  # top-right
    (32.0, 48.0, -1.0, 1.0),  # bottom-left
    (76.0, 48.0, 1.0, 1.0),  # bottom-right
]

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


def in_kerb_zone(x, y):
    if not in_rrect(INNER, x, y):
        return False
    if in_rrect(INNER, x, y, -KERB_WIDTH):
        return False
    for cx, cy, sx, sy in CORNERS:
        u = (x - cx) * sx
        v = (y - cy) * sy
        if u < 0 or v < 0:
            continue
        if u * u + v * v <= INNER['r'] ** 2:
            return True
    return False


def classify(x, y):
    o0 = in_rrect(OUTER, x, y, 0)
    i0 = in_rrect(INNER, x, y, 0)
    if o0 and not i0:
        return 'asphalt'
    if i0:
        if in_kerb_zone(x, y):
            return 'kerb'
        if not in_rrect(INNER, x, y, -6):
            return 'grass'
        if not in_rrect(INNER, x, y, -8):
            return 'wall'
        return 'scenery'
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


def is_line(x, y):
    """True for the 2 px white line just inside each asphalt edge."""
    if in_rrect(OUTER, x, y, 0) and not in_rrect(OUTER, x, y, -LINE):
        return True
    if in_rrect(INNER, x, y, LINE) and not in_rrect(INNER, x, y, 0):
        return True
    return False


def in_corner_square(c, r):
    """Whether cell (c, r) lies entirely inside one corner quadrant."""
    for cx, cy, sx, sy in CORNERS:
        if all(
            (x - cx) * sx >= 0 and (y - cy) * sy >= 0
            for x in (c, c + 1)
            for y in (r, r + 1)
        ):
            return True
    return False


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
    kerb_edge = 'kerb' in samples and (
        'asphalt' in samples or 'grass' in samples
    )
    asphalt_grass = 'asphalt' in samples and 'grass' in samples
    return in_corner_square(c, r) and (kerb_edge or asphalt_grass)


def render(cols, rows):
    w, h = cols[1] - cols[0], rows[1] - rows[0]
    width, height = w * TILE, h * TILE
    out = bytearray(width * height * 4)

    for ty in range(rows[0], rows[1]):
        for tx in range(cols[0], cols[1]):
            phase = 1 if (tx + ty) % 2 else 0
            custom = is_kerb_edge(tx, ty)
            center = classify(tx + 0.5, ty + 0.5)
            for py in range(TILE):
                for px in range(TILE):
                    wx = tx + (px + 0.5) / TILE
                    wy = ty + (py + 0.5) / TILE
                    cell = classify(wx, wy) if custom else center
                    ch = 'w' if is_line(wx, wy) else code(cell, px, py, phase)
                    r_, g_, b_ = PALETTE[ch]
                    ix = (ty - rows[0]) * TILE + py
                    iy = (tx - cols[0]) * TILE + px
                    o = (ix * width + iy) * 4
                    out[o:o + 4] = bytes((r_, g_, b_, 255))
    return width, height, out


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else 'f1-corner-kerbs.png'
    # Top-left corner: outer arc plus the inner apex kerb.
    cols = (10, 46)
    rows = (10, 46)
    width, height, pixels = render(cols, rows)
    write_png(out_path, width, height, pixels)
    print(f'wrote {out_path} ({width}x{height})')


if __name__ == '__main__':
    main()
