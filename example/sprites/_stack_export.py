"""Shared export helpers for the voxel-model scripts in this folder.

Every model script builds `vol[z, y, x]` (x right, y back->front, z up) and then
calls `save_all(vol, out_dir)` to write:

    slices.png      the slice strip the Flutter package renders
    views.png       TOP / SIDE / FRONT / BACK proofs, 8x
    check.png       the slicer's turntable + exploded proof sheet
    turntable.gif   16-frame spin, 6x
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

SLICER = Path("/home/rafael/.pi/agent/git/github.com/danielwh2/sprite-stacking/skills/sprite-stacking/scripts")
if str(SLICER) not in sys.path:
    sys.path.insert(0, str(SLICER))

from views_to_slices import build_preview, render_stack_image  # noqa: E402


def top_view(v):
    h, y, x = v.shape[:3]
    out = np.zeros((y, x, 4), np.uint8)
    for z in range(h):
        m = v[z, ..., 3] > 0
        out[m] = v[z][m]
    return out


def side_view(v):
    h, y, x = v.shape[:3]
    out = np.zeros((h, y, 4), np.uint8)
    for i in range(x):
        m = v[:, :, i, 3] > 0
        out[m] = v[:, :, i][m]
    return out[::-1][:, ::-1]


def front_view(v):
    h, y, x = v.shape[:3]
    out = np.zeros((h, x, 4), np.uint8)
    for j in range(y):
        m = v[:, j, :, 3] > 0
        out[m] = v[:, j, :][m]
    return out[::-1]


def back_view(v):
    h, y, x = v.shape[:3]
    out = np.zeros((h, x, 4), np.uint8)
    for j in range(y - 1, -1, -1):
        m = v[:, j, :, 3] > 0
        out[m] = v[:, j, :][m]
    return out[::-1][:, ::-1]


def views_of(v):
    return [top_view(v), side_view(v), front_view(v), back_view(v)]


def compose_sheet(views, out_path, scale=8, gap=6):
    up = [
        Image.fromarray(v).resize((v.shape[1] * scale, v.shape[0] * scale), Image.NEAREST)
        for v in views
    ]
    gap_px = gap * scale
    height = max(v.height for v in up)
    width = sum(v.width for v in up) + gap_px * (len(up) - 1)
    sheet = Image.new("RGBA", (width, height), (255, 255, 255, 255))
    x = 0
    for v in up:
        sheet.paste(v, (x, (height - v.height) // 2), v)
        x += v.width + gap_px
    sheet.convert("RGB").save(out_path)


def render_turntable(vol, out_path, scale=6, bg=(22, 44, 74)):
    frames = []
    for angle in range(0, 360, 22):
        frame = render_stack_image(vol, angle, squash=0.75, spacing=1.0)
        frames.append(frame.resize((frame.width * scale, frame.height * scale), Image.NEAREST))
    width = max(f.width for f in frames)
    height = max(f.height for f in frames)
    gif_frames = []
    for f in frames:
        canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        canvas.paste(f, ((width - f.width) // 2, (height - f.height) // 2), f)
        flat = Image.new("RGBA", (width, height), (*bg, 255))
        flat.alpha_composite(canvas)
        gif_frames.append(flat.convert("RGB").convert("P", palette=Image.ADAPTIVE))
    gif_frames[0].save(
        out_path,
        save_all=True,
        append_images=gif_frames[1:],
        duration=90,
        loop=0,
        disposal=2,
        optimize=False,
    )


def save_all(vol, out_dir, turntable_scale=6, bg=(22, 44, 74)):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    h, y, x = vol.shape[:3]
    Image.fromarray(np.concatenate(list(vol), axis=1)).save(out / "slices.png")
    print(f"{Path(out_dir).name}: {h} slices of {x} x {y} px")
    views = views_of(vol)
    compose_sheet(views, out / "views.png")
    build_preview(vol, views, out / "check.png")
    render_turntable(vol, out / "turntable.gif", scale=turntable_scale, bg=bg)
