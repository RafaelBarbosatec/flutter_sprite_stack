---
name: flutter-sprite-stack-assets
description: Author, slice, pack and validate sprite-stack PNGs for the flutter_sprite_stack package. Use when creating a 360-degree prop from orthographic views, slicing a sheet into cross-sections, building a vertical multi-frame atlas for animation, or debugging a stack that renders with gaps, floats, wobbles, jitters or clips.
license: MIT
metadata:
  package: flutter_sprite_stack
  version: "0.3.0"
---

# Sprite-stack assets

A sprite stack is one PNG holding the horizontal cross-sections of a prop,
ordered **bottom to top**. The renderer draws the slices in order with a small
vertical lift, which fakes height; rotating around Y is then free, because every
angle is just the same slices drawn with a skewed shear.

```text
one frame (a "strip"):

  z0   z1   z2   …   zN-1        ← slice 0 = ground contact, on the left
 ┌────┬────┬────┬────┬────┐
 │    │    │    │    │    │      each cell = the prop cut at that height
 └────┴────┴────┴────┴────┘
```

`sliceCount` is the number of cells; `sliceWidth = imageWidth / sliceCount`.
A **frame atlas** stacks several strips vertically:

```text
frame 0  [z0][z1][z2] … [zN-1]   ← row 0 of the atlas
frame 1  [z0][z1][z2] … [zN-1]
…
```

`sliceHeight = imageHeight / frameCount`.

## Decide what you are making

| The prop… | Use | Cost |
| --- | --- | --- |
| is rigid (crate, car, house) | one strip | baseline memory |
| flexes (tree, flag, cape, torch) | one strip + `StackMotion` at runtime | same memory, no extra art |
| changes silhouette (walk cycle, wing flap) | frame atlas | `frameCount ×` memory |
| opens up (roof off, crate open) | one strip + `SliceCut` at runtime | same memory, no extra art |

Author frames only when the **silhouette** changes. Do not author frames for
sway, breathing, bobbing or lean: `StackMotion` does that for free at runtime.

## Workflow

### 1. Get orthographic views

The reference pipeline needs four orthographic views — **TOP, SIDE, FRONT,
BACK** — on a flat background, all at the same scale.

Upstream carving tool (Python + NumPy + Pillow, runs on the dev machine):

```bash
pip install pillow numpy
npx skills add danielwh2/sprite-stacking    # fetches SKILL.md + the scripts

python3 skills/sprite-stacking/scripts/views_to_slices.py views.png slices.png \
  --slices 24 \
  --shade 0.2 \
  --preview check.png
```

Useful flags: `--round` (clip each slice to an ellipse — towers, pots, balloons),
`--side-nose left|right`, `--order auto|reading` and `--colours N` (shared
palette across the four views).

Do **not** re-implement the carver in Dart. It is a one-off authoring step; the
Dart package only consumes the strip.

### 2. Validate the strip

```bash
python3 scripts/validate_atlas.py slices.png --slices 32
```

Exit code `0` means usable, `1` means broken. Fix errors before touching Flutter;
they are invisible in a PNG viewer and obvious in game.

### 3. (Animated props) build the atlas

Render every frame on the **same canvas with the same pivot**:

```bash
python3 scripts/make_atlas.py torch.png \
  frames/f00.png frames/f01.png frames/f02.png frames/f03.png \
  --slices 14 --force

python3 scripts/validate_atlas.py torch.png --slices 14 --frames 4
```

`make_atlas.py` refuses frames with different sizes on purpose: padding a smaller
frame shifts its pivot and makes the animation jump.

### 4. Register the asset

```yaml
flutter:
  assets:
    - assets/torch.png
```

Load it with the matching numbers:

```dart
final torch = await SpriteStack.load(
  'assets/torch.png',
  sliceCount: 32,
  frameCount: 8,
);
```

## Rules

- **Slice 0 is the ground contact.** It anchors the shadow and the component's
  `groundLocal`. An empty slice 0 makes the prop float.
- **A slice is a filled cross-section, not an outline.** Hollow interiors are
  what the renderer shows when a `SliceCut` removes the roof; do not paint the
  inside of the volume on every slice.
- **One cell width for the whole strip.** Never crop each slice to its own
  content: that re-centres each slice and the prop wobbles while rotating.
- **Transparent background, hard alpha.** Anti-aliased edges read as a halo
  around pixel art; the renderer keeps hard pixels on purpose.
- **Cell size ~ square.** 16–32 px per side is a good default; props that are
  tall in profile (cars, trees) often use taller cells. Very wide cells waste
  fill rate on empty pixels.
- **Leave headroom for animated parts.** A flag or wing needs empty slices above
  the rest pose, otherwise motion clips at the top of the cell.
- **Keep the frame count small.** Memory is `width × height × 4 × frames`
  decoded: 6 frames of 24 slices at 32×32 is ~590 KB, 6 frames of 64 slices at
  64×64 is ~6 MB.

## Diagnose a broken render

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| gaps between cross-sections | empty slices inside the stack | fill the slice, or raise `sliceCount` |
| prop floats above its shadow | slice 0 empty | move the prop down in the volume before carving |
| wobbles while rotating | slices cropped/re-centred individually | re-carve with one shared cell width |
| animation jitters | frames rendered with different pivots or canvas sizes | re-render on an identical canvas |
| top of the prop clips when it moves | no headroom slices | add empty slices at the top |
| whole cell painted, including background | opaque background | export with alpha |
| prop looks translucent | semi-transparent pixels | flatten alpha to 0 or 255 |
| `ArgumentError: Image WxH does not split…` | `sliceCount`/`frameCount` do not divide the image | run the validator, pass the right numbers |

## Scripts

Both scripts are pure Python 3 standard library — no `pip install`, no Pillow,
no NumPy. They run anywhere the agent has a shell.

```bash
# a strip or atlas: dimensions, gaps, pivot drift, alpha hygiene
python3 scripts/validate_atlas.py <png> --slices N [--frames M] [--strict] [--json]

# pack frames into an atlas (same size required), optionally validating
python3 scripts/make_atlas.py <out.png> f0.png f1.png … --slices N [--force]
```

`--strict` promotes warnings to errors; use it in CI for assets you own.
`--json` prints a machine-readable report when you need to post-process it.

## More

- `references/asset-format.md` — exact format math, memory table, naming.
- `references/authoring-rules.md` — the reference pipeline's rules on top of ours
  (frame selection, headroom, slice bloom) and where they come from.
