#!/usr/bin/env python3
"""Render the house stack at several angles and print ASCII previews."""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

SLICER = Path("/home/rafael/.pi/agent/git/github.com/danielwh2/sprite-stacking/skills/sprite-stacking/scripts")
sys.path.insert(0, str(SLICER))
from views_to_slices import render_stack_image  # noqa: E402

PALETTE = {
    (44, 32, 26): "#", (238, 228, 202): "w", (198, 182, 150): "v",
    (252, 246, 228): "W", (176, 82, 52): "R", (138, 60, 40): "r",
    (212, 118, 76): "H", (120, 52, 36): "k", (122, 70, 40): "D",
    (82, 46, 26): "d", (210, 176, 80): "n", (120, 172, 208): "g",
    (200, 228, 248): "G", (90, 66, 44): "f", (158, 66, 50): "C",
    (120, 48, 38): "c", (90, 40, 34): "t", (140, 138, 146): "s",
}
K = list(PALETTE)
A = np.array(K).astype(int)


def classify(px):
    r, g, b, a = px
    if a < 128:
        return " "
    d = ((A - (r, g, b)) ** 2).sum(-1)
    return PALETTE[K[int(d.argmin())]]


def to_ascii(img: Image.Image, max_w: int = 70) -> str:
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

def load_volume(path="slices.png", slices=29):
    strip = np.array(Image.open(path).convert("RGBA"))
    w = strip.shape[1] // slices
    return np.stack([strip[:, i * w:(i + 1) * w] for i in range(slices)])


def main():
    vol = load_volume()
    print("vol shape (slices, H, W):", vol.shape[:3])
    for angle in (0, 45, 90, 135, 180, 225, 270, 315):
        frame = render_stack_image(vol, angle, squash=0.75, spacing=1.0, shadow=False, outline=False)
        print(f"\n===== angle {angle} =====")
        print(to_ascii(frame))


if __name__ == "__main__":
    main()
