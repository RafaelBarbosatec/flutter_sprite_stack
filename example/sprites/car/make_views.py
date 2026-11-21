#!/usr/bin/env python3
"""Draw four orthographic views of a chunky red Formula 1 car.

Layout: 1x4 row (TOP, SIDE, FRONT, BACK) on flat white, 8x nearest upscale.
Geometry: 72px long, 36px wide, 22px tall, with open wheels and full-width wings.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

PAL = {
    "outline": (14, 16, 22),
    "body": (208, 32, 40),
    "body_sh": (140, 20, 28),
    "body_hi": (255, 118, 88),
    "wing": (30, 32, 44),
    "wing_hi": (120, 130, 156),
    "tire": (22, 22, 30),
    "tire_hi": (74, 74, 88),
    "hub": (160, 164, 180),
    "cockpit": (16, 20, 30),
    "halo": (210, 216, 228),
    "accent": (244, 246, 250),
    "diffuser": (48, 50, 62),
}

W = 36          # front/back width (including outline)
L = 72          # side length / top-view height (including outline)
H = 16          # slice count (side view height, excluding outline)

# s runs 0 (front) .. 71 (rear) along the car's length.
FRONT_S = 0
REAR_S = L - 1


def top_y(s: int) -> int:
    """Top view y for a length coordinate s (front points down)."""
    return L - 1 - s


def side_x(s: int) -> int:
    """Side view x for a length coordinate s (front points left)."""
    return s


def py(z: int) -> int:
    """Image y for a height coordinate z (ground is z=0 at the bottom)."""
    return H - 1 - z


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


def _top_view() -> Image.Image:
    img = Image.new("RGBA", (W + 2, L + 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox = oy = 1

    # Rear wing (s 62..71) and front wing (s 0..8): full width.
    d.rectangle([ox + 0, oy + top_y(REAR_S), ox + W - 1, oy + top_y(62)], fill=PAL["wing"])
    d.rectangle([ox + 0, oy + top_y(62), ox + W - 1, oy + top_y(62) + 1], fill=PAL["wing_hi"])
    d.rectangle([ox + 0, oy + top_y(8), ox + W - 1, oy + top_y(FRONT_S)], fill=PAL["wing"])
    d.rectangle([ox + 0, oy + top_y(FRONT_S), ox + W - 1, oy + top_y(FRONT_S) + 1], fill=PAL["wing_hi"])

    # Rear wheels (s 49..61, outboard) and front wheels (s 11..23, outboard).
    d.ellipse([ox + 0, oy + top_y(61), ox + 8, oy + top_y(49)], fill=PAL["tire"])
    d.ellipse([ox + W - 9, oy + top_y(61), ox + W - 1, oy + top_y(49)], fill=PAL["tire"])
    d.ellipse([ox + 3, oy + top_y(23), ox + 10, oy + top_y(11)], fill=PAL["tire"])
    d.ellipse([ox + W - 10, oy + top_y(23), ox + W - 3, oy + top_y(11)], fill=PAL["tire"])

    # Central body: nose (s 8..28) and engine cover / sidepods (s 28..52).
    d.rectangle([ox + 12, oy + top_y(28), ox + 24, oy + top_y(8)], fill=PAL["body"])
    d.rectangle([ox + 8, oy + top_y(52), ox + 28, oy + top_y(28)], fill=PAL["body"])
    d.ellipse([ox + 5, oy + top_y(43), ox + 31, oy + top_y(33)], fill=PAL["body"])

    # Racing stripe down the middle.
    d.rectangle([ox + 17, oy + top_y(52), ox + 18, oy + top_y(8)], fill=PAL["accent"])

    # Cockpit opening (kept opaque so it does not carve a hole) + halo.
    d.rectangle([ox + 14, oy + top_y(34), ox + 22, oy + top_y(28)], fill=PAL["cockpit"])
    d.rectangle([ox + 13, oy + top_y(28), ox + 23, oy + top_y(26)], fill=PAL["halo"])

    # Wheel hubs.
    d.ellipse([ox + 4, oy + top_y(57), ox + 7, oy + top_y(54)], fill=PAL["hub"])
    d.ellipse([ox + W - 7, oy + top_y(57), ox + W - 4, oy + top_y(54)], fill=PAL["hub"])
    d.ellipse([ox + 5, oy + top_y(19), ox + 8, oy + top_y(16)], fill=PAL["hub"])
    d.ellipse([ox + W - 8, oy + top_y(19), ox + W - 5, oy + top_y(16)], fill=PAL["hub"])

    return crop(add_outline(img))


def _side_view() -> Image.Image:
    img = Image.new("RGBA", (L + 2, H + 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox = oy = 1

    # Front wing (s 0..8).
    d.rectangle([ox + side_x(0), oy + py(4), ox + side_x(8), oy + py(1)], fill=PAL["wing"])

    # Nose wedge (s 8..28, z 2..8).
    d.polygon(
        [
            (ox + side_x(8), oy + py(4)),
            (ox + side_x(28), oy + py(8)),
            (ox + side_x(28), oy + py(6)),
            (ox + side_x(8), oy + py(2)),
        ],
        fill=PAL["body"],
    )

    # Cockpit + halo (s 28..38).
    d.rectangle([ox + side_x(28), oy + py(11), ox + side_x(38), oy + py(8)], fill=PAL["body"])
    d.rectangle([ox + side_x(31), oy + py(9), ox + side_x(35), oy + py(8)], fill=PAL["cockpit"])
    d.rectangle([ox + side_x(29), oy + py(12), ox + side_x(37), oy + py(11)], fill=PAL["halo"])

    # Engine cover (s 38..52) + shark fin.
    d.rectangle([ox + side_x(38), oy + py(11), ox + side_x(52), oy + py(6)], fill=PAL["body"])
    d.rectangle([ox + side_x(44), oy + py(14), ox + side_x(48), oy + py(11)], fill=PAL["body"])

    # Diffuser (s 54..60) and beam wing (s 56..62).
    d.rectangle([ox + side_x(54), oy + py(5), ox + side_x(60), oy + py(1)], fill=PAL["diffuser"])
    d.rectangle([ox + side_x(56), oy + py(6), ox + side_x(62), oy + py(4)], fill=PAL["wing"])

    # Rear wing (s 62..71), as tall as the wheels so all views share one height.
    d.rectangle([ox + side_x(62), oy + py(14), ox + side_x(71), oy + py(6)], fill=PAL["wing"])
    d.rectangle([ox + side_x(62), oy + py(14), ox + side_x(63), oy + py(6)], fill=PAL["wing_hi"])

    # Wheels (front s 11..23, rear s 49..61).
    d.ellipse([ox + side_x(11), oy + py(14), ox + side_x(23), oy + py(2)], fill=PAL["tire"])
    d.ellipse([ox + side_x(49), oy + py(14), ox + side_x(61), oy + py(2)], fill=PAL["tire"])
    d.ellipse([ox + side_x(15), oy + py(10), ox + side_x(19), oy + py(6)], fill=PAL["hub"])
    d.ellipse([ox + side_x(53), oy + py(10), ox + side_x(57), oy + py(6)], fill=PAL["hub"])

    return crop(add_outline(img))


def _front_view() -> Image.Image:
    img = Image.new("RGBA", (W + 2, H + 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox = oy = 1

    # Front wing (full width).
    d.rectangle([ox + 0, oy + py(4), ox + W - 1, oy + py(1)], fill=PAL["wing"])

    # Front wheels.
    d.ellipse([ox + 3, oy + py(14), ox + 10, oy + py(2)], fill=PAL["tire"])
    d.ellipse([ox + W - 10, oy + py(14), ox + W - 3, oy + py(2)], fill=PAL["tire"])

    # Nose + halo.
    d.rectangle([ox + 12, oy + py(8), ox + 24, oy + py(4)], fill=PAL["body"])
    d.rectangle([ox + 13, oy + py(12), ox + 23, oy + py(11)], fill=PAL["halo"])

    return crop(add_outline(img))


def _back_view() -> Image.Image:
    img = Image.new("RGBA", (W + 2, H + 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox = oy = 1

    # Rear wing + beam wing (full width).
    d.rectangle([ox + 0, oy + py(14), ox + W - 1, oy + py(6)], fill=PAL["wing"])
    d.rectangle([ox + 0, oy + py(6), ox + W - 1, oy + py(4)], fill=PAL["wing"])

    # Rear wheels.
    d.ellipse([ox + 0, oy + py(14), ox + 8, oy + py(2)], fill=PAL["tire"])
    d.ellipse([ox + W - 9, oy + py(14), ox + W - 1, oy + py(2)], fill=PAL["tire"])

    # Gearbox / engine cover + diffuser.
    d.rectangle([ox + 8, oy + py(11), ox + 28, oy + py(4)], fill=PAL["body"])
    d.rectangle([ox + 8, oy + py(5), ox + 28, oy + py(1)], fill=PAL["diffuser"])

    return crop(add_outline(img))


def compose_sheet(views: list[Image.Image], out_path: Path, scale: int = 8, gap: int = 6) -> None:
    up = [v.resize((v.width * scale, v.height * scale), Image.NEAREST) for v in views]
    gap_px = gap * scale
    pad = gap_px
    h = max(v.height for v in up)
    w = sum(v.width for v in up) + gap_px * (len(up) - 1)
    sheet = Image.new("RGBA", (w + pad * 2, h + pad * 2), (255, 255, 255, 255))
    x = pad
    for v in up:
        sheet.paste(v, (x, pad + (h - v.height) // 2), v)
        x += v.width + gap_px
    sheet.convert("RGB").save(out_path)


def main() -> None:
    out_dir = Path(__file__).resolve().parent
    views = [_top_view(), _side_view(), _front_view(), _back_view()]
    for name, v in zip(("top", "side", "front", "back"), views):
        print(name, v.size)
    compose_sheet(views, out_dir / "views.png")
    print("wrote", out_dir / "views.png")


if __name__ == "__main__":
    main()
