#!/usr/bin/env python3
"""Draw four orthographic views of a chunky cherry-blossom tree.

Layout: 1x4 row (TOP, SIDE, FRONT, BACK) on flat white, 8x nearest upscale.
Geometry: 30x30 canopy footprint, 6px trunk, 41px tall.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

PAL = {
    "outline": (34, 22, 30),
    "trunk": (116, 78, 48),
    "trunk_sh": (72, 46, 30),
    "trunk_hi": (172, 124, 78),
    "bark": (58, 36, 26),
    "canopy_sh": (150, 58, 112),
    "canopy_mid": (224, 100, 152),
    "canopy_hi": (250, 172, 190),
    "blossom": (255, 238, 246),
}

W = L = 32          # front/back width and side length (including the 1px outline)
H = 41              # trunk + crown height in slices (excluding the outline)
CANOPY_BOX = [1, 12, 30, 40]   # left, top, right, bottom (crown)
TRUNK_BOX = [13, 0, 18, 16]    # left, top, right, bottom (trunk)
TOP_BOX = [1, 1, 30, 30]       # top-down crown footprint


def add_outline(img: Image.Image, color=PAL["outline"]) -> Image.Image:
    """Draw a 1px 8-connected dark outline around every opaque region."""
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


def _vertical_view() -> Image.Image:
    """SIDE / FRONT / BACK: trunk + layered crown (symmetric tree).

    Ground (z = 0) is at the bottom of the image, matching the slicer's
    expectation that the SIDE row `H - 1` is the ground slice.
    """
    img = Image.new("RGBA", (W + 2, H + 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox = oy = 1

    def py(z: int) -> int:
        return oy + (H - 1 - z)

    # Crown: base, then shaded underside and lit upper-left/right clusters.
    d.ellipse([ox + CANOPY_BOX[0], py(CANOPY_BOX[3]), ox + CANOPY_BOX[2], py(CANOPY_BOX[1])], fill=PAL["canopy_mid"])
    d.ellipse([ox + 10, py(26), ox + 30, py(12)], fill=PAL["canopy_sh"])
    d.ellipse([ox + 2, py(40), ox + 16, py(28)], fill=PAL["canopy_hi"])
    d.ellipse([ox + 18, py(38), ox + 28, py(30)], fill=PAL["canopy_hi"])

    # Trunk.
    d.rectangle([ox + TRUNK_BOX[0], py(TRUNK_BOX[3]), ox + TRUNK_BOX[2], py(TRUNK_BOX[1])], fill=PAL["trunk"])
    d.rectangle([ox + 13, py(16), ox + 13, py(0)], fill=PAL["trunk_sh"])
    d.rectangle([ox + 18, py(16), ox + 18, py(0)], fill=PAL["trunk_hi"])
    for (x, z) in [(15, 3), (16, 8), (15, 12)]:
        d.point((ox + x, py(z)), fill=PAL["bark"])

    # Blossom specks on the crown.
    for (x, z) in [(5, 16), (11, 13), (19, 17), (26, 15), (15, 24), (23, 26), (8, 22), (27, 24)]:
        d.point((ox + x, py(z)), fill=PAL["blossom"])

    return crop(add_outline(img))


def _top_view() -> Image.Image:
    """TOP: round crown footprint with clustered highlights/shadows."""
    img = Image.new("RGBA", (W + 2, L + 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox = oy = 1

    d.ellipse([ox + TOP_BOX[0], oy + TOP_BOX[1], ox + TOP_BOX[2], oy + TOP_BOX[3]], fill=PAL["canopy_mid"])
    d.ellipse([ox + 3, oy + 3, ox + 16, oy + 16], fill=PAL["canopy_hi"])
    d.ellipse([ox + 16, oy + 16, ox + 29, oy + 29], fill=PAL["canopy_sh"])
    d.ellipse([ox + 11, oy + 8, ox + 22, oy + 15], fill=PAL["canopy_hi"])

    for (x, y) in [(6, 6), (13, 5), (22, 8), (26, 13), (19, 19), (9, 15), (16, 12)]:
        d.point((ox + x, oy + y), fill=PAL["blossom"])

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
    views = [_top_view(), _vertical_view(), _vertical_view(), _vertical_view()]
    for name, v in zip(("top", "side", "front", "back"), views):
        print(name, v.size)
    compose_sheet(views, out_dir / "views.png")
    print("wrote", out_dir / "views.png")


if __name__ == "__main__":
    main()
