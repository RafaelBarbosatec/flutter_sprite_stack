#!/usr/bin/env python3
"""Model a red Formula 1 car (driver helmet, halo, open wings) as a voxel volume.

The visual-hull slicer fills every cavity hidden from the four silhouettes, so
an open cockpit with a driver, an open halo and a two-element rear wing cannot
be carved from views. The volume is built voxel by voxel instead and written
straight to the slice strip.

Axes: vol[z, y, x]. x runs left->right, y runs back->front (the nose points to
+y, i.e. DOWN in the top view), z is up. ``s`` is the distance from the nose
tip along the car (y = L - 1 - s).

Outputs: slices.png, views.png (orthographic projections), check.png,
viewer.html.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

SLICER = Path("/home/rafael/.pi/agent/git/github.com/danielwh2/sprite-stacking/skills/sprite-stacking/scripts")
sys.path.insert(0, str(SLICER))
from views_to_slices import build_html_viewer, build_preview  # noqa: E402

PAL = {
    "body": (208, 32, 40),
    "body_sh": (140, 20, 28),
    "body_hi": (240, 70, 60),
    "white": (244, 246, 250),
    "yellow": (250, 212, 60),
    "wing": (30, 32, 44),
    "wing_hi": (70, 76, 100),
    "tire": (22, 22, 30),
    "tire_hi": (62, 62, 76),
    "hub": (170, 174, 190),
    "rim": (54, 56, 70),
    "soft": (246, 206, 52),     # soft-compound sidewall ring
    "cockpit": (16, 20, 30),
    "seat": (38, 42, 58),
    "halo": (150, 158, 176),
    "halo_hi": (232, 236, 244),
    "metal": (92, 96, 112),
    "floor": (48, 50, 62),
    "floor_hi": (86, 90, 106),
    "suit": (36, 48, 112),
    "helmet": (252, 214, 52),
    "helmet_sh": (214, 168, 30),
    "visor": (24, 30, 52),
    "visor_hi": (150, 190, 226),
    "helmet_blue": (46, 96, 206),
}

X, L, H = 38, 72, 15
CX = (X - 1) / 2  # 18.5

vol = np.zeros((H, L, X, 4), dtype=np.uint8)


def col(name):
    r, g, b = PAL[name]
    return (r, g, b, 255)


def put(x, s, z, name, mirror=False):
    for xx in ((x, X - 1 - x) if mirror else (x,)):
        if 0 <= xx < X and 0 <= s < L and 0 <= z < H:
            vol[z, L - 1 - s, xx] = col(name)


def box(x0, x1, s0, s1, z0, z1, name, mirror=False):
    for z in range(z0, z1 + 1):
        for s in range(s0, s1 + 1):
            for x in range(x0, x1 + 1):
                put(x, s, z, name, mirror)


def clear(x0, x1, s0, s1, z0, z1):
    for z in range(z0, z1 + 1):
        for s in range(s0, s1 + 1):
            for x in range(x0, x1 + 1):
                vol[z, L - 1 - s, x] = 0


# ------------------------------------------------------------------ floor
box(7, 30, 30, 60, 1, 2, "floor")
# diffuser: fins every 4 px on the rear of the floor
box(9, 28, 55, 60, 3, 4, "floor")
for x in range(9, 29):
    if (x // 2) % 2 == 0:
        box(x, x, 55, 60, 4, 4, "floor_hi")

# ------------------------------------------------------------------ nose
for s in range(8, 29):
    hw = 3.5 + (s - 8) * 0.2
    zb = 2 + (s - 8) // 20
    zt = 4 + round((s - 8) * 0.25)
    for x in range(X):
        if abs(x - CX) <= hw:
            for z in range(zb, zt + 1):
                put(x, s, z, "body")

# ------------------------------------------------------------------ sidepods
for s in range(27, 49):
    for x in range(X):
        v = ((s - 38) / 10.5) ** 2 + ((x - CX) / 13.5) ** 2
        if v <= 1:
            top = 7 if v < 0.8 else 6
            for z in range(2, top + 1):
                put(x, s, z, "body")
# air intake mouths at the front of the sidepods
box(7, 10, 28, 29, 3, 5, "cockpit", mirror=True)
box(8, 9, 28, 28, 3, 5, "body_sh", mirror=True) if False else None

# ------------------------------------------------------------------ cockpit tub + engine cover
box(11, 26, 28, 38, 3, 9, "body")
for s in range(38, 58):
    hw = 9.5 - (s - 38) * 0.25
    zt = 11 if s <= 44 else round(11 - (s - 44) * 3 / 12)
    for x in range(X):
        if abs(x - CX) <= hw:
            for z in range(3, zt + 1):
                put(x, s, z, "body")
# tail + gearbox
box(15, 22, 56, 61, 4, 7, "body_sh")
box(12, 25, 50, 58, 3, 6, "body_sh")

# airbox / shark fin
box(17, 20, 41, 49, 12, 14, "body")
box(17, 20, 41, 42, 12, 13, "cockpit")      # intake mouth
box(18, 19, 43, 49, 14, 14, "white")        # centre stripe on the fin

# ------------------------------------------------------------------ cockpit + driver
clear(14, 23, 29, 37, 7, 9)                 # open cockpit
box(14, 23, 29, 37, 6, 6, "cockpit")        # floor
box(14, 23, 29, 37, 7, 7, "seat")
box(14, 23, 36, 37, 7, 9, "seat")           # seat back
box(15, 22, 34, 36, 7, 8, "suit")           # shoulders
box(16, 21, 29, 30, 8, 8, "metal")          # steering wheel
box(17, 20, 29, 29, 9, 9, "yellow")

# helmet: sphere r=3.3 centred on the driver's head
HC_S, HC_Z, HR = 32.5, 9.6, 3.6
for z in range(H):
    for s in range(L):
        for x in range(X):
            d = math.sqrt((x - CX) ** 2 + (s - HC_S) ** 2 + ((z - HC_Z) * 1.0) ** 2)
            if d > HR:
                continue
            name = "helmet"
            # visor band on the front half
            if s < HC_S - 0.5 and HC_Z - 1.6 <= z <= HC_Z + 0.7:
                name = "visor_hi" if (z >= HC_Z + 0.2 and abs(x - CX) > 1.2) else "visor"
            # racing stripe over the crown
            elif abs(x - CX) <= 0.6 and z >= HC_Z + 0.5:
                name = "helmet_blue"
            elif z <= HC_Z - 1.5:
                name = "helmet_sh"
            put(x, s, z, name)

# halo: front pillar, front bar and two side arms, all outside the helmet
box(18, 19, 28, 28, 9, 11, "halo")
box(13, 24, 27, 28, 12, 13, "halo")
box(13, 14, 28, 36, 12, 13, "halo", mirror=True)
box(13, 14, 35, 36, 9, 11, "halo", mirror=True)
# mirrors
box(9, 11, 30, 31, 9, 10, "body", mirror=True)
box(9, 9, 30, 31, 10, 10, "white", mirror=True)

# ------------------------------------------------------------------ wheels
def wheel(x0, x1, cs, cz, r, outer_left):
    xs = range(x0, x1 + 1)
    for z in range(H):
        for s in range(L):
            d = math.hypot(s - cs, z - cz)
            if d > r:
                continue
            for x in xs:
                depth = (x - x0) if outer_left else (x1 - x)  # 0 = outermost
                name = "tire"
                if depth <= 1:
                    if d <= 1.2:
                        name = "rim"
                    elif d <= 2.6:
                        name = "hub"
                    elif d <= 3.6:
                        name = "rim"
                    elif 4.3 <= d <= 5.6:
                        name = "soft"
                put(x, s, z, name)


WR = 6.4
wheel(3, 10, 17, 6, WR, True)
wheel(X - 1 - 10, X - 1 - 3, 17, 6, WR, False)
wheel(0, 8, 55, 6, WR, True)
wheel(X - 1 - 8, X - 1, 55, 6, WR, False)

# suspension arms
box(11, 12, 15, 16, 6, 7, "metal", mirror=True)
box(11, 12, 19, 20, 6, 7, "metal", mirror=True)
box(9, 11, 53, 54, 6, 7, "metal", mirror=True)
box(9, 11, 57, 58, 6, 7, "metal", mirror=True)

# ------------------------------------------------------------------ front wing
box(0, 37, 0, 7, 1, 2, "wing")
box(0, 37, 0, 1, 1, 2, "wing_hi")
box(5, 32, 2, 5, 3, 4, "body")               # red flap
box(17, 20, 2, 5, 3, 4, "white")
box(0, 1, 0, 8, 1, 5, "body", mirror=True)   # endplates
box(0, 0, 3, 5, 3, 4, "white", mirror=True)

# ------------------------------------------------------------------ rear wing
box(2, 35, 62, 71, 7, 8, "wing")             # lower plane
box(2, 35, 62, 63, 7, 8, "wing_hi")
box(2, 35, 64, 70, 13, 14, "wing")           # upper plane / DRS flap
box(2, 35, 69, 70, 14, 14, "yellow")
box(17, 20, 64, 67, 9, 12, "wing")           # pylon
box(15, 22, 60, 63, 5, 7, "wing")            # tail connects to the plane
box(0, 2, 62, 71, 5, 14, "body", mirror=True)  # endplates
box(0, 0, 65, 69, 9, 12, "white", mirror=True)
# beam wing
box(8, 29, 57, 62, 5, 6, "wing")
# exhaust
box(17, 20, 60, 62, 5, 6, "metal")
box(18, 19, 61, 62, 5, 6, "cockpit")

# ------------------------------------------------------------------ livery
ZT = lambda s: max(z for z in range(H) if vol[z, L - 1 - s, 18, 3] > 0)  # noqa: E731

# racing stripe down the engine cover and onto the cockpit surround
for s in range(38, 58):
    if vol[:, L - 1 - s, 18, 3].any():
        z = ZT(s)
        if vol[z, L - 1 - s, 18, 1] == col("body")[1]:
            for xx in (18, 19):
                vol[z, L - 1 - s, xx] = col("white")
# car number "1" on the nose
GLYPH = [".X.", "XX.", ".X.", ".X.", "XXX"]
for r, row in enumerate(GLYPH):
    s = 17 - r
    for c, ch in enumerate(row):
        if ch == "X":
            x = 17 + c
            z = ZT(s)
            vol[z, L - 1 - s, x] = col("white")
# yellow sponsor stripes across the sidepods
for s in (36, 37):
    for x in list(range(7, 12)) + list(range(26, 31)):
        if vol[7, L - 1 - s, x, 3] > 0:
            vol[7, L - 1 - s, x] = col("yellow")

# ------------------------------------------------------------------ top lighting
# Every exposed upward face gets its lighter shade, so each slice reads as 3D.
HI = {"body": "body_hi", "wing": "wing_hi", "tire": "tire_hi", "floor": "floor_hi",
      "halo": "halo_hi", "helmet": "helmet"}
lookup = {col(k): col(v) for k, v in HI.items()}
src = vol.copy()
for z in range(H):
    for y in range(L):
        for x in range(X):
            if src[z, y, x, 3] == 0:
                continue
            above = src[z + 1, y, x, 3] if z + 1 < H else 0
            if above == 0:
                key = tuple(int(v) for v in src[z, y, x])
                if key in lookup:
                    vol[z, y, x] = lookup[key]


# ------------------------------------------------------------------ views
def top_view(v):
    out = np.zeros((L, X, 4), np.uint8)
    for z in range(H):
        m = v[z, ..., 3] > 0
        out[m] = v[z][m]
    return out


def side_view(v):
    out = np.zeros((H, L, 4), np.uint8)
    for x in range(X):
        m = v[:, :, x, 3] > 0
        out[m] = v[:, :, x][m]
    return out[::-1][:, ::-1]  # nose pointing left


def front_view(v):
    out = np.zeros((H, X, 4), np.uint8)
    for y in range(L):
        m = v[:, y, :, 3] > 0
        out[m] = v[:, y, :][m]
    return out[::-1]


def back_view(v):
    out = np.zeros((H, X, 4), np.uint8)
    for y in range(L - 1, -1, -1):
        m = v[:, y, :, 3] > 0
        out[m] = v[:, y, :][m]
    return out[::-1][:, ::-1]


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
    Image.fromarray(np.concatenate(list(vol), axis=1)).save(out / "slices.png")
    print(f"{H} slices of {X} x {L} px")
    views = [top_view(vol), side_view(vol), front_view(vol), back_view(vol)]
    compose_sheet(views, out / "views.png")
    build_preview(vol, views, out / "check.png")
    build_html_viewer(vol, views, out / "viewer.html", title="slices")


if __name__ == "__main__":
    main()
