#!/usr/bin/env python3
"""Model an iconic Star Wars inspired starfighter (T-65 X-Wing style) as a voxel volume.

Star Wars starfighter signature features:
- Long tapered wedge fuselage with pointed nose and nosecone sensor tip
- Dark tinted cockpit canopy with angular blast glass framing
- Astromech droid socket (R2 unit blue/silver dome) behind cockpit
- Iconic X-configuration S-foils (four split wings spread vertically with gap)
- Four heavy sublight engine cylinders at wing roots with glowing blue-cyan ion afterburners
- Four long laser cannons mounted on wingtips with muzzle barrels reaching forward
- Rebel Alliance red squadron stripes and markings ('Red Five' style accents)
- Hull plating in dirty starship off-white / light battle-gray with darker mechanical paneling
- Underbelly proton torpedo launcher chutes and shield generator ridges

Axes: vol[z, y, x]
- x: left to right (width = 45, CX = 22)
- y: back to front (length = 65, nose is pointing to +y, so in top view nose is DOWN)
  s is distance from nose tip along the ship: y = L - 1 - s (s=0 is nose tip, s=L-1 is rear)
- z: bottom to top (height = 21 slices, CZ = 10 is central wing axis)

Outputs: slices.png, views.png, check.png, viewer.html, turntable.gif
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

SLICER = Path("/home/rafael/.pi/agent/git/github.com/danielwh2/sprite-stacking/skills/sprite-stacking/scripts")
sys.path.insert(0, str(SLICER))
from views_to_slices import build_html_viewer, build_preview, render_stack_image  # noqa: E402

PAL = {
    # Starfighter Hull (dirty off-white / light alloy)
    "hull_hi": (240, 243, 248),
    "hull": (208, 214, 224),
    "hull_mid": (175, 182, 195),
    "hull_sh": (135, 142, 155),
    "hull_dark": (95, 102, 115),
    # Mechanical greebles & internals
    "metal_dark": (45, 48, 56),
    "metal_black": (26, 28, 34),
    "metal_pipe": (120, 125, 138),
    # Squadron Markings (Rebel Red Five)
    "rebel_red": (214, 42, 42),
    "rebel_red_hi": (245, 75, 68),
    "rebel_red_sh": (150, 25, 28),
    "yellow_marking": (240, 195, 48),
    # Canopies: dark smoky blue glass with strong framing and bright sky-glint
    "canopy_glass": (16, 28, 44),
    "canopy_dark": (10, 18, 30),
    "canopy_glint": (130, 210, 255),
    "canopy_bright": (220, 245, 255),
    "canopy_frame": (50, 56, 70),
    "canopy_frame_hi": (110, 118, 135),
    # Astromech Droid (R2 unit)
    "droid_white": (245, 245, 250),
    "droid_blue": (38, 92, 215),
    "droid_eye": (220, 40, 40),
    "droid_silver": (185, 192, 205),
    # Engines & Thrusters
    "engine_intake": (50, 54, 64),
    "engine_rim": (145, 152, 165),
    "engine_glow": (80, 210, 255),      # bright cyan ion exhaust
    "engine_core": (220, 250, 255),     # pure hot center
    # Laser Cannons
    "cannon_body": (65, 70, 80),
    "cannon_hi": (130, 135, 148),
    "cannon_tip": (230, 60, 50),       # hot ready laser emitter
}

X, L, H = 45, 65, 21
CX = (X - 1) / 2.0  # 22.0
CZ = 10.0           # midplane height

vol = np.zeros((H, L, X, 4), dtype=np.uint8)


def col(name: str):
    r, g, b = PAL[name]
    return (r, g, b, 255)


def put(x: int | float, s: int | float, z: int | float, name: str, mirror=False):
    ix = int(round(x))
    is_ = int(round(s))
    iz = int(round(z))
    for xx in ((ix, int(round(X - 1 - ix))) if mirror else (ix,)):
        if 0 <= xx < X and 0 <= is_ < L and 0 <= iz < H:
            vol[iz, L - 1 - is_, xx] = col(name)


def box(x0: int, x1: int, s0: int, s1: int, z0: int, z1: int, name: str, mirror=False):
    for z in range(z0, z1 + 1):
        for s in range(s0, s1 + 1):
            for x in range(x0, x1 + 1):
                put(x, s, z, name, mirror)


def circle_disc(cx: float, cz: float, r: float, s: int, name: str, mirror=False):
    r_sq = r * r
    min_x = int(math.floor(cx - r))
    max_x = int(math.ceil(cx + r))
    min_z = int(math.floor(cz - r))
    max_z = int(math.ceil(cz + r))
    for z in range(min_z, max_z + 1):
        for x in range(min_x, max_x + 1):
            if (x - cx) ** 2 + (z - cz) ** 2 <= r_sq:
                put(x, s, z, name, mirror)


# -------------------------------------------------------------------------
# 1. NOSECONE & MAIN FUSELAGE
# -------------------------------------------------------------------------
# Nose tip sensor probe (s = 0..3)
box(21, 23, 0, 1, 9, 11, "metal_dark")
box(21, 23, 2, 3, 9, 11, "hull_dark")
put(22, 0, 10, "metal_pipe")

# Forward fuselage wedge (s = 4..30)
# Tapers outward in width and height towards the cockpit
for s in range(4, 31):
    t = (s - 4) / 26.0  # 0.0 to 1.0
    hw = 1.6 + t * 4.2   # half-width: ~1.6 at s=4 to ~5.8 at s=30 (width ~3 to 12)
    hz = 1.3 + t * 3.7   # half-height: ~1.3 at s=4 to ~5.0 at s=30 (height ~3 to 11)

    min_x = int(math.floor(CX - hw))
    max_x = int(math.ceil(CX + hw))
    min_z = int(math.floor(CZ - hz))
    max_z = int(math.ceil(CZ + hz))

    for z in range(min_z, max_z + 1):
        for x in range(min_x, max_x + 1):
            # Hexagonal / chamfered cross-section for classic starship wedge
            dx = abs(x - CX) / (hw + 0.01)
            dz = abs(z - CZ) / (hz + 0.01)
            if dx + dz * 0.4 <= 1.05 and dz + dx * 0.35 <= 1.05:
                # Color paneling
                c_name = "hull"
                if z == min_z or z == max_z:
                    c_name = "hull_mid"
                if abs(x - CX) >= hw - 0.7:
                    c_name = "hull_sh"
                put(x, s, z, c_name)

# Rebel squadron red chevrons on fuselage nose (s = 10..14)
for s in range(10, 15):
    put(CX - 2, s, CZ + 2, "rebel_red", mirror=True)
    put(CX - 1, s, CZ + 3, "rebel_red", mirror=True)
put(CX, 8, CZ + 1, "yellow_marking")

# Proton torpedo launcher indents underneath (s = 18..24)
box(19, 20, 18, 22, 6, 7, "metal_black")
box(24, 25, 18, 22, 6, 7, "metal_black")

# Mid & Aft fuselage body (s = 31..54)
for s in range(31, 55):
    hw = 6.0
    hz = 5.0
    min_x = int(CX - hw)
    max_x = int(CX + hw)
    min_z = int(CZ - hz)
    max_z = int(CZ + hz)
    for z in range(min_z, max_z + 1):
        for x in range(min_x, max_x + 1):
            dx = abs(x - CX) / hw
            dz = abs(z - CZ) / hz
            if dx + dz * 0.35 <= 1.15 and dz <= 1.0:
                c_name = "hull"
                if abs(x - CX) >= hw - 0.8:
                    c_name = "hull_sh"
                put(x, s, z, c_name)

# Rear engine compartment & thrust structure (s = 55..59)
for s in range(55, 60):
    box(17, 27, s, s, 6, 14, "metal_dark")
    box(18, 26, s, s, 7, 13, "metal_black")

# -------------------------------------------------------------------------
# 2. COCKPIT CANOPY (s = 20..38, z = 11..16)
# -------------------------------------------------------------------------
for s in range(20, 39):
    t_canopy = (s - 20) / 18.0
    # Canopy rises sharply from s=20 to s=31, then slopes down to droid socket
    if t_canopy <= 0.65:
        cap_z = 11.5 + (t_canopy / 0.65) * 4.8  # peaks at ~16.3
    else:
        cap_z = 16.3 - ((t_canopy - 0.65) / 0.35) * 1.8  # slopes down to ~14.5

    canopy_hw = 1.0 + math.sin(t_canopy * math.pi) * 3.4
    for z in range(11, int(round(cap_z)) + 1):
        for x in range(int(round(CX - canopy_hw)), int(round(CX + canopy_hw)) + 1):
            if abs(x - CX) <= canopy_hw:
                is_frame = (
                    abs(x - CX) >= canopy_hw - 0.7
                    or z >= int(round(cap_z))
                    or s in (20, 26, 32, 38)
                    or (abs(x - CX) < 0.6 and z >= int(round(cap_z)) - 1)  # central rib
                )
                if is_frame:
                    put(x, s, z, "canopy_frame_hi" if z >= int(round(cap_z)) else "canopy_frame")
                else:
                    # Glass with diagonal specular shine streak
                    diag = (s - 20) - (z - 11) * 2
                    if diag in (2, 3):
                        put(x, s, z, "canopy_bright")
                    elif diag in (0, 1, 4, 5):
                        put(x, s, z, "canopy_glint")
                    else:
                        put(x, s, z, "canopy_glass")

# Cockpit interior seat & pilot helmet visible through canopy
box(21, 23, 27, 32, 11, 13, "metal_black")
put(22, 29, 13, "rebel_red")       # red rebel flight helmet!
put(22, 29, 14, "droid_white")     # helmet crest
put(22, 28, 13, "yellow_marking")  # tinted flight visor

# -------------------------------------------------------------------------
# 3. ASTROMECH DROID SOCKET & R2 UNIT (s = 39..43)
# -------------------------------------------------------------------------
box(20, 24, 39, 43, 13, 14, "hull_dark")
# Droid dome (z = 15..17)
circle_disc(CX, 15.5, 2.0, 40, "droid_silver")
circle_disc(CX, 15.5, 2.0, 41, "droid_silver")
circle_disc(CX, 15.5, 2.0, 42, "droid_silver")
box(21, 23, 40, 42, 16, 17, "droid_silver")
# Blue details on droid
put(22, 40, 16, "droid_blue")
put(21, 41, 16, "droid_blue")
put(23, 41, 16, "droid_blue")
put(22, 42, 16, "droid_blue")
put(22, 40, 15, "droid_eye")  # red photoreceptor eye!

# -------------------------------------------------------------------------
# 4. FOUR INCOM 4L4 SUBLIGHT ENGINES (s = 38..62)
# -------------------------------------------------------------------------
# Located at 4 quadrants: left/right (x ~ 14 and 30), top/bottom (z ~ 6 and 14)
ENGINE_CENTERS = [
    (14.0, 14.5),  # Top Left
    (30.0, 14.5),  # Top Right
    (14.0, 5.5),   # Bottom Left
    (30.0, 5.5),   # Bottom Right
]

for ex, ez in ENGINE_CENTERS:
    # Engine intake half-cylinders and main turbines (s = 38..56)
    for s in range(38, 57):
        r = 3.2
        # Front air intake lips (s = 38..40)
        if s <= 40:
            circle_disc(ex, ez, r, s, "engine_rim")
            circle_disc(ex, ez, r - 1.2, s, "engine_intake")
        elif s < 53:
            # Main engine housing
            circle_disc(ex, ez, r, s, "hull")
            # Panel ribbing along engine
            if s in (44, 48, 52):
                circle_disc(ex, ez, r, s, "hull_dark")
        else:
            # Rear nozzle tapering
            circle_disc(ex, ez, r, s, "metal_dark")
            circle_disc(ex, ez, r - 0.7, s, "metal_black")

    # Exhaust nozzle rings (s = 57..60)
    for s in range(57, 61):
        circle_disc(ex, ez, 2.7, s, "metal_dark")
        circle_disc(ex, ez, 1.8, s, "metal_black")

    # Glowing ion afterburner thrust plume (s = 61..64)
    circle_disc(ex, ez, 1.9, 61, "engine_rim")
    circle_disc(ex, ez, 1.4, 61, "engine_glow")
    put(ex, 61, ez, "engine_core")

    circle_disc(ex, ez, 1.2, 62, "engine_glow")
    put(ex, 62, ez, "engine_core")

    circle_disc(ex, ez, 0.9, 63, "engine_glow")
    put(ex, 63, ez, "engine_core")

    put(ex, 64, ez, "engine_glow")

# -------------------------------------------------------------------------
# 5. S-FOIL WINGS IN ATTACK POSITION (X-CONFIGURATION)
# -------------------------------------------------------------------------
# Four split wings spread out from engine roots to wingtips:
# - Upper Left:  x: 14 -> 3,  s: 40 -> 60, z rises from 14 -> 18
# - Upper Right: x: 30 -> 41, s: 40 -> 60, z rises from 14 -> 18
# - Lower Left:  x: 14 -> 3,  s: 40 -> 60, z drops from 6  -> 2
# - Lower Right: x: 30 -> 41, s: 40 -> 60, z drops from 6  -> 2

WING_CONFIGS = [
    # (is_right, is_top)
    (False, True),
    (True, True),
    (False, False),
    (True, False),
]

for is_right, is_top in WING_CONFIGS:
    z_dir = 1.0 if is_top else -1.0
    for span in range(0, 15):  # 0 is near engine, 14 is wingtip
        x_val = (27 + span) if is_right else (17 - span)
        z_base = CZ + (3.8 + span * 0.42) * z_dir
        z_int = int(round(z_base))

        # Chord of the wing sweeps backwards:
        # at root: s in 39..56
        # at tip:  s in 44..59
        s_front = int(round(39 + span * 0.4))
        s_back = int(round(56 + span * 0.25))

        for s in range(s_front, s_back + 1):
            # Wing thickness (1 to 2 slices)
            put(x_val, s, z_int, "hull")
            if span > 6:
                put(x_val, s, z_int + (1 if is_top else -1), "hull_sh")

            # Red Five squadron stripes on wing surfaces!
            # Signature 5 red stripes on outer wings
            if 7 <= span <= 13:
                # Characteristic hash marks near wingtip
                if (span + s) % 3 == 0 and s >= 48:
                    put(x_val, s, z_int, "rebel_red")
            # Yellow trim along wing leading edge
            if s == s_front and span >= 4:
                put(x_val, s, z_int, "yellow_marking")

# -------------------------------------------------------------------------
# 6. FOUR TAIM & BAK KX9 LASER CANNONS (AT WINGTIPS)
# -------------------------------------------------------------------------
# Mounted at the four wingtip positions:
# Span = 14 => x = 3 (left) and 41 (right)
# Upper tips at z = 18, Lower tips at z = 2
CANNON_POSITIONS = [
    (3, 18),   # Upper Left
    (41, 18),  # Upper Right
    (3, 2),    # Lower Left
    (41, 2),   # Lower Right
]

for cx_tip, cz_tip in CANNON_POSITIONS:
    # Cannon generator mount at wingtip (s = 48..60)
    for s in range(48, 61):
        box(cx_tip - 1, cx_tip + 1, s, s, cz_tip - 1, cz_tip + 1, "metal_dark")
        put(cx_tip, s, cz_tip, "hull_dark")
        # Flash suppressor cooling vents
        if s in (50, 54, 58):
            put(cx_tip, s, cz_tip + 1, "metal_pipe")
            put(cx_tip, s, cz_tip - 1, "metal_pipe")

    # Long cannon barrel extending forward past the nose! (s = 14..47)
    for s in range(14, 48):
        put(cx_tip, s, cz_tip, "cannon_body")
        # Spiral reinforcement rings on barrel
        if s in (18, 25, 32, 39):
            put(cx_tip, s, cz_tip, "cannon_hi")
            put(cx_tip - 1, s, cz_tip, "metal_dark")
            put(cx_tip + 1, s, cz_tip, "metal_dark")

    # Laser emitter muzzle tip (s = 11..13)
    put(cx_tip, 13, cz_tip, "metal_black")
    put(cx_tip, 12, cz_tip, "cannon_tip")
    put(cx_tip, 11, cz_tip, "cannon_tip")

# -------------------------------------------------------------------------
# 7. TOP & DIRECTIONAL LIGHTING HIGHLIGHTS
# -------------------------------------------------------------------------
HI_MAP = {
    "hull": "hull_hi",
    "hull_sh": "hull_mid",
    "hull_mid": "hull_hi",
    "rebel_red": "rebel_red_hi",
    "rebel_red_sh": "rebel_red",
    "metal_dark": "metal_pipe",
    "canopy_frame": "hull_hi",
    "cannon_body": "cannon_hi",
}
hi_lookup = {col(k): col(v) for k, v in HI_MAP.items()}

src = vol.copy()
for z in range(H):
    for y in range(L):
        for x in range(X):
            if src[z, y, x, 3] == 0:
                continue
            above = src[z + 1, y, x, 3] if z + 1 < H else 0
            if above == 0:
                key = tuple(int(v) for v in src[z, y, x])
                if key in hi_lookup:
                    vol[z, y, x] = hi_lookup[key]


# -------------------------------------------------------------------------
# 8. ORTHOGRAPHIC PROJECTIONS & ASSET EXPORT
# -------------------------------------------------------------------------
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


def render_turntable(v, out_path, scale=5):
    frames = []
    for angle in range(0, 360, 22):  # 16 frames
        frame = render_stack_image(v, angle, squash=0.75, spacing=1.0, shadow=True, outline=True)
        w, h = frame.size
        frame = frame.resize((w * scale, h * scale), Image.NEAREST)
        frames.append(frame)

    w = max(f.width for f in frames)
    h = max(f.height for f in frames)
    canvas_frames = []
    for f in frames:
        c = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        c.paste(f, ((w - f.width) // 2, (h - f.height) // 2), f)
        canvas_frames.append(c)

    bg = (18, 22, 30, 255)  # deep space blue background
    gif_frames = []
    for f in canvas_frames:
        flat = Image.new("RGBA", (w, h), bg)
        flat.alpha_composite(f)
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
    print(f"wrote turntable {out_path}")


def main() -> None:
    out = Path(__file__).resolve().parent
    slices_img = Image.fromarray(np.concatenate(list(vol), axis=1))
    slices_img.save(out / "slices.png")
    print(f"Exported {H} slices of {X} x {L} px: total {slices_img.width}x{slices_img.height} px")

    views = [top_view(vol), side_view(vol), front_view(vol), back_view(vol)]
    compose_sheet(views, out / "views.png")
    print("Exported views.png")

    build_preview(vol, views, out / "check.png")
    print("Exported check.png")

    build_html_viewer(vol, views, out / "viewer.html", title="Starfighter Sprite Stack")
    print("Exported viewer.html")

    render_turntable(vol, out / "turntable.gif")


if __name__ == "__main__":
    main()
