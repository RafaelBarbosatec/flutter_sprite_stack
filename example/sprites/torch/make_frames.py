#!/usr/bin/env python3
"""Generate an 8-frame torch atlas for the animation example.

The atlas is a vertical stack of frames, each one a horizontal strip of
cross-sections (ground slice first, left to right):

    frame 0: [z0][z1]...[z31]
    frame 1: [z0][z1]...[z31]
    ...

Anatomy (bottom to top):

    z0-13   wooden handle with two hemp wraps
    z14-18  iron cup: band, neck and a flared rim with rivets
    z18-19  glowing pitch / embers inside the cup
    z19-28  teardrop flame (white-hot core -> yellow -> orange -> red edge)
    z24-31  sparks that drift up and fade (headroom above the flame)

Every motion term is a whole harmonic of the frame phase, so the loop is
seamless: frame 7 flows straight back into frame 0. All frames share the same
canvas and the same centre pivot, as the renderer requires.

Output: frames.png (32 slices x 20 px, 8 frames x 20 px).
"""
from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image

SIZE = 20
SLICES = 32
FRAMES = 8
OUT = Path(__file__).with_name("frames.png")
C = SIZE / 2

Color = tuple[int, int, int]

# Wood, dark -> light.
WOOD: list[Color] = [(52, 32, 22), (80, 51, 33), (110, 72, 44), (142, 98, 60)]
HEMP: list[Color] = [(112, 90, 56), (150, 122, 76), (186, 156, 100)]
# Iron, dark -> light.
IRON: list[Color] = [(34, 38, 50), (54, 60, 76), (84, 92, 110), (128, 136, 152)]
RIVET: Color = (170, 176, 188)
# Fire heat ramp, cold -> hot.
FIRE: list[Color] = [
    (150, 36, 32),
    (214, 74, 30),
    (244, 122, 34),
    (255, 176, 52),
    (255, 220, 98),
    (255, 246, 196),
]
PITCH: list[Color] = [(40, 18, 16), (92, 28, 20), (170, 50, 24), (236, 104, 30)]

Pixel = tuple[int, int, Color, int]


def clamp_idx(value: float, count: int) -> int:
    return max(0, min(count - 1, int(value)))


def disc(cx: float, cy: float, radius: float):
    r2 = radius * radius
    lo = max(0, int(cy - radius) - 1)
    hi = min(SIZE, int(cy + radius) + 2)
    for y in range(lo, hi):
        for x in range(SIZE):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            if dx * dx + dy * dy <= r2:
                yield x, y, dx, dy


def lit(dx: float, dy: float, radius: float) -> float:
    """Cylinder-ish light: 1 towards the upper-left, 0 towards the lower-right."""
    nx, ny = dx / radius, dy / radius
    return max(0.0, min(1.0, 0.5 - 0.5 * (nx * 0.75 + ny * 0.55)))


def warm(color: Color, amount: float) -> Color:
    """Tint a colour towards firelight."""
    r, g, b = color
    return (
        min(255, int(r + (255 - r) * amount * 0.9)),
        min(255, int(g + (150 - g) * amount * 0.55)),
        min(255, int(b + (60 - b) * amount * 0.2)),
    )


def flame_light(frame: int) -> float:
    phi = 2 * math.pi * frame / FRAMES
    return 0.85 + 0.15 * math.sin(phi * 2 + 0.7) + 0.08 * math.sin(phi * 3)


# --- Handle -----------------------------------------------------------------

def handle_slice(z: int, frame: int) -> list[Pixel]:
    # Tapered stake: pointed at the ground, slightly fatter under the cup.
    radius = 1.5 + 0.35 * min(z, 4) + 0.04 * max(0, z - 4)
    rng = random.Random(7000 + z * 31)
    glow = max(0.0, (z - 6) / 8) * 0.26 * flame_light(frame)
    wrapped = z in (4, 5, 9, 10)
    pixels: list[Pixel] = []
    for x, y, dx, dy in disc(C, C, radius):
        shade = lit(dx, dy, radius)
        if wrapped:
            # Diagonal rope: the stripe shifts with z so it reads as a spiral.
            stripe = (x + y + z) % 3
            color = HEMP[clamp_idx(shade * 2.4, 3)]
            if stripe == 0:
                color = HEMP[0]
        else:
            color = WOOD[clamp_idx(shade * 4, 4)]
            grain = rng.random()
            if grain < 0.14:
                color = WOOD[max(0, WOOD.index(color) - 1)]
            elif grain > 0.93:
                color = WOOD[min(3, WOOD.index(color) + 1)]
        # Firelight catches the right/top side of the upper handle.
        if glow > 0 and dx > -0.3:
            color = warm(color, glow)
        pixels.append((x, y, color, 255))
    return pixels


# --- Iron cup ---------------------------------------------------------------

def cup_slice(z: int, frame: int) -> list[Pixel]:
    radii = {14: 3.5, 15: 2.8, 16: 3.5, 17: 4.3, 18: 4.9}
    radius = radii[z]
    light = flame_light(frame)
    rng = random.Random(8300 + frame * 7 + z)
    pixels: list[Pixel] = []
    for x, y, dx, dy in disc(C, C, radius):
        shade = lit(dx, dy, radius)
        color = IRON[clamp_idx(shade * 4, 4)]
        d = math.hypot(dx, dy)
        if z == 14 and (x + y) % 4 == 0 and d > radius - 1.4:
            color = RIVET
        if z == 18:
            if d <= radius - 1.2:
                # Inside of the cup: glowing pitch.
                n = rng.random() * light
                color = PITCH[clamp_idx(1 + n * 3, 4)]
            else:
                color = IRON[clamp_idx(shade * 4 + 1, 4)]
        elif z >= 16:
            # The flare reflects the flame on its upper edge.
            color = warm(color, 0.12 * (z - 15) * light * (1 - shade))
        pixels.append((x, y, color, 255))
    return pixels


def coal_slice(frame: int) -> list[Pixel]:
    rng = random.Random(9100 + frame * 13)
    light = flame_light(frame)
    pixels: list[Pixel] = []
    for x, y, dx, dy in disc(C, C, 3.5):
        d = math.hypot(dx, dy) / 3.5
        heat = (1 - d) * 0.8 * light + rng.random() * 0.35
        color = FIRE[clamp_idx(heat * 4, 4)]
        pixels.append((x, y, color, 255))
    return pixels


# --- Flame ------------------------------------------------------------------

FLAME_BASE = 20
FLAME_TOP = 28


def flame_slice(z: int, frame: int) -> list[Pixel]:
    phi = 2 * math.pi * frame / FRAMES
    height = 8.6 + 1.0 * math.sin(phi + 0.4) + 0.6 * math.sin(2 * phi + 1.3)
    t = (z - FLAME_BASE) / height
    if t >= 1.0:
        return []
    rng = random.Random(4000 + frame * 211 + z * 17)

    breathe = 1 + 0.10 * math.sin(2 * phi + z * 0.9) + 0.06 * math.sin(3 * phi)
    radius = (4.1 * (1 - t ** 1.7) ** 0.8 + 0.5 * (1 - t)) * breathe
    # The base hugs the cup; the sway grows towards the tip and lags behind.
    sway = 1.9 * t ** 1.25
    lag = 1.5 * t
    cx = C + sway * math.sin(phi - lag) + 0.35 * t * math.sin(3 * phi + z)
    cy = C + sway * 0.8 * math.cos(phi - lag) + 0.3 * t * math.cos(2 * phi + z)

    shapes = [(cx, cy, radius)]
    # A secondary lick that whips round the main body mid-flame.
    if 0.2 < t < 0.75:
        a = 2 * phi + 1.9 + t * 3
        lick_r = 1.5 * (1 - t) + 0.4
        shapes.append(
            (cx + math.cos(a) * radius * 0.75, cy + math.sin(a) * radius * 0.75, lick_r)
        )

    seen: dict[tuple[int, int], Color] = {}
    for sx, sy, sr in shapes:
        for x, y, dx, dy in disc(sx, sy, sr):
            u = math.hypot(dx, dy) / sr
            if u > 0.8 and rng.random() < 0.3:
                continue  # ragged rim
            heat = (1 - u * 0.95) * (1 - t * 0.55) + (rng.random() - 0.5) * 0.12
            # Hot bottom, cooler tip.
            heat += 0.12 * (1 - t) - 0.1 * t
            color = FIRE[clamp_idx(heat * 6.2, 6)]
            previous = seen.get((x, y))
            if previous is None or FIRE.index(color) > FIRE.index(previous):
                seen[(x, y)] = color
    return [(x, y, c, 255) for (x, y), c in seen.items()]


# --- Sparks -----------------------------------------------------------------

SPARKS = 5


def spark_pixels(z: int, frame: int) -> list[Pixel]:
    pixels: list[Pixel] = []
    for i in range(SPARKS):
        age = (frame + round(i * FRAMES / SPARKS)) % FRAMES
        if 24 + age != z or age == FRAMES - 1:
            continue
        theta = i * 2.4 + age * 0.55
        r = 1.2 + age * 0.45
        x = int(C + math.cos(theta) * r)
        y = int(C + math.sin(theta) * r * 0.9)
        color = FIRE[5 - min(5, age // 1)] if age < 3 else FIRE[max(0, 4 - age + 1)]
        alpha = 255 if age < 5 else 210
        pixels.append((x, y, color, alpha))
    return pixels


# --- Atlas ------------------------------------------------------------------

def slice_pixels(z: int, frame: int) -> list[Pixel]:
    if z <= 13:
        return handle_slice(z, frame)
    if z <= 18:
        return cup_slice(z, frame)
    pixels: list[Pixel] = []
    if z == 19:
        pixels += coal_slice(frame)
    if FLAME_BASE <= z <= FLAME_TOP + 1:
        pixels += flame_slice(z, frame)
    pixels += spark_pixels(z, frame)
    return pixels


def main() -> None:
    atlas = Image.new("RGBA", (SIZE * SLICES, SIZE * FRAMES), (0, 0, 0, 0))
    for frame in range(FRAMES):
        for z in range(SLICES):
            for x, y, (r, g, b), a in slice_pixels(z, frame):
                atlas.putpixel((z * SIZE + x, frame * SIZE + y), (r, g, b, a))

    atlas.save(OUT)
    print(f"wrote {OUT} ({atlas.width}x{atlas.height})")


if __name__ == "__main__":
    main()
