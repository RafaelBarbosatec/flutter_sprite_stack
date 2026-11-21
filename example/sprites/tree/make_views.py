#!/usr/bin/env python3
"""Draw four orthographic views of a chunky leafy green tree.

Layout: 1x4 row (TOP, SIDE, FRONT, BACK) on flat white, 8x nearest upscale.
Geometry: a gnarly branch flare lifts a cluster of overlapping leaf "puffs"
off the trunk, so the carved canopy reads as several bunched clumps of
foliage with bark peeking through the gaps, instead of one smooth ball.
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

PAL = {
    "outline": (20, 26, 16),
    "trunk": (104, 72, 44),
    "trunk_sh": (64, 44, 26),
    "trunk_hi": (156, 112, 66),
    "bark": (46, 30, 20),
    "branch": (96, 68, 42),
    "branch_sh": (58, 40, 24),
    "canopy_sh": (48, 92, 50),
    "canopy_mid": (82, 142, 70),
    "canopy_hi": (138, 190, 92),
    "canopy_hi2": (182, 218, 118),
    "leaf_fleck": (206, 232, 140),
}

W = L = 36          # front/back width and side length (including the 1px outline)
H = 47              # trunk + crown height in slices (excluding the outline)
CX = 17.0           # canopy / trunk horizontal centre (art px)

# Canopy envelope: three overlapping "puff" lobes stacked bottom to top, so the
# silhouette bulges and necks rather than forming one plain sphere.
PUFFS = [
    # (centre_z, half_height, half_width)
    (21.0, 10.5, 16.0),
    (31.0, 8.5, 13.5),
    (39.5, 6.5, 9.5),
]

TRUNK_TOP = 11       # bare trunk up to this z
FLARE_TOP = 15       # short fork spreads out to this z before leaves take over


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


def puff_half_width(z: float) -> float:
    """Union half-width of the stacked canopy puffs at height z (0 outside all of them)."""
    best = 0.0
    for cz, hh, hw in PUFFS:
        t = (z - cz) / hh
        if -1.0 < t < 1.0:
            best = max(best, hw * math.sqrt(1.0 - t * t))
    return best


def _vertical_view() -> Image.Image:
    """SIDE / FRONT / BACK: trunk, branch flare and layered canopy puffs.

    Ground (z = 0) is at the bottom of the image, matching the slicer's
    expectation that the SIDE row `H - 1` is the ground slice.
    """
    img = Image.new("RGBA", (W + 2, H + 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox = oy = 1

    def py(z: float) -> int:
        return oy + round(H - 1 - z)

    def ebox(x0: float, x1: float, z0: float, z1: float):
        return [ox + round(x0), py(z1), ox + round(x1), py(z0)]

    # --- Canopy puffs (back to front: lower, then mid, then top tuft) ---
    for cz, hh, hw in PUFFS:
        d.ellipse(ebox(CX - hw, CX + hw, cz - hh, cz + hh), fill=PAL["canopy_mid"])

    # Gentle shading: shadow under each puff, soft highlight on the upper-left.
    for cz, hh, hw in PUFFS:
        d.ellipse(ebox(CX + hw * 0.1, CX + hw * 0.9, cz - hh * 0.85, cz - hh * 0.1), fill=PAL["canopy_sh"])
        d.ellipse(ebox(CX - hw * 0.8, CX + hw * 0.05, cz + hh * 0.1, cz + hh * 0.8), fill=PAL["canopy_hi"])
        d.ellipse(ebox(CX - hw * 0.4, CX + hw * 0.05, cz + hh * 0.35, cz + hh * 0.75), fill=PAL["canopy_hi2"])

    # Small extra leaf clumps bulging off the main puffs, so the outline reads
    # as bunched foliage rather than three plain circles.
    extra_clumps = [
        (CX - 14.0, 19.0, 5.0, PAL["canopy_mid"]),
        (CX + 13.5, 23.5, 4.6, PAL["canopy_mid"]),
        (CX - 10.5, 34.5, 4.0, PAL["canopy_hi"]),
        (CX + 10.0, 37.0, 4.0, PAL["canopy_sh"]),
        (CX - 5.5, 43.5, 3.2, PAL["canopy_hi2"]),
        (CX + 6.5, 42.0, 3.0, PAL["canopy_mid"]),
    ]
    for cx, cz, r, colour in extra_clumps:
        d.ellipse(ebox(cx - r, cx + r, cz - r, cz + r), fill=colour)

    # Tiny branch tips just barely peeking between the clumps (kept small and
    # sparse so bark reads as an accent, not a tangle of roots).
    branch_tips = [(CX - 12.5, 20.0), (CX + 12.0, 24.5), (CX - 9.5, 33.5), (CX + 9.0, 36.0)]
    for tx, tz in branch_tips:
        d.ellipse(ebox(tx - 1.6, tx + 1.6, tz - 1.4, tz + 1.4), fill=PAL["branch"])
        d.point((ox + round(tx), py(tz + 1)), fill=PAL["branch_sh"])

    # --- Short fork: trunk splits into two stubby branches holding the lowest puff. ---
    for side_sign in (-1, 1):
        x0, x1 = CX, CX + side_sign * 7.5
        z0, z1 = TRUNK_TOP, FLARE_TOP
        steps = 8
        for i in range(steps):
            t0, t1 = i / steps, (i + 1) / steps
            bx0, bx1 = x0 + (x1 - x0) * t0, x0 + (x1 - x0) * t1
            bz0, bz1 = z0 + (z1 - z0) * t0, z0 + (z1 - z0) * t1
            thick = max(2, round(3.2 * (1.0 - 0.4 * t0)))
            d.line([ox + round(bx0), py(bz0), ox + round(bx1), py(bz1)], fill=PAL["branch"], width=thick)
    d.rectangle(ebox(CX - 3.0, CX + 3.0, TRUNK_TOP - 1, TRUNK_TOP + 1), fill=PAL["branch"])

    # --- Trunk ---
    d.rectangle(ebox(CX - 3.0, CX + 3.0, 0, TRUNK_TOP), fill=PAL["trunk"])
    d.rectangle(ebox(CX - 3.0, CX - 2.0, 0, TRUNK_TOP), fill=PAL["trunk_sh"])
    d.rectangle(ebox(CX + 2.0, CX + 3.0, 0, TRUNK_TOP), fill=PAL["trunk_hi"])
    for (x, z) in [(CX - 1.0, 2), (CX, 5), (CX - 1.5, 7), (CX + 1.0, 4), (CX - 0.5, 9)]:
        d.point((ox + round(x), py(z)), fill=PAL["bark"])

    # Leaf flecks scattered on the canopy for sparkle.
    flecks = [
        (CX - 10, 14), (CX - 2, 12), (CX + 9, 16), (CX + 14, 22),
        (CX - 14, 20), (CX - 6, 27), (CX + 4, 30), (CX + 10, 33),
        (CX - 9, 36), (CX - 2, 41), (CX + 5, 43), (CX - 4, 25),
    ]
    for (x, z) in flecks:
        d.point((ox + round(x), py(z)), fill=PAL["leaf_fleck"])

    return crop(add_outline(img))


def _top_view() -> Image.Image:
    """TOP: lumpy cloud-shaped crown footprint made of several overlapping puffs."""
    img = Image.new("RGBA", (W + 2, L + 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox = oy = 1
    cx = cy = 17.5

    def cbox(x0: float, y0: float, x1: float, y1: float):
        return [ox + round(x0), oy + round(y0), ox + round(x1), oy + round(y1)]

    # Main lobes: one big centre mass plus several puffs ringed around it so
    # the footprint reads as bunched clumps, not a single disc.
    lobes = [
        (cx, cy, 13.5, PAL["canopy_mid"]),
        (cx - 11.5, cy - 4.0, 7.5, PAL["canopy_mid"]),
        (cx + 11.0, cy - 2.0, 7.0, PAL["canopy_mid"]),
        (cx - 7.0, cy + 10.5, 6.5, PAL["canopy_mid"]),
        (cx + 8.5, cy + 9.5, 6.0, PAL["canopy_mid"]),
        (cx - 1.0, cy - 12.0, 6.0, PAL["canopy_mid"]),
        (cx + 1.5, cy + 13.0, 5.0, PAL["canopy_mid"]),
    ]
    for lx, ly, r, colour in lobes:
        d.ellipse(cbox(lx - r, ly - r, lx + r, ly + r), fill=colour)

    # Lighting: sunlit clump upper-left, shadow clump lower-right, warm top highlight.
    d.ellipse(cbox(cx - 15, cy - 15, cx + 6, cy + 4), fill=PAL["canopy_hi"])
    d.ellipse(cbox(cx - 3, cy + 2, cx + 16, cy + 16), fill=PAL["canopy_sh"])
    d.ellipse(cbox(cx - 9, cy - 14, cx + 3, cy - 2), fill=PAL["canopy_hi2"])
    d.ellipse(cbox(cx - 13, cy - 7, cx - 3, cy + 2), fill=PAL["canopy_hi2"])

    # Tiny branch flecks near the hub, bark just peeking between the clumps.
    gaps = [
        (cx - 9.5, cy - 2.5, 1.3), (cx + 9.0, cy - 0.5, 1.2),
        (cx - 5.5, cy + 9.0, 1.1), (cx + 6.5, cy + 8.0, 1.0),
    ]
    for gx, gy, r in gaps:
        d.ellipse(cbox(gx - r, gy - r, gx + r, gy + r), fill=PAL["branch"])

    for (x, y) in [
        (cx - 8, cy - 8), (cx + 2, cy - 11), (cx + 10, cy - 4), (cx + 12, cy + 7),
        (cx - 11, cy + 2), (cx - 2, cy + 12), (cx + 1, cy + 1), (cx - 4, cy - 2),
    ]:
        d.point((ox + round(x), oy + round(y)), fill=PAL["leaf_fleck"])

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
