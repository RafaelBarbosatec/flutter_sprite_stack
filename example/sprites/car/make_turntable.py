#!/usr/bin/env python3
"""Render a turntable GIF of the carved car stack."""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

SLICER = Path("/home/rafael/.pi/agent/git/github.com/danielwh2/sprite-stacking/skills/sprite-stacking/scripts")
sys.path.insert(0, str(SLICER))
from views_to_slices import views_to_slices, render_stack_image  # noqa: E402


def main() -> None:
    sheet = np.array(Image.open("views.png").convert("RGBA"))
    vol, _ = views_to_slices(sheet, slices=16, top_nose="down", side_nose="left", order="reading")

    scale = 6
    frames = []
    for angle in range(0, 360, 22):  # 16 frames, ~22.5 deg steps
        frame = render_stack_image(vol, angle, squash=0.75, spacing=1.0, shadow=True, outline=True)
        w, h = frame.size
        frame = frame.resize((w * scale, h * scale), Image.NEAREST)
        frames.append(frame)

    # center all frames on a shared canvas so the turntable doesn't jump
    w = max(f.width for f in frames)
    h = max(f.height for f in frames)
    canvas_frames = []
    for f in frames:
        c = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        c.paste(f, ((w - f.width) // 2, (h - f.height) // 2), f)
        canvas_frames.append(c)

    # GIF needs opaque frames; put on a flat background
    bg = (58, 68, 84, 255)
    gif_frames = []
    for f in canvas_frames:
        flat = Image.new("RGBA", (w, h), bg)
        flat.alpha_composite(f)
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
