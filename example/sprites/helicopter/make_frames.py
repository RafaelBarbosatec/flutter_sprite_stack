#!/usr/bin/env python3
"""Generate a military attack helicopter sprite stack with animated long rotors.

Outputs:
  - frames.png: Vertical stack of 8 frames, each frame has 24 slices horizontally.
    Total size: (24 * 68) x (8 * 76) = 1632 x 608 px.
  - slices.png: Frame 0 slices.
  - views.png: Orthographic 4 views of frame 0.
  - check.png: Visual check sheet of frame 0.
  - viewer.html: HTML turntable viewer.
  - turntable.gif: GIF showing helicopter turning AND rotors spinning.

Anatomy (Apache / Viper inspired military attack helicopter):
  X = 68, L = 76, H = 24, FRAMES = 8.
  Nose points towards +Y (down in top view).
  Tail points towards 0.
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

X = 68   # width (wide clearance for long main rotor)
L = 76   # length (tail to nose 30mm chain gun)
H = 24   # height (slices)
FRAMES = 8

CX = (X - 1) / 2.0  # 33.5
ROTOR_X = CX
ROTOR_Y = 44.0      # Main rotor mast position (cabin center-forward)
TAIL_ROTOR_Y = 8.0  # Tail rotor position
TAIL_ROTOR_X = CX + 2.5 # Starboard side of vertical stabilizer

PAL = {
    # Camouflage / Armor (Olive Drab & Shading)
    "camo_base": (56, 72, 48),
    "camo_dark": (38, 48, 32),
    "camo_shadow": (26, 32, 22),
    "camo_hi": (84, 106, 72),
    "camo_light": (108, 132, 92),
    "belly": (44, 54, 38),
    # Metal / Machinery / Skids
    "metal_black": (20, 22, 25),
    "metal_dark": (32, 35, 40),
    "metal_mid": (55, 60, 68),
    "metal_hi": (95, 102, 116),
    "skid": (34, 38, 44),
    "skid_hi": (72, 78, 90),
    # Cockpit Glass (Smoky ballistic glass with vibrant reflection)
    "glass_dark": (14, 24, 26),
    "glass_mid": (25, 58, 62),
    "glass_hi": (55, 130, 135),
    "glass_spec": (160, 240, 230),
    "cockpit_interior": (18, 20, 22),
    "pilot_suit": (48, 60, 42),
    "pilot_helmet": (120, 115, 85),
    "visor": (22, 35, 50),
    # Weapons & Ordnance
    "pylon": (46, 58, 40),
    "pylon_dark": (32, 40, 28),
    "rocket_pod": (52, 65, 46),
    "rocket_front": (22, 24, 26),
    "rocket_tube": (12, 12, 14),
    "missile_rail": (38, 42, 46),
    "hellfire_body": (220, 224, 230),
    "hellfire_head": (32, 34, 36),
    "hellfire_band": (225, 185, 35),
    "chain_gun": (22, 24, 26),
    "gun_barrel": (42, 45, 50),
    "gun_muzzle": (16, 18, 20),
    "sensor_turret": (30, 34, 38),
    "sensor_lens": (24, 180, 195),
    "sensor_lens2": (220, 60, 50),    # FLIR thermal eye
    # Engine & Exhaust
    "intake": (16, 18, 20),
    "exhaust": (85, 75, 65),
    "exhaust_dark": (45, 40, 35),
    # Rotors & Markings
    "rotor_hub": (45, 48, 54),
    "rotor_blade": (26, 28, 32),
    "rotor_edge": (58, 62, 70),
    "rotor_tip": (235, 205, 35),       # High-vis warning yellow
    "rotor_stripe": (220, 40, 40),     # Warning red band
    "tail_blade": (30, 32, 36),
    "tail_tip": (235, 205, 35),
    "nav_red": (240, 40, 40),
    "nav_green": (40, 225, 60),
    "white_star": (235, 240, 245),
}

def col(name):
    return (*PAL[name], 255)

def build_base_volume() -> np.ndarray:
    """Build the static helicopter airframe."""
    v = np.zeros((H, L, X, 4), dtype=np.uint8)

    def put(x, y, z, name, mirror=False):
        for xx in ((x, X - 1 - x) if mirror else (x,)):
            ix, iy, iz = int(round(xx)), int(round(y)), int(round(z))
            if 0 <= ix < X and 0 <= iy < L and 0 <= iz < H:
                v[iz, iy, ix] = col(name)

    def box(x0, x1, y0, y1, z0, z1, name, mirror=False):
        for z in range(z0, z1 + 1):
            for y in range(y0, y1 + 1):
                for x in range(x0, x1 + 1):
                    put(x, y, z, name, mirror)

    # -------------------------------------------------------------------------
    # 1. LANDING SKIDS (z=0, 1, 2)
    # Skids at x=20..21 (mirror x=46..47). Runs from y=24 to y=60
    box(20, 21, 26, 60, 0, 0, "skid", mirror=True)
    box(20, 21, 26, 60, 1, 1, "skid_hi", mirror=True)

    # Front upturn curve (y=61..65)
    put(20, 61, 1, "skid", mirror=True)
    put(21, 61, 1, "skid_hi", mirror=True)
    put(20, 62, 2, "skid", mirror=True)
    put(21, 62, 2, "skid_hi", mirror=True)
    put(20, 63, 3, "skid", mirror=True)
    put(21, 63, 3, "skid_hi", mirror=True)
    put(20, 64, 4, "skid_hi", mirror=True)

    # Rear upturn curve (y=24..25)
    put(20, 25, 1, "skid", mirror=True)
    put(21, 25, 1, "skid_hi", mirror=True)
    put(20, 24, 2, "skid_hi", mirror=True)

    # Skid cross struts connecting to fuselage (at y=31 and y=51, z=1..3)
    for s_y in (31, 51):
        for step, x in enumerate(range(22, 28)):
            z_pos = 1 + (step * 2) // 5
            put(x, s_y, z_pos, "metal_dark", mirror=True)
            put(x, s_y, z_pos + 1, "metal_mid", mirror=True)

    # -------------------------------------------------------------------------
    # 2. 30mm CHIN CANNON & GIMBAL (z=0..3, y=62..75)
    box(33, 34, 67, 74, 0, 0, "gun_barrel")
    put(33, 75, 0, "gun_muzzle")
    put(34, 75, 0, "gun_muzzle")
    box(32, 35, 62, 66, 0, 1, "chain_gun")
    box(32, 35, 60, 63, 1, 2, "metal_black")

    # -------------------------------------------------------------------------
    # 3. NOSE SENSOR TURRET (TADS/PNVS at y=64..70, z=2..5)
    for z in range(2, 6):
        for y in range(64, 71):
            for x in range(30, 38):
                dx = x - CX
                dy = y - 67.0
                dz = z - 3.5
                if dx*dx + dy*dy*0.85 + dz*dz*1.1 <= 5.5:
                    put(x, y, z, "sensor_turret")
    # Day/Night optical sensor lens
    box(34, 35, 70, 70, 3, 4, "sensor_lens")
    put(34, 70, 4, "glass_spec")
    # FLIR thermal eye
    put(31, 69, 3, "sensor_lens2")

    # -------------------------------------------------------------------------
    # 4. LOWER FUSELAGE & BELLY (z=3..6)
    for y in range(21, 65):
        if y < 28:
            hw = 2.2 + (y - 21) * 0.5
        elif y <= 52:
            hw = 5.8 + 1.4 * math.sin((y - 28) / 24.0 * math.pi)
        else:
            hw = 5.8 * (1.0 - (y - 52) / 13.0) ** 0.6 + 1.0

        xl = int(math.floor(CX - hw))
        xr = int(math.ceil(CX + hw))

        for x in range(xl + 1, xr):
            put(x, y, 3, "belly")

        for z in range(4, 7):
            for x in range(xl, xr + 1):
                if x == xl or x == xr:
                    put(x, y, z, "camo_dark" if z == 4 else "camo_base")
                else:
                    put(x, y, z, "camo_base")

    # -------------------------------------------------------------------------
    # 5. WEAPON STUB WINGS (PYLONS) & ORDNANCE (z=6..7, y=39..47)
    box(14, 26, 40, 46, 6, 6, "pylon", mirror=True)
    box(14, 25, 41, 45, 7, 7, "camo_hi", mirror=True)
    box(14, 26, 40, 40, 6, 6, "pylon_dark", mirror=True)

    # Wingtip missile launch rails & navigation lights
    box(13, 13, 39, 47, 6, 7, "missile_rail", mirror=True)
    put(13, 39, 7, "nav_red")      # Port red light
    put(54, 39, 7, "nav_green")    # Starboard green light

    # Inboard ordnance: Hydra 70 Rocket Pod (x=21..24, y=37..48, z=4..6)
    for z in (4, 5):
        box(21, 24, 37, 48, z, z, "rocket_pod", mirror=True)
    box(21, 24, 49, 49, 4, 5, "rocket_front", mirror=True)
    put(22, 49, 4, "rocket_tube", mirror=True)
    put(23, 49, 4, "rocket_tube", mirror=True)
    put(22, 49, 5, "rocket_tube", mirror=True)
    put(23, 49, 5, "rocket_tube", mirror=True)

    # Outboard ordnance: Quad AGM-114 Hellfire Missiles (x=15..19, y=38..50, z=4..5)
    for mx, mz in ((15, 4), (18, 4), (16, 5), (18, 5)):
        box(mx, mx, 39, 48, mz, mz, "hellfire_body", mirror=True)
        put(mx, 47, mz, "hellfire_band", mirror=True)
        put(mx, 49, mz, "hellfire_head", mirror=True)

    # -------------------------------------------------------------------------
    # 6. TANDEM COCKPIT & CANOPY (z=7..13)
    # Gunner in front (y=53..62), Pilot in back elevated (y=39..51)
    for y in range(21, 63):
        if y < 28:
            hw = 2.0 + (y - 21) * 0.4
        elif y <= 51:
            hw = 5.0
        else:
            hw = 5.0 * (1.0 - (y - 51) / 12.0) ** 0.5 + 0.8
        xl = int(math.floor(CX - hw))
        xr = int(math.ceil(CX + hw))

        for z in range(7, 10):
            for x in range(xl, xr + 1):
                if x == xl or x == xr:
                    put(x, y, z, "camo_base")
                else:
                    put(x, y, z, "camo_base")

    # Cockpit interiors & crew
    # Gunner seat (y=54..60, z=7..9)
    box(32, 35, 54, 60, 7, 7, "cockpit_interior")
    box(33, 34, 55, 57, 8, 8, "pilot_suit")
    box(33, 34, 56, 57, 9, 9, "pilot_helmet")
    box(33, 34, 58, 58, 9, 9, "visor")

    # Pilot seat (elevated, y=42..49, z=8..10)
    box(32, 35, 42, 49, 8, 8, "cockpit_interior")
    box(33, 34, 43, 46, 9, 9, "pilot_suit")
    box(33, 34, 44, 46, 10, 10, "pilot_helmet")
    box(33, 34, 47, 47, 10, 10, "visor")

    # Faceted stealth canopy glass & frame (z=8..13, y=40..62)
    for y in range(40, 63):
        if y > 59:
            cw = 2.0
            z_top = 10
        elif y > 51:
            cw = 2.9
            z_top = 11
        elif y > 40:
            cw = 3.3
            z_top = 13
        else:
            cw = 2.4
            z_top = 12

        c_xl = int(math.floor(CX - cw))
        c_xr = int(math.ceil(CX + cw))

        for z in range(8, z_top + 1):
            for x in range(c_xl, c_xr + 1):
                is_frame = (x == c_xl or x == c_xr or z == z_top or
                            y in (40, 50, 51, 62))
                if is_frame:
                    put(x, y, z, "metal_dark")
                else:
                    if x == c_xl + 1 and z == z_top - 1:
                        put(x, y, z, "glass_hi")
                    elif (x + y) % 5 == 0 and z >= z_top - 2:
                        put(x, y, z, "glass_spec")
                    else:
                        put(x, y, z, "glass_mid")

    # Canopy top roof plate (z=14, y=41..49)
    box(32, 35, 42, 49, 14, 14, "camo_hi")

    # -------------------------------------------------------------------------
    # 7. TWIN TURBOSHAFT ENGINES (z=8..13, y=31..44, left & right)
    for z in range(8, 13):
        box(24, 29, 32, 44, z, z, "camo_base", mirror=True)
    # Air intakes at front (y=44..45, z=9..12)
    box(25, 28, 44, 44, 9, 12, "metal_dark", mirror=True)
    box(25, 28, 45, 45, 10, 11, "intake", mirror=True)
    # Infrared-suppressing exhaust nozzles (y=30..32, z=10..13)
    box(24, 28, 30, 32, 10, 12, "exhaust", mirror=True)
    box(25, 27, 29, 29, 10, 12, "exhaust_dark", mirror=True)
    put(26, 30, 13, "exhaust", mirror=True)

    # -------------------------------------------------------------------------
    # 8. TAIL BOOM & EMPENNAGE (y=5..28, z=9..19)
    for y in range(8, 29):
        hw = 1.0 + (y - 8) * 0.08
        bx_l = int(round(CX - hw))
        bx_r = int(round(CX + hw))
        bz_bot = int(round(10 + (y - 8) * 0.04))
        bz_top = int(round(12 + (y - 8) * 0.06))
        for z in range(bz_bot, bz_top + 1):
            for x in range(bx_l, bx_r + 1):
                put(x, y, z, "camo_base")

    # Horizontal tail wing / stabilizer (y=11..16, z=12..13, spans x=22..45)
    box(22, 45, 11, 15, 12, 12, "camo_base")
    box(22, 45, 12, 14, 13, 13, "camo_hi")
    box(22, 22, 10, 16, 11, 14, "camo_dark")
    box(45, 45, 10, 16, 11, 14, "camo_dark")

    # Swept vertical stabilizer fin (y=5..13, z=12..20)
    for z in range(12, 21):
        fy_front = int(round(12.5 - (z - 12) * 0.45))
        fy_back = int(round(7.0 - (z - 12) * 0.25))
        for y in range(fy_back, fy_front + 1):
            put(CX, y, z, "camo_base")
            put(CX - 1, y, z, "camo_dark")
            if y == fy_front:
                put(CX, y, z, "camo_hi")

    # -------------------------------------------------------------------------
    # 9. MAIN ROTOR MAST HOUSING (DOGHOUSE) (z=14..16, y=41..48)
    box(31, 36, 41, 48, 14, 15, "camo_base")
    box(32, 35, 42, 47, 16, 16, "camo_hi")
    # Mast shaft (z=17..20, at ROTOR_X, ROTOR_Y)
    rx = int(round(ROTOR_X))
    ry = int(round(ROTOR_Y))
    for z in range(17, 21):
        box(rx - 1, rx + 1, ry - 1, ry + 1, z, z, "metal_dark")
        put(rx, ry, z, "metal_hi")
    # Swashplate & pitch links at z=19
    box(rx - 2, rx + 2, ry - 2, ry + 2, 19, 19, "metal_mid")

    # -------------------------------------------------------------------------
    # 10. MILITARY STAR INSIGNIA
    put(27, 37, 13, "white_star")
    put(40, 37, 13, "white_star")

    return v


def add_rotors_to_volume(base_vol: np.ndarray, frame: int) -> np.ndarray:
    """Clone the base volume and paint rotating main rotor and tail rotor."""
    v = base_vol.copy()

    def put(x, y, z, name):
        ix, iy, iz = int(round(x)), int(round(y)), int(round(z))
        if 0 <= ix < X and 0 <= iy < L and 0 <= iz < H:
            v[iz, iy, ix] = col(name)

    # -------------------------------------------------------------------------
    # MAIN ROTOR: 4-blade rotor spinning at z=21 (cap at z=22..23)
    # Long, wide rotor radius: 30.5 px (Diameter 61 px across 68 px width!)
    ROTOR_RADIUS = 30.5
    angle_offset = (frame / FRAMES) * (math.pi / 2.0)

    # Longbow radar dome / mast nut at z=22..23
    rx = int(round(ROTOR_X))
    ry = int(round(ROTOR_Y))
    for dy in (-2, -1, 0, 1, 2):
        for dx in (-2, -1, 0, 1, 2):
            if dx*dx + dy*dy <= 4.5:
                put(rx + dx, ry + dy, 22, "metal_mid")
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            put(rx + dx, ry + dy, 23, "metal_hi")

    # 4 Rotor Blades
    for blade_idx in range(4):
        blade_angle = angle_offset + blade_idx * (math.pi / 2.0)
        cos_a = math.cos(blade_angle)
        sin_a = math.sin(blade_angle)

        nx = -sin_a
        ny = cos_a

        # Step along blade from hub (r=3.5) to tip (r=ROTOR_RADIUS)
        r = 3.5
        while r <= ROTOR_RADIUS:
            bx = ROTOR_X + r * cos_a
            by = ROTOR_Y + r * sin_a

            is_tip = (r >= ROTOR_RADIUS - 4.5)
            is_stripe = (ROTOR_RADIUS - 7.0 <= r < ROTOR_RADIUS - 4.5)

            tip_color = "rotor_tip" if is_tip else ("rotor_stripe" if is_stripe else "rotor_blade")
            edge_color = "rotor_tip" if is_tip else ("rotor_stripe" if is_stripe else "rotor_edge")

            put(bx, by, 21, tip_color)
            put(bx + 0.7 * nx, by + 0.7 * ny, 21, edge_color)

            if r <= 7.0:
                put(bx, by, 20, "metal_dark")

            r += 0.85

    # -------------------------------------------------------------------------
    # TAIL ROTOR: 4-blade anti-torque rotor spinning in Y-Z plane!
    # Mounted on starboard side (x = TAIL_ROTOR_X = 36), centered at y=TAIL_ROTOR_Y (8.0), z=16.0
    TAIL_RADIUS = 7.5
    tail_z_center = 16.0
    tail_angle_offset = (frame / FRAMES) * math.pi

    tx = int(round(TAIL_ROTOR_X))
    put(tx, TAIL_ROTOR_Y, int(round(tail_z_center)), "metal_hi")
    put(tx - 1, TAIL_ROTOR_Y, int(round(tail_z_center)), "metal_dark")

    for t_blade in range(4):
        t_ang = tail_angle_offset + t_blade * (math.pi / 2.0)
        cos_t = math.cos(t_ang)
        sin_t = math.sin(t_ang)

        tr = 1.0
        while tr <= TAIL_RADIUS:
            by = TAIL_ROTOR_Y + tr * cos_t
            bz = tail_z_center + tr * sin_t
            is_tip = (tr >= TAIL_RADIUS - 1.8)
            color_name = "tail_tip" if is_tip else "tail_blade"
            put(tx, by, bz, color_name)
            tr += 0.85

    # Top-lighting pass
    HI_MAP = {
        col("camo_base"): col("camo_hi"),
        col("camo_dark"): col("camo_base"),
        col("skid"): col("skid_hi"),
        col("metal_dark"): col("metal_mid"),
        col("metal_mid"): col("metal_hi"),
    }
    for z in range(H - 1):
        for y in range(L):
            for x in range(X):
                if v[z, y, x, 3] > 0 and v[z + 1, y, x, 3] == 0:
                    c = tuple(int(val) for val in v[z, y, x])
                    if c in HI_MAP:
                        v[z, y, x] = HI_MAP[c]

    return v


def top_view(v):
    out = np.zeros((L, X, 4), np.uint8)
    for z in range(H):
        m = v[z, ..., 3] > 0
        out[m] = v[z][m]
    return out


def side_view(v):
    out = np.zeros((H, L, 4), np.uint8)
    for x in range(X):
        m = v[..., x, 3] > 0
        out[m] = v[..., x, :][m]
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


def render_animated_turntable(frame_vols: list[np.ndarray], out_path: Path, scale=5):
    gif_images = []
    total_steps = 32
    for step in range(total_steps):
        angle = (step * 360.0 / total_steps)
        vol_idx = step % len(frame_vols)
        current_vol = frame_vols[vol_idx]

        frame_img = render_stack_image(
            current_vol, angle, squash=0.75, spacing=1.0, shadow=True, outline=True
        )
        w, h = frame_img.size
        frame_img = frame_img.resize((w * scale, h * scale), Image.NEAREST)

        bg = Image.new("RGBA", frame_img.size, (16, 20, 24, 255))
        bg.alpha_composite(frame_img)
        gif_images.append(bg.convert("RGB").convert("P", palette=Image.ADAPTIVE))

    gif_images[0].save(
        out_path,
        save_all=True,
        append_images=gif_images[1:],
        duration=65,
        loop=0,
        disposal=2,
        optimize=False,
    )
    print(f"wrote animated turntable {out_path}")


def main() -> None:
    out = Path(__file__).resolve().parent
    print("Building base military helicopter airframe...")
    base_vol = build_base_volume()

    print(f"Generating {FRAMES} animation frames with rotating rotors...")
    frame_vols = [add_rotors_to_volume(base_vol, f) for f in range(FRAMES)]

    # 1. Save frame 0 static slice strip
    frame0_strip = np.concatenate(list(frame_vols[0]), axis=1)
    Image.fromarray(frame0_strip).save(out / "slices.png")
    print(f"Wrote slices.png ({X * H}x{L})")

    # 2. Save full vertical animation atlas frames.png
    frame_strips = [np.concatenate(list(v), axis=1) for v in frame_vols]
    atlas_array = np.concatenate(frame_strips, axis=0)
    atlas_img = Image.fromarray(atlas_array)
    atlas_img.save(out / "frames.png")
    print(f"Wrote frames.png: {atlas_img.width}x{atlas_img.height} ({H} slices, {FRAMES} frames)")

    # 3. Orthographic views & preview
    views = [top_view(frame_vols[0]), side_view(frame_vols[0]), front_view(frame_vols[0]), back_view(frame_vols[0])]
    compose_sheet(views, out / "views.png")
    print("Wrote views.png")

    build_preview(frame_vols[0], views, out / "check.png")
    print("Wrote check.png")

    build_html_viewer(frame_vols[0], views, out / "viewer.html", title="Military Attack Helicopter")
    print("Wrote viewer.html")

    # 4. Animated GIF turntable
    render_animated_turntable(frame_vols, out / "turntable.gif")


if __name__ == "__main__":
    main()
