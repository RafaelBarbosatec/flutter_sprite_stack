#!/usr/bin/env python3
"""Render a turntable GIF of the cottage stack (porch, fence and lawn)."""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

SLICER = Path("/home/rafael/.pi/agent/git/github.com/danielwh2/sprite-stacking/skills/sprite-stacking/scripts")
sys.path.insert(0, str(SLICER))
from views_to_slices import render_stack_image  # noqa: E402

def load_volume(path="slices.png", slices=29):
    strip = np.array(Image.open(path).convert("RGBA"))
    w = strip.shape[1] // slices
    return np.stack([strip[:, i * w:(i + 1) * w] for i in range(slices)])


def main() -> None:
    vol = load_volume()

    scale = 6
    frames = []
    for angle in range(0, 360, 22):
        frame = render_stack_image(vol, angle, squash=0.75, spacing=1.0, shadow=True, outline=True)
        w, h = frame.size
        frames.append(frame.resize((w * scale, h * scale), Image.NEAREST))

    w = max(f.width for f in frames)
    h = max(f.height for f in frames)
    bg = (58, 68, 84, 255)
    gif_frames = []
    for f in frames:
        c = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        c.paste(f, ((w - f.width) // 2, (h - f.height) // 2), f)
        flat = Image.new("RGBA", (w, h), bg)
        flat.alpha_composite(c)
        gif_frames.append(flat.convert("RGB").convert("P", palette=Image.ADAPTIVE))

    out = Path("turntable.gif")
    gif_frames[0].save(
        out,
        save_all=True,
        append_images=gif_frames[1:],
        duration=90,
        loop=0,
        disposal=2,
        optimize=False,
    )
    print(f"wrote {out} ({w}x{h}, {len(gif_frames)} frames)")


if __name__ == "__main__":
    main()
