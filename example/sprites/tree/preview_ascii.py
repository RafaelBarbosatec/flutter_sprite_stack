#!/usr/bin/env python3
"""Render the carved tree stack at several angles and print ASCII previews."""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

SLICER = Path("/home/rafael/.pi/agent/git/github.com/danielwh2/sprite-stacking/skills/sprite-stacking/scripts")
sys.path.insert(0, str(SLICER))

from views_to_slices import views_to_slices, render_stack_image  # noqa: E402

PALETTE = {
    (20, 26, 16): "#", (104, 72, 44): "t", (64, 44, 26): "T",
    (156, 112, 66): "h", (46, 30, 20): "k", (96, 68, 42): "b", (58, 40, 24): "B",
    (48, 92, 50): "d", (82, 142, 70): "m", (138, 190, 92): "l",
    (182, 218, 118): "L", (206, 232, 140): "w",
}
K = list(PALETTE)
A = np.array(K).astype(int)


def classify(px):
    r, g, b, a = px
    if a < 128:
        return " "
    d = ((A - (r, g, b)) ** 2).sum(-1)
    return PALETTE[K[int(d.argmin())]]


def to_ascii(img: Image.Image, max_w: int = 64) -> str:
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
    vol, views = views_to_slices(sheet, slices=43, top_nose="down", side_nose="left", order="reading", round_=True)
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
