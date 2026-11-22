#!/usr/bin/env python3
"""Builds the documentation previews for flutter_sprite_stack.

Requires Pillow (dev-only):

    uv venv .venv && . .venv/bin/activate && uv pip install pillow
    python3 tool/make_preview.py

Outputs:
    doc/preview.png    three angles side by side (pub.dev screenshot)
    doc/turntable.gif  full 360 turn (README)
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
STRIP = ROOT / "example" / "assets" / "robot_stack.png"
OUT = ROOT / "doc"

SLICES = 24
SLICE = 32
SCALE = 5
PITCH = 0.55
SPACING = 1.0
MARGIN = 18
TILE = 320


def squash_for(pitch: float) -> float:
    return max(0.08, min(1.0, math.sin(max(0.0, min(pitch, math.pi / 2)))))


def background(size: tuple[int, int]) -> Image.Image:
    width, height = size
    image = Image.new("RGBA", size, (18, 22, 31, 255))
    draw = ImageDraw.Draw(image)
    for y in range(height):
        t = y / max(1, height - 1)
        color = (
            int(18 + (10 - 18) * t),
            int(22 + (14 - 22) * t),
            int(31 + (22 - 31) * t),
            255,
        )
        draw.line((0, y, width, y), fill=color)
    return image


def render(stack: Image.Image, angle: float) -> Image.Image:
    squash = squash_for(PITCH)
    cos = abs(math.cos(angle))
    sin = abs(math.sin(angle))
    width = (SLICE * cos + SLICE * sin) * SCALE
    height = (SLICE * sin + SLICE * cos) * squash * SCALE + (SLICES - 1) * SPACING * SCALE
    canvas = Image.new("RGBA", (int(width) + MARGIN * 2, int(height) + MARGIN * 2), (0, 0, 0, 0))
    ground_x = MARGIN + width / 2
    ground_y = MARGIN + height

    for z in range(SLICES):
        slice_image = stack.crop((z * SLICE, 0, (z + 1) * SLICE, SLICE))
        rotated = slice_image.rotate(
            -math.degrees(angle), resample=Image.Resampling.NEAREST, expand=True
        )
        scaled = rotated.resize(
            (
                max(1, round(rotated.width * SCALE)),
                max(1, round(rotated.height * squash * SCALE)),
            ),
            Image.Resampling.NEAREST,
        )
        center_y = ground_y - (SLICE * squash * SCALE) / 2 - z * SPACING * SCALE
        canvas.alpha_composite(
            scaled,
            (round(ground_x - scaled.width / 2), round(center_y - scaled.height / 2)),
        )
    return canvas


def compose(prop: Image.Image, size: int = TILE) -> Image.Image:
    scene = background((size, size))
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(shadow)
    cx = size / 2
    cy = size - MARGIN
    draw.ellipse(
        (cx - 44, cy - 14, cx + 44, cy + 12),
        fill=(0, 0, 0, 110),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(10))
    scene.alpha_composite(shadow)

    x = round((size - prop.width) / 2)
    y = round(size - MARGIN - prop.height)
    scene.alpha_composite(prop, (x, y))
    return scene


def main() -> None:
    OUT.mkdir(exist_ok=True)
    stack = Image.open(STRIP).convert("RGBA")
    if stack.width != SLICE * SLICES:
        raise SystemExit(f"unexpected strip size {stack.size}")

    angles = [0.0, math.pi / 6, math.pi / 4, math.pi / 3]
    tiles = [compose(render(stack, angle)) for angle in angles]
    sheet = Image.new("RGBA", (TILE * len(tiles), TILE), (18, 22, 31, 255))
    for index, tile in enumerate(tiles):
        sheet.alpha_composite(tile, (index * TILE, 0))
    sheet.convert("RGB").save(OUT / "preview.png", optimize=True)

    frames = [compose(render(stack, i * 2 * math.pi / 48)) for i in range(48)]
    frames[0].save(
        OUT / "turntable.gif",
        save_all=True,
        append_images=frames[1:],
        duration=60,
        loop=0,
        optimize=True,
        disposal=2,
    )
    print(f"wrote {OUT / 'preview.png'} and {OUT / 'turntable.gif'}")


if __name__ == "__main__":
    main()
