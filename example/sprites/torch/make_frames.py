#!/usr/bin/env python3
"""Generate a 5-frame torch atlas for the animation example.

The atlas is a vertical stack of frames, each one a horizontal strip of
cross-sections (ground slice first, left to right):

    frame 0: [z0][z1]...[z13]
    frame 1: [z0][z1]...[z13]
    ...

Frame 0 sits on top. The flame is drawn as a stack of shrinking discs whose
centre wobbles per frame, which is enough to read as a flicker without any
hand-drawn frames.

Output: frames.png (14 slices x 16 px, 5 frames x 16 px).
"""
from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image

SIZE = 16
SLICES = 14
FRAMES = 5
OUT = Path(__file__).with_name("frames.png")

WOOD = (104, 68, 42)
WOOD_DARK = (74, 46, 28)
BAND = (96, 102, 116)
BAND_DARK = (62, 68, 82)
FLAME_OUTER = (232, 116, 36)
FLAME_MID = (250, 168, 52)
FLAME_CORE = (255, 232, 132)
EMBER = (176, 54, 28)


def disc(cx: float, cy: float, radius: float) -> list[tuple[int, int]]:
    out = []
    r2 = radius * radius
    for y in range(SIZE):
        for x in range(SIZE):
            if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r2:
                out.append((x, y))
    return out


def handle_slice() -> list[tuple[int, int, int, int, int, int]]:
    cx = cy = SIZE / 2
    pixels = []
    for x, y in disc(cx, cy, 2.9):
        # Simple cylindrical shading: darker towards the left edge.
        t = (x + 0.5 - cx) / 2.9
        color = WOOD if t > -0.35 else WOOD_DARK
        pixels.append((x, y, *color, 255))
    return pixels


def band_slice() -> list[tuple[int, int, int, int, int, int]]:
    cx = cy = SIZE / 2
    pixels = []
    for x, y in disc(cx, cy, 3.2):
        color = BAND if (x + y) % 3 else BAND_DARK
        pixels.append((x, y, *color, 255))
    return pixels


def flame_slice(
    z: int, frame: int
) -> list[tuple[int, int, int, int, int, int]]:
    """One cross-section of a teardrop flame that wobbles per frame."""
    t = (z - 9) / (SLICES - 10)  # 0 at the base of the flame, 1 at the tip
    radius = 3.2 * (1 - t) ** 0.75 + 0.7
    wobble = 1.15 * (1 - t)
    cx = SIZE / 2 + wobble * math.sin(frame * 1.7 + z * 0.35)
    cy = SIZE / 2 + wobble * 0.7 * math.cos(frame * 1.3 + z * 0.5)

    rng = random.Random(1000 + frame * 97 + z)
    pixels = []
    for x, y in disc(cx, cy, radius):
        d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
        if d <= radius * 0.45:
            color = FLAME_CORE
        elif d <= radius * 0.78:
            color = FLAME_MID
        else:
            color = FLAME_OUTER
        # A few embers along the rim so the silhouette is not a clean circle.
        if d > radius * 0.8 and rng.random() < 0.18:
            color = EMBER
        pixels.append((x, y, *color, 255))
    return pixels


def main() -> None:
    atlas = Image.new("RGBA", (SIZE * SLICES, SIZE * FRAMES), (0, 0, 0, 0))
    for frame in range(FRAMES):
        strip = Image.new("RGBA", (SIZE * SLICES, SIZE), (0, 0, 0, 0))
        for z in range(SLICES):
            if z <= 7:
                pixels = handle_slice()
            elif z == 8:
                pixels = band_slice()
            else:
                pixels = flame_slice(z, frame)
            for x, y, r, g, b, a in pixels:
                strip.putpixel((z * SIZE + x, y), (r, g, b, a))
        atlas.paste(strip, (0, frame * SIZE))

    atlas.save(OUT)
    print(f"wrote {OUT} ({atlas.width}x{atlas.height})")


if __name__ == "__main__":
    main()
