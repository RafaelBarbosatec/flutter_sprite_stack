#!/usr/bin/env python3
"""Render the carved stack at several angles and print ASCII previews."""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

SLICER = Path("/home/rafael/.pi/agent/git/github.com/danielwh2/sprite-stacking/skills/sprite-stacking/scripts")
sys.path.insert(0, str(SLICER))

from views_to_slices import views_to_slices, render_stack_image  # noqa: E402


PALETTE = {
    (26, 26, 46): "#", (46, 98, 216): "B", (26, 58, 142): "b",
    (150, 188, 255): "h", (36, 66, 128): "g", (205, 225, 255): "G",
    (32, 32, 40): "#", (74, 74, 86): "w", (255, 226, 92): "Y",
    (226, 52, 52): "R", (198, 202, 212): "s", (120, 124, 134): "d",
    (18, 22, 34): "#",
}
PAL_KEYS = list(PALETTE)
PAL_ARR = np.array(PAL_KEYS).astype(int)


def classify(px):
    """Map an RGBA pixel to an ASCII char via nearest palette color."""
    r, g, b, a = px
    if a < 128:
        return " "
    d = ((PAL_ARR - (r, g, b)) ** 2).sum(-1)
    return PALETTE[PAL_KEYS[int(d.argmin())]]


def to_ascii(img: Image.Image, max_w: int = 72) -> str:
    a = np.array(img.convert("RGBA"))
    h, w = a.shape[:2]
    # downsample by averaging alpha, keep color via nearest
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
                # representative: most common opaque color (median)
                med = np.median(opaque, axis=0).astype(int)
                row.append(classify(med))
        out.append("".join(row))
    return "\n".join(out)


def main():
    sheet = np.array(Image.open("views.png").convert("RGBA"))
    vol, views = views_to_slices(sheet, slices=18, top_nose="down", side_nose="left", order="reading")
    print("vol shape (slices, H, W):", vol.shape[:3])
    for angle in (0, 45, 90, 135, 180, 225, 270, 315):
        frame = render_stack_image(vol, angle, squash=0.75, spacing=1.0, shadow=False, outline=False)
        print(f"\n===== angle {angle} =====")
        print(to_ascii(frame))


if __name__ == "__main__":
    main()
