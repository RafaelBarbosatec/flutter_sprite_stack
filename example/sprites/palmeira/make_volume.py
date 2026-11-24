#!/usr/bin/env python3
"""Palmeira imperial: a tall royal palm with a curved trunk.

Trunk: a slim, slightly curved column with leaf-scar rings.
Crown: eight arching fronds plus a couple of coconut clusters, kept at least
2 px wide so nothing flickers while the diorama turns.

Outputs: slices.png, views.png, check.png, turntable.gif
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from _stack_export import save_all  # noqa: E402

PAL = {
    "trunk_hi": (186, 158, 116),
    "trunk": (146, 118, 82),
    "trunk_sh": (104, 82, 56),
    "trunk_ring": (78, 60, 40),
    "frond_hi": (150, 196, 96),
    "frond": (98, 154, 72),
    "frond_sh": (64, 112, 58),
    "frond_dk": (44, 82, 48),
    "coco": (150, 128, 70),
    "shadow": (30, 46, 32),
}

X = Y = 25
CX = CY = (X - 1) / 2.0
H = 26

vol = np.zeros((H, Y, X, 4), dtype=np.uint8)


def col(name):
    r, g, b = PAL[name]
    return (r, g, b, 255)


def put(x, y, z, name):
    x, y, z = int(round(x)), int(round(y)), int(round(z))
    if 0 <= x < X and 0 <= y < Y and 0 <= z < H:
        vol[z, y, x] = col(name)


# ------------------------------------------------------------------ trunk
TRUNK_TOP = 17
for z in range(1, TRUNK_TOP + 1):
    t = z / TRUNK_TOP
    # gentle S-curve, thicker at the base
    cx = CX + math.sin(t * 2.2) * 1.6
    cy = CY + math.cos(t * 1.7) * 0.9
    r = 0.9 + 1.3 * (1 - t) ** 2
    for y in range(Y):
        for x in range(X):
            if (x - cx) ** 2 + (y - cy) ** 2 > (r + 0.35) ** 2:
                continue
            name = "trunk"
            if x - cx > 0.35:
                name = "trunk_sh"
            elif x - cx < -0.35:
                name = "trunk_hi"
            if z % 3 == 0:
                name = "trunk_ring"
            put(x, y, z, name)
# root flare
for z in (0, 1):
    for y in range(Y):
        for x in range(X):
            if math.hypot(x - CX, y - CY) <= 2.9 - z * 0.6:
                put(x, y, z, "trunk_sh" if (x + y) % 2 else "trunk")

# ----------------------------------------------------------------- crown
TOP = TRUNK_TOP
CROWN_CX = CX + math.sin(2.2) * 1.6
CROWN_CY = CY + math.cos(1.7) * 0.9

# Central bud.
for z in range(TOP, TOP + 3):
    put(CROWN_CX, CROWN_CY, z, "frond_hi")
put(CROWN_CX, CROWN_CY, TOP + 2, "frond")

# Eight arching fronds: rise a little, then droop with the tip.
FRONDS = 8
for i in range(FRONDS):
    angle = i * 2 * math.pi / FRONDS + 0.35
    length = 9.0 if i % 2 == 0 else 7.5
    for step in range(1, int(length) + 1):
        t = step / length
        reach = 1.0 + step * 0.95
        x = CROWN_CX + math.cos(angle) * reach
        y = CROWN_CY + math.sin(angle) * reach
        # arch: up fast, then droop below the crown at the tip
        z = TOP + 1.6 + math.sin(t * 2.4) * 2.6 - (t ** 2.4) * 5.2
        name = "frond"
        if t < 0.3:
            name = "frond_hi"
        elif t > 0.78:
            name = "frond_sh"
        # two-pixel-wide blades: offset perpendicular to the frond
        px, py = -math.sin(angle), math.cos(angle)
        put(x, y, z, name)
        # three-pixel-wide blades keep the crown solid at any angle
        put(x + px, y + py, z, name)
        put(x - px, y - py, z, name)
        if step > 3:
            put(x + px * 2, y + py * 2, z, name)
            put(x - px * 2, y - py * 2, z, name)

# A second, shorter ring of fronds drooping under the crown so the head reads
# as a full palm instead of a starburst.
for i in range(6):
    angle = i * 2 * math.pi / 6 + 0.9
    length = 5.5
    for step in range(1, int(length) + 1):
        t = step / length
        reach = 1.0 + step * 0.9
        x = CROWN_CX + math.cos(angle) * reach
        y = CROWN_CY + math.sin(angle) * reach
        z = TOP - 0.5 - t * 2.4
        px, py = -math.sin(angle), math.cos(angle)
        name = "frond_sh" if t > 0.5 else "frond"
        put(x, y, z, name)
        put(x + px, y + py, z, name)

# Coconut clusters under the crown.
for dx, dy in ((1.4, 1.1), (-1.5, 0.9), (0.6, -1.6), (-0.8, -1.4)):
    for z in range(TOP - 2, TOP):
        put(CROWN_CX + dx, CROWN_CY + dy, z, "coco")

# ------------------------------------------------------- top light baking
HI = {
    "frond": "frond_hi",
    "frond_sh": "frond",
    "frond_dk": "frond_sh",
    "trunk": "trunk_hi",
    "trunk_sh": "trunk",
    "coco": "trunk_hi",
}
lookup = {col(k): col(v) for k, v in HI.items()}
src = vol.copy()
for z in range(H):
    for y in range(Y):
        for x in range(X):
            if src[z, y, x, 3] == 0:
                continue
            above = src[z + 1, y, x, 3] if z + 1 < H else 0
            if above == 0:
                key = tuple(int(v) for v in src[z, y, x])
                if key in lookup:
                    vol[z, y, x] = lookup[key]

if __name__ == "__main__":
    save_all(vol, Path(__file__).resolve().parent, turntable_scale=7)
