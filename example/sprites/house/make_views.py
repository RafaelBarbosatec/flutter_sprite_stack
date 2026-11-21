#!/usr/bin/env python3
"""Draw the four orthographic views of a chunky countryside cottage (pyramid roof).

Layout: 1x4 row (TOP, SIDE, FRONT, BACK) on flat white, 8x nearest upscale.
Geometry: 24x24 footprint, 14px walls, 8px pyramid roof, 3x3 chimney on the peak.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

PAL = {
    "outline": (44, 32, 26),        # dark warm brown
    "wall": (238, 228, 202),        # cream plaster
    "wall_sh": (198, 182, 150),     # wall shadow
    "wall_hi": (252, 246, 228),     # wall highlight
    "roof": (176, 82, 52),          # terracotta
    "roof_sh": (138, 60, 40),       # roof shadow slope
    "roof_hi": (212, 118, 76),      # roof lit slope
    "ridge": (120, 52, 36),         # ridge seam
    "door": (122, 70, 40),          # wooden door
    "door_d": (82, 46, 26),
    "door_knob": (210, 176, 80),
    "glass": (120, 172, 208),       # window glass
    "glass_h": (200, 228, 248),
    "frame": (90, 66, 44),          # window frame
    "chimney": (158, 66, 50),       # brick
    "chimney_d": (120, 48, 38),
    "chimney_top": (90, 40, 34),
    "foundation": (140, 138, 146),  # stone base
}

W = 24
L = 24
WALL_H = 14          # Z 0..13
ROOF_H = 8           # Z 14..21
CHIMNEY_H = 4        # Z 22..25
TOTAL_H = WALL_H + ROOF_H + CHIMNEY_H  # 26

# Gable/trapezoid widths per row (row = 25 - Z): row 4 = Z21 (flat top) .. row 11 = Z14 (eave)
ROOF_ROWS = {4: (10, 13), 5: (9, 15), 6: (7, 16), 7: (6, 17),
             8: (4, 19), 9: (3, 20), 10: (1, 22), 11: (0, 23)}


def add_outline(img: Image.Image, color=PAL["outline"]) -> Image.Image:
    a = np.array(img)
    alpha = a[..., 3] > 0
    d = alpha.copy()
    d[1:] |= alpha[:-1]
    d[:-1] |= alpha[1:]
    d[:, 1:] |= alpha[:, :-1]
    d[:, :-1] |= alpha[:, 1:]
    d[1:, 1:] |= alpha[:-1, :-1]
    d[1:, :-1] |= alpha[:-1, 1:]
    d[:-1, 1:] |= alpha[1:, :-1]
    d[:-1, :-1] |= alpha[1:, 1:]
    outline = d & ~alpha
    a[outline] = (color[0], color[1], color[2], 255)
    return Image.fromarray(a)


def crop(img: Image.Image) -> Image.Image:
    a = np.array(img)
    ys, xs = np.nonzero(a[..., 3] > 0)
    return Image.fromarray(a[ys.min(): ys.max() + 1, xs.min(): xs.max() + 1])


def draw_window(d: ImageDraw.ImageDraw, x: int, y: int) -> None:
    d.rectangle([x, y, x + 3, y + 4], fill=PAL["frame"])
    d.rectangle([x + 1, y + 1, x + 2, y + 3], fill=PAL["glass"])
    d.rectangle([x + 1, y + 1, x + 1, y + 1], fill=PAL["glass_h"])


def _roof_row(d: ImageDraw.ImageDraw, ox: int, oy: int, row: int, x0: int, x1: int) -> None:
    """One roof row of the gable end: shadow slope (X<12), lit slope (X>12), ridge seam (X=12)."""
    for x in range(x0, x1 + 1):
        if x < 12:
            c = PAL["roof_sh"]
        elif x > 12:
            c = PAL["roof_hi"]
        else:
            c = PAL["ridge"]
        d.point((ox + x, oy + row), fill=c)


def _draw_chimney(d: ImageDraw.ImageDraw, ox: int, oy: int) -> None:
    """3x4 chimney block sitting on the roof peak, rows 0..3 (Z 22..25), X 10..12."""
    d.rectangle([ox + 10, oy, ox + 12, oy + 3], fill=PAL["chimney"])
    d.rectangle([ox + 11, oy + 1, ox + 11, oy + 2], fill=PAL["chimney_d"])


def _draw_walls(d: ImageDraw.ImageDraw, ox: int, oy: int) -> None:
    d.rectangle([ox, oy + 12, ox + 23, oy + 25], fill=PAL["wall"])
    d.rectangle([ox, oy + 12, ox + 23, oy + 12], fill=PAL["wall_hi"])
    d.rectangle([ox, oy + 23, ox + 23, oy + 23], fill=PAL["wall_sh"])
    d.rectangle([ox, oy + 24, ox + 23, oy + 25], fill=PAL["foundation"])


def top_view() -> Image.Image:
    img = Image.new("RGBA", (W + 2, L + 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox = oy = 1
    # pyramid roof: left half shadow, right half lit
    d.rectangle([ox, oy, ox + 23, oy + 23], fill=PAL["roof"])
    d.rectangle([ox, oy, ox + 11, oy + 23], fill=PAL["roof_sh"])
    d.rectangle([ox + 13, oy, ox + 23, oy + 23], fill=PAL["roof_hi"])
    # diagonal ridges from peak to the 4 corners
    for (cx, cy) in ((0, 0), (23, 0), (0, 23), (23, 23)):
        d.line([(ox + 12, oy + 12), (ox + cx, oy + cy)], fill=PAL["ridge"])
    # flat peak cap
    d.rectangle([ox + 10, oy + 10, ox + 13, oy + 13], fill=PAL["roof_hi"])
    # chimney footprint (3x3) on the peak
    d.rectangle([ox + 10, oy + 10, ox + 12, oy + 12], fill=PAL["chimney"])
    d.rectangle([ox + 11, oy + 11, ox + 11, oy + 11], fill=PAL["chimney_top"])
    return crop(add_outline(img))


def side_view() -> Image.Image:
    img = Image.new("RGBA", (L + 2, TOTAL_H + 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox = oy = 1
    _draw_chimney(d, ox, oy)
    for row, (x0, x1) in ROOF_ROWS.items():
        _roof_row(d, ox, oy, row, x0, x1)
    _draw_walls(d, ox, oy)
    for wx in (4, 16):
        draw_window(d, ox + wx, oy + 17)
    return crop(add_outline(img))


def front_view() -> Image.Image:
    img = Image.new("RGBA", (W + 2, TOTAL_H + 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox = oy = 1
    _draw_chimney(d, ox, oy)
    for row, (x0, x1) in ROOF_ROWS.items():
        _roof_row(d, ox, oy, row, x0, x1)
    _draw_walls(d, ox, oy)
    # door X 10..13, Z 0..6 -> rows 19..25
    d.rectangle([ox + 10, oy + 19, ox + 13, oy + 25], fill=PAL["door_d"])
    d.rectangle([ox + 11, oy + 19, ox + 12, oy + 25], fill=PAL["door"])
    d.rectangle([ox + 12, oy + 22, ox + 12, oy + 22], fill=PAL["door_knob"])
    for wx in (4, 16):
        draw_window(d, ox + wx, oy + 17)
    return crop(add_outline(img))


def back_view() -> Image.Image:
    img = Image.new("RGBA", (W + 2, TOTAL_H + 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox = oy = 1
    _draw_chimney(d, ox, oy)
    for row, (x0, x1) in ROOF_ROWS.items():
        _roof_row(d, ox, oy, row, x0, x1)
    _draw_walls(d, ox, oy)
    for wx in (4, 16):
        draw_window(d, ox + wx, oy + 17)
    # small attic window
    d.rectangle([ox + 10, oy + 15, ox + 13, oy + 16], fill=PAL["frame"])
    d.rectangle([ox + 11, oy + 15, ox + 12, oy + 16], fill=PAL["glass"])
    return crop(add_outline(img))


def compose_sheet(views: list[Image.Image], out_path: Path, scale: int = 8, gap: int = 6) -> None:
    up = [v.resize((v.width * scale, v.height * scale), Image.NEAREST) for v in views]
    gap_px = gap * scale
    h = max(v.height for v in up)
    w = sum(v.width for v in up) + gap_px * (len(up) - 1)
    sheet = Image.new("RGBA", (w, h), (255, 255, 255, 255))
    x = 0
    for v in up:
        sheet.paste(v, (x, (h - v.height) // 2), v)
        x += v.width + gap_px
    sheet.convert("RGB").save(out_path)


def main() -> None:
    out_dir = Path(__file__).resolve().parent
    views = [top_view(), side_view(), front_view(), back_view()]
    for name, v in zip(["top", "side", "front", "back"], views):
        print(name, v.size)
    compose_sheet(views, out_dir / "views.png")
    print("wrote", out_dir / "views.png")


if __name__ == "__main__":
    main()
