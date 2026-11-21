#!/usr/bin/env python3
"""Render the carved F1 car stack at several angles and print ASCII previews."""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

SLICER = Path("/home/rafael/.pi/agent/git/github.com/danielwh2/sprite-stacking/skills/sprite-stacking/scripts")
sys.path.insert(0, str(SLICER))

from views_to_slices import views_to_slices, render_stack_image  # noqa: E402

PALETTE = {
    (14, 16, 22): "#", (208, 32, 40): "R", (140, 20, 28): "r",
    (255, 118, 88): "h", (30, 32, 44): "W", (120, 130, 156): "w",
    (22, 22, 30): "T", (74, 74, 88): "t", (160, 164, 180): "H",
    (16, 20, 30): "C", (210, 216, 228): "G", (244, 246, 250): "A",
    (48, 50, 62): "D",
}
K = list(PALETTE)
A = np.array(K).astype(int)


def classify(px):
    r, g, b, a = px
    if a < 128:
        return " "
    d = ((A - (r, g, b)) ** 2).sum(-1)
    return PALETTE[K[int(d.argmin())]]


def to_ascii(img: Image.Image, max_w: int = 76) -> str:
    a = np.array(img.convert("RGBA"))
    h, w = a.shape[:2]
    step = max(1, round(w / max_w))
    out = []
    for y in range(0, h, step):
        row = []
        for x in range(0, w, step):
            block = a[y: y + step, x: x + step]
            opaque = block[block[..., 3] > 128]
            if len(opaque) == 0:
                row.append(" ")
            else:
                row.append(classify(np.median(opaque, axis=0).astype(int)))
        out.append("".join(row))
    return "\n".join(out)


def main():
    sheet = np.array(Image.open("views.png").convert("RGBA"))
    vol, views = views_to_slices(sheet, slices=16, top_nose="down", side_nose="left", order="reading")
    print("vol shape (slices, H, W):", vol.shape[:3])
    for name, v in zip(["TOP", "SIDE", "FRONT", "BACK"], views):
        print(f"\n== {name} ==")
        print("\n".join("".join(classify(p) for p in row) for row in v))
    for angle in (0, 45, 90, 135, 180, 225, 270, 315):
        frame = render_stack_image(vol, angle, squash=0.75, spacing=1.0, shadow=True, outline=True)
        print(f"\n===== angle {angle} =====")
        print(to_ascii(frame))


if __name__ == "__main__":
    main()
