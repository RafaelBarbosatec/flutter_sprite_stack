#!/usr/bin/env python3
"""Draw the four orthographic views of a chunky blue car and compose the model sheet.

Outputs views.png: a 1x4 row (TOP, SIDE, FRONT, BACK), flat white, 8x nearest upscale.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

PAL = {
    "outline": (26, 26, 46),
    "body": (46, 98, 216),       # saturated mid blue
    "shadow": (26, 58, 142),     # cool deep shadow
    "light": (150, 188, 255),    # warm bright highlight
    "glass": (36, 66, 128),      # windshield / windows
    "glass_h": (205, 225, 255),  # glass specular
    "tire": (32, 32, 40),
    "tire_h": (74, 74, 86),
    "head": (255, 226, 92),      # headlight
    "tail": (226, 52, 52),       # taillight
    "bumper": (198, 202, 212),
    "bumper_d": (120, 124, 134),
    "grille": (18, 22, 34),
}


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


def top_view() -> Image.Image:
    # 16 wide x 32 long, front pointing DOWN (row 31). +1 px margin for outline.
    img = Image.new("RGBA", (18, 34), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox = oy = 1
    d.rounded_rectangle([ox + 0, oy + 0, ox + 15, oy + 31], radius=2, fill=PAL["body"])
    d.rectangle([ox + 1, oy + 1, ox + 2, oy + 30], fill=PAL["shadow"])
    d.rectangle([ox + 13, oy + 1, ox + 14, oy + 30], fill=PAL["shadow"])
    d.rectangle([ox + 6, oy + 1, ox + 8, oy + 30], fill=PAL["light"])
    # windshield (front, bottom) + rear window (back, top): glass seen from above.
    # These top-view glass areas become the windshield/rear-window faces in the hull.
    d.rectangle([ox + 2, oy + 3, ox + 13, oy + 6], fill=PAL["glass"])
    d.rectangle([ox + 6, oy + 4, ox + 7, oy + 5], fill=PAL["glass_h"])
    d.rectangle([ox + 2, oy + 25, ox + 13, oy + 28], fill=PAL["glass"])
    d.rectangle([ox + 6, oy + 26, ox + 7, oy + 27], fill=PAL["glass_h"])
    return crop(add_outline(img))


def side_view() -> Image.Image:
    # 32 long x 16 tall, front pointing LEFT (col 0). +1 px margin for outline.
    img = Image.new("RGBA", (34, 18), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox = oy = 1
    # cabin: cols 9-20, rows 0-10 (roof at 0)
    d.rectangle([ox + 9, oy + 0, ox + 20, oy + 10], fill=PAL["body"])
    # main body: hood + doors + trunk, cols 1-29, rows 2-10
    d.rectangle([ox + 1, oy + 2, ox + 29, oy + 10], fill=PAL["body"])
    # bumpers
    d.rectangle([ox + 0, oy + 5, ox + 1, oy + 10], fill=PAL["bumper"])
    d.rectangle([ox + 30, oy + 5, ox + 31, oy + 10], fill=PAL["bumper"])
    # glass band (windows)
    d.rectangle([ox + 10, oy + 1, ox + 20, oy + 4], fill=PAL["glass"])
    d.rectangle([ox + 13, oy + 1, ox + 14, oy + 4], fill=PAL["glass_h"])
    # deck highlights
    d.rectangle([ox + 2, oy + 2, ox + 8, oy + 2], fill=PAL["light"])
    d.rectangle([ox + 22, oy + 2, ox + 28, oy + 2], fill=PAL["light"])
    d.rectangle([ox + 11, oy + 0, ox + 19, oy + 0], fill=PAL["light"])
    # door highlight
    d.rectangle([ox + 11, oy + 6, ox + 19, oy + 6], fill=PAL["light"])
    # bottom shadow
    d.rectangle([ox + 1, oy + 9, ox + 29, oy + 10], fill=PAL["shadow"])
    # wheels (rows 11-15, directly under body bottom row 10)
    d.ellipse([ox + 4, oy + 11, ox + 8, oy + 15], fill=PAL["tire"])
    d.ellipse([ox + 21, oy + 11, ox + 25, oy + 15], fill=PAL["tire"])
    d.rectangle([ox + 5, oy + 12, ox + 6, oy + 13], fill=PAL["tire_h"])
    d.rectangle([ox + 22, oy + 12, ox + 23, oy + 13], fill=PAL["tire_h"])
    return crop(add_outline(img))


def front_view() -> Image.Image:
    img = Image.new("RGBA", (18, 18), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox = oy = 1
    d.rounded_rectangle([ox + 0, oy + 0, ox + 15, oy + 10], radius=2, fill=PAL["body"])
    # wheels
    d.ellipse([ox + 0, oy + 11, ox + 4, oy + 15], fill=PAL["tire"])
    d.ellipse([ox + 11, oy + 11, ox + 15, oy + 15], fill=PAL["tire"])
    d.rectangle([ox + 1, oy + 12, ox + 2, oy + 13], fill=PAL["tire_h"])
    d.rectangle([ox + 12, oy + 12, ox + 13, oy + 13], fill=PAL["tire_h"])
    # windshield
    d.rectangle([ox + 3, oy + 1, ox + 12, oy + 4], fill=PAL["glass"])
    d.rectangle([ox + 6, oy + 2, ox + 7, oy + 3], fill=PAL["glass_h"])
    # headlights + grille
    d.rectangle([ox + 2, oy + 6, ox + 4, oy + 8], fill=PAL["head"])
    d.rectangle([ox + 11, oy + 6, ox + 13, oy + 8], fill=PAL["head"])
    d.rectangle([ox + 5, oy + 6, ox + 10, oy + 8], fill=PAL["grille"])
    # bumper + bottom shadow
    d.rectangle([ox + 2, oy + 9, ox + 13, oy + 9], fill=PAL["bumper"])
    d.rectangle([ox + 0, oy + 10, ox + 15, oy + 10], fill=PAL["shadow"])
    return crop(add_outline(img))


def back_view() -> Image.Image:
    img = Image.new("RGBA", (18, 18), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox = oy = 1
    d.rounded_rectangle([ox + 0, oy + 0, ox + 15, oy + 10], radius=2, fill=PAL["body"])
    d.ellipse([ox + 0, oy + 11, ox + 4, oy + 15], fill=PAL["tire"])
    d.ellipse([ox + 11, oy + 11, ox + 15, oy + 15], fill=PAL["tire"])
    d.rectangle([ox + 1, oy + 12, ox + 2, oy + 13], fill=PAL["tire_h"])
    d.rectangle([ox + 12, oy + 12, ox + 13, oy + 13], fill=PAL["tire_h"])
    # rear window
    d.rectangle([ox + 3, oy + 1, ox + 12, oy + 4], fill=PAL["glass"])
    d.rectangle([ox + 6, oy + 2, ox + 7, oy + 3], fill=PAL["glass_h"])
    # taillights + rear panel
    d.rectangle([ox + 2, oy + 6, ox + 4, oy + 8], fill=PAL["tail"])
    d.rectangle([ox + 11, oy + 6, ox + 13, oy + 8], fill=PAL["tail"])
    d.rectangle([ox + 5, oy + 6, ox + 10, oy + 8], fill=PAL["bumper_d"])
    d.rectangle([ox + 2, oy + 9, ox + 13, oy + 9], fill=PAL["bumper"])
    d.rectangle([ox + 0, oy + 10, ox + 15, oy + 10], fill=PAL["shadow"])
    return crop(add_outline(img))


def compose_sheet(views: list[Image.Image], out_path: Path, scale: int = 8, gap: int = 6) -> None:
    up = [v.resize((v.width * scale, v.height * scale), Image.NEAREST) for v in views]
    gap_px = gap * scale
    h = max(v.height for v in up)
    w = sum(v.width for v in up) + gap_px * (len(up) - 1)
    sheet = Image.new("RGBA", (w, h), (255, 255, 255, 255))
    x = 0
    for v in up:
        sheet.paste(v, (x, (h - v.height) // 2), v)  # alpha mask keeps white gaps
        x += v.width + gap_px
    sheet.convert("RGB").save(out_path)


def main() -> None:
    out_dir = Path(__file__).resolve().parent
    views = [top_view(), side_view(), front_view(), back_view()]
    for i, name in enumerate(["top", "side", "front", "back"]):
        print(name, views[i].size)
    compose_sheet(views, out_dir / "views.png")
    print("wrote", out_dir / "views.png")


if __name__ == "__main__":
    main()
