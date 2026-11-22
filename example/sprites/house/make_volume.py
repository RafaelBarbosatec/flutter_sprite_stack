#!/usr/bin/env python3
"""Model a cottage with porch, picket fence and lawn directly as a voxel volume.

The visual-hull slicer cannot carve a hollow fence ring or a porch (every
silhouette would fill the whole yard), so the volume is built voxel by voxel
and written straight to the slice strip.

Axes: vol[z, y, x]. x runs left->right, y runs back->front (the front of the
house faces +y, i.e. down in the top view), z is up.

Outputs: slices.png, views.png (orthographic projections), check.png,
viewer.html.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

SLICER = Path("/home/rafael/.pi/agent/git/github.com/danielwh2/sprite-stacking/skills/sprite-stacking/scripts")
sys.path.insert(0, str(SLICER))
from views_to_slices import build_html_viewer, build_preview  # noqa: E402

PAL = {
    "grass": (98, 170, 74),
    "grass_d": (80, 148, 62),
    "grass_h": (122, 190, 88),
    "tuft": (66, 128, 56),
    "path": (206, 194, 170),
    "path_d": (178, 166, 146),
    "fence": (248, 245, 235),
    "fence_d": (208, 202, 188),
    "wall": (240, 230, 204),
    "siding": (222, 208, 178),
    "trim": (252, 249, 238),
    "foundation": (140, 138, 146),
    "foundation_d": (116, 114, 124),
    "roof": (176, 82, 52),
    "roof_sh": (138, 60, 40),
    "roof_hi": (212, 118, 76),
    "roof_mid": (192, 96, 62),
    "roof_dk": (122, 52, 38),
    "ridge": (230, 140, 96),
    "door": (172, 64, 56),
    "door_d": (120, 40, 38),
    "knob": (236, 196, 84),
    "glass": (120, 172, 208),
    "glass_h": (200, 228, 248),
    "frame": (96, 70, 48),
    "shutter": (70, 128, 96),
    "shutter_d": (48, 98, 72),
    "deck": (196, 146, 90),
    "deck_d": (160, 112, 66),
    "deck_dk": (122, 84, 52),
    "chimney": (158, 66, 50),
    "chimney_d": (120, 48, 38),
    "cap": (110, 108, 118),
    "bush": (58, 130, 64),
    "bush_h": (84, 160, 78),
    "pink": (232, 104, 150),
    "yellow": (246, 208, 80),
    "white": (250, 250, 250),
}

# Yard
X, Y = 48, 48
H = 29
# House body (inclusive)
HX0, HX1, HY0, HY1 = 10, 37, 6, 27
WALL_Z0, WALL_Z1 = 1, 16
# Porch deck (inclusive)
DX0, DX1, DY0, DY1 = 9, 38, 28, 36
CX0, CX1 = 21, 26  # steps / gate / path centre column (6 wide)

vol = np.zeros((H, Y, X, 4), dtype=np.uint8)


def c(name):
    r, g, b = PAL[name]
    return (r, g, b, 255)


def box(x0, x1, y0, y1, z0, z1, color):
    vol[z0: z1 + 1, y0: y1 + 1, x0: x1 + 1] = c(color)


def put(x, y, z, color):
    if 0 <= x < X and 0 <= y < Y and 0 <= z < H:
        vol[z, y, x] = c(color)


def hash2(x, y, s=0):
    return ((x * 73856093) ^ (y * 19349663) ^ (s * 83492791)) & 0xFFFF


# ---------------------------------------------------------------- lawn
for y in range(Y):
    for x in range(X):
        h = hash2(x // 2, y // 2)
        name = "grass"
        if h % 7 == 0:
            name = "grass_d"
        elif h % 11 == 0:
            name = "grass_h"
        put(x, y, 0, name)

# Raised grass tufts (2x2, 1 high) scattered over the lawn.
for y in range(3, Y - 3, 2):
    for x in range(3, X - 3, 2):
        if hash2(x, y, 5) % 23 == 0:
            box(x, x + 1, y, y + 1, 1, 1, "tuft")

# Flower patches (2x2, 1 high).
FLOWERS = [(4, 10, "pink"), (5, 22, "yellow"), (4, 34, "pink"), (42, 12, "yellow"),
           (41, 26, "pink"), (42, 36, "yellow"), (13, 40, "yellow"), (32, 41, "pink"),
           (18, 3, "pink"), (30, 3, "yellow")]
FLOWERS_CLEAR = []

# Stone path from the gate to the steps.
for y in range(DY1 + 3, Y):
    for x in range(CX0 + 1, CX1):
        put(x, y, 0, "path" if ((x + y // 2) % 2 == 0) else "path_d")

# ---------------------------------------------------------------- house
box(HX0, HX1, HY0, HY1, 1, 2, "foundation")
box(HX0, HX1, HY0, HY1, 3, WALL_Z1, "wall")
for z in range(3, WALL_Z1 + 1):
    if z % 2 == 0:  # clapboard siding lines
        box(HX0, HX1, HY0, HY1, z, z, "siding")
# darker band at the foot of the foundation
for x in range(HX0, HX1 + 1):
    for y in range(HY0, HY1 + 1):
        if (x + y) % 4 == 0:
            put(x, y, 1, "foundation_d")

# corner boards (2x2)
for cx in (HX0, HX1 - 1):
    for cy in (HY0, HY1 - 1):
        box(cx, cx + 1, cy, cy + 1, 3, WALL_Z1, "trim")


def window(face, a0, z0, h=6):
    """5 wide frame (1px) + 3 wide glass + 2px shutters either side, 2px deep.

    face: 'front' (y=HY1), 'back' (y=HY0), 'left' (x=HX0), 'right' (x=HX1).
    a0: first coordinate along the wall of the 9-wide group (shutter included).
    """
    cells = []
    for i in range(9):
        for k in range(h):
            if i in (0, 1, 7, 8):
                col = "shutter" if i in (0, 8) else "shutter_d"
                col = "shutter" if i in (0, 7) else "shutter_d"
            elif i in (2, 6) or k in (0, h - 1):
                col = "frame"
            else:
                col = "glass_h" if (i == 3 and k == h - 2) else "glass"
            cells.append((i, k, col))
    for i, k, col in cells:
        for d in range(2):
            if face == "front":
                put(a0 + i, HY1 - d, z0 + k, col)
            elif face == "back":
                put(a0 + i, HY0 + d, z0 + k, col)
            elif face == "left":
                put(HX0 + d, a0 + i, z0 + k, col)
            else:
                put(HX1 - d, a0 + i, z0 + k, col)


window("front", 12, 11)
window("front", 27, 11)
window("back", 12, 9)
window("back", 27, 9)
window("left", 9, 8)
window("left", 19, 8) if False else None
window("right", 9, 8)
# long walls get a second window further along
window("left", 17, 8) if False else None

# front door under the porch (4 wide, 6 tall)
for i, x in enumerate(range(22, 26)):
    for z in range(3, 9):
        for d in range(2):
            col = "door_d" if i in (0, 3) or z == 8 else "door"
            put(x, HY1 - d, z, col)
put(24, HY1, 5, "knob")
put(24, HY1 - 1, 5, "knob")

# ---------------------------------------------------------------- roof
RX0, RX1, RY0, RY1 = HX0 - 1, HX1 + 1, HY0 - 1, HY1 + 1  # overhang 1
ROOF_Z0 = WALL_Z1 + 1
INSETS = [0, 2, 3, 5, 6, 8, 9, 11]
for k, ins in enumerate(INSETS):
    z = ROOF_Z0 + k
    x0, x1, y0, y1 = RX0 + ins, RX1 - ins, RY0 + ins, RY1 - ins
    if x0 > x1 or y0 > y1:
        break
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            # which edge is nearest? decides the lit side
            dl, dr, dt, db = x - x0, x1 - x, y - y0, y1 - y
            m = min(dl, dr, dt, db)
            if m == dl and dl <= dt and dl <= db:
                base = "roof_sh"      # west slope, in shadow
            elif m == dr:
                base = "roof_hi"      # east slope, lit
            elif m == dt:
                base = "roof_dk" if k % 2 else "roof_sh"   # north slope
            else:
                base = "roof_mid" if k % 2 == 0 else "roof"  # south slope
            if k == 0 and m == 0:
                base = "trim"           # fascia board
            put(x, y, z, base)
# ridge cap
rz = ROOF_Z0 + len(INSETS) - 1
ridge = INSETS[-1]
box(RX0 + ridge, RX1 - ridge, RY0 + ridge, RY1 - ridge, rz, rz, "ridge")

# chimney
box(30, 33, 10, 13, ROOF_Z0 + 1, ROOF_Z0 + 10, "chimney")
for z in range(ROOF_Z0 + 2, ROOF_Z0 + 10, 2):
    box(30, 33, 10, 13, z, z, "chimney_d")
box(30, 33, 10, 13, ROOF_Z0 + 10, ROOF_Z0 + 10, "cap")

# ---------------------------------------------------------------- porch
# deck: 2 boards thick, plank lines on top
box(DX0, DX1, DY0, DY1, 1, 1, "deck_dk")
box(DX0, DX1, DY0, DY1, 2, 2, "deck")
for y in range(DY0, DY1 + 1):
    if (y - DY0) % 3 == 2:
        box(DX0, DX1, y, y, 2, 2, "deck_d")

# steps (1 high) down to the path
box(CX0, CX1, DY1 + 1, DY1 + 2, 1, 1, "deck_d")

# railing: left, right and front (gap for the steps)
RAIL_Z0, RAIL_Z1 = 3, 5
def railing_cell(x, y):
    on_left = x in (DX0, DX0 + 1)
    on_right = x in (DX1 - 1, DX1)
    on_front = y in (DY1 - 1, DY1) and not (CX0 - 1 <= x <= CX1 + 1)
    return on_left or on_right or on_front

for y in range(DY0, DY1 + 1):
    for x in range(DX0, DX1 + 1):
        if not railing_cell(x, y):
            continue
        along = x if y >= DY1 - 1 else y
        # balusters: 2 on, 1 gap, top rail continuous
        if (along % 3) != 2:
            box(x, x, y, y, RAIL_Z0, RAIL_Z0 + 1, "fence")
        put(x, y, RAIL_Z1, "fence_d" if (x + y) % 2 else "fence")

# posts (2x2) hold up the porch roof
for px, py in [(DX0, DY1 - 1), (DX1 - 1, DY1 - 1), (CX0 - 3, DY1 - 1), (CX1 + 2, DY1 - 1)]:
    box(px, px + 1, py, py + 1, 3, 8, "trim")
    box(px, px + 1, py, py, 3, 8, "fence_d") if False else None

# porch roof: lean-to stepping up to the wall
PRZ = 9
box(DX0 - 1, DX1 + 1, DY0, DY1 - 1, PRZ, PRZ, "trim")
box(DX0 - 1, DX1 + 1, DY0, DY1 - 1, PRZ + 1, PRZ + 1, "roof_mid")
box(DX0, DX1, DY0, DY1 - 2, PRZ + 2, PRZ + 2, "roof")
box(DX0 + 2, DX1 - 2, DY0, DY1 - 4, PRZ + 3, PRZ + 3, "roof_hi")

# ---------------------------------------------------------------- fence
FZ0, FZ1 = 1, 5


def fence_cell(x, y):
    ring = x < 2 or x >= X - 2 or y < 2 or y >= Y - 2
    if not ring:
        return False
    gate = y >= Y - 2 and CX0 <= x <= CX1
    return not gate


for y in range(Y):
    for x in range(X):
        if not fence_cell(x, y):
            continue
        along = x if (y < 2 or y >= Y - 2) else y
        # pickets: 2 wide, 1 gap -> but corners always solid
        corner = (x < 2 or x >= X - 2) and (y < 2 or y >= Y - 2)
        if corner:
            box(x, x, y, y, FZ0, FZ1 + 1, "fence")
            continue
        picket = (along % 3) != 2
        if picket:
            box(x, x, y, y, FZ0, FZ1, "fence")
            if (along % 3) == 0:
                put(x, y, FZ1, "fence_d")
        # rails
        put(x, y, 2, "fence_d")
        put(x, y, 4, "fence_d")

# gate posts
for gx in (CX0 - 2, CX1 + 1):
    box(gx, gx + 1, Y - 2, Y - 1, 1, 7, "fence")
    box(gx, gx + 1, Y - 2, Y - 1, 7, 7, "deck")

# ---------------------------------------------------------------- bushes
def bush(cx, cy, r=3):
    cz = 1.6
    for z in range(1, 6):
        for y in range(cy - r, cy + r + 1):
            for x in range(cx - r, cx + r + 1):
                d = ((x - cx) ** 2 + (y - cy) ** 2 + ((z - cz) * 1.3) ** 2) ** 0.5
                if d <= r + 0.3:
                    put(x, y, z, "bush_h" if (z >= 3 or (x + y) % 5 == 0) else "bush")


bush(14, 40, 3)
bush(33, 40, 3)
bush(5, 8, 2)
bush(42, 8, 2)
# small blossoms on the bushes
for (bx, by, col) in [(13, 39, "pink"), (15, 41, "pink"), (33, 39, "yellow"), (34, 41, "yellow")]:
    put(bx, by, 4, col)
    put(bx + 1, by, 4, col)

for fx, fy, col in FLOWERS:
    box(fx, fx + 1, fy, fy + 1, 1, 1, col)
    put(fx, fy, 2, "white")
    put(fx + 1, fy + 1, 2, "white") if False else None


# ---------------------------------------------------------------- views
def top_view(v):
    out = np.zeros((Y, X, 4), np.uint8)
    for z in range(H):
        m = v[z, ..., 3] > 0
        out[m] = v[z][m]
    return out


def front_view(v):
    out = np.zeros((H, X, 4), np.uint8)
    for y in range(Y):  # back to front so the nearest wins
        m = v[:, y, :, 3] > 0
        out[m] = v[:, y, :][m]
    return out[::-1]


def back_view(v):
    out = np.zeros((H, X, 4), np.uint8)
    for y in range(Y - 1, -1, -1):
        m = v[:, y, :, 3] > 0
        out[m] = v[:, y, :][m]
    return out[::-1][:, ::-1]


def side_view(v):
    out = np.zeros((H, Y, 4), np.uint8)
    for x in range(X):
        m = v[:, :, x, 3] > 0
        out[m] = v[:, :, x][m]
    return out[::-1][:, ::-1]  # front pointing left


def compose_sheet(views, out_path, scale=8, gap=6):
    up = [Image.fromarray(v).resize((v.shape[1] * scale, v.shape[0] * scale), Image.NEAREST) for v in views]
    gap_px = gap * scale
    h = max(v.height for v in up)
    w = sum(v.width for v in up) + gap_px * (len(up) - 1)
    sheet = Image.new("RGBA", (w, h), (255, 255, 255, 255))
    x = 0
    for v in up:
        sheet.paste(v, (x, (h - v.height) // 2), v)
        x += v.width + gap_px
    sheet.convert("RGB").save(out_path)


def main() -> None:
    out = Path(__file__).resolve().parent
    strip = np.concatenate(list(vol), axis=1)
    Image.fromarray(strip).save(out / "slices.png")
    print(f"{H} slices of {X} x {Y} px -> {out / 'slices.png'}")

    views = [top_view(vol), side_view(vol), front_view(vol), back_view(vol)]
    compose_sheet(views, out / "views.png")
    build_preview(vol, views, out / "check.png")
    build_html_viewer(vol, views, out / "viewer.html", title="slices")


if __name__ == "__main__":
    main()
