# flutter_sprite_stack

[![pub package](https://img.shields.io/pub/v/flutter_sprite_stack.svg)](https://pub.dev/packages/flutter_sprite_stack)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-%E2%89%A53.22-02569B?logo=flutter)](https://flutter.dev)
[![docs](https://img.shields.io/badge/docs-docs.page-6FA0FF)](https://docs.page/RafaelBarbosatec/flutter_sprite_stack)

📖 **Documentation:** https://docs.page/RafaelBarbosatec/flutter_sprite_stack

Render **sprite-stacking** props in Flutter with free turntable rotation.

A sprite stack is a set of horizontal cross-sections of a 3D shape. Drawing
them bottom-up — each one rotated and vertically squashed — produces a fake-3D
billboard you can spin in any direction. It is the same trick pixel-art games
have used since the 90s, with a **1x art-pixel software rasterizer** and no 3D
pipeline.

![Turntable of the example F1 car](https://github.com/RafaelBarbosatec/flutter_sprite_stack/blob/fb92cb362cd765698cdd5f64f6d8d578480e933a/doc/turntable.gif)

*The example F1 car spinning at runtime — four arbitrary angles of a 15-slice
strip, not 8 pre-baked directions.*

```
slices (ground slice on the left)
┌────┬────┬────┬────┬────┐
│ 0  │ 1  │ 2  │ …  │ 23 │   each slice: top-down cross-section
└────┴────┴────┴────┴────┘
        ↓ render bottom-up
      ╱▔▔╲        yaw     → rotation around the vertical axis
     │    │       pitch   → camera tilt (0 = edge-on, π/2 = top-down)
      ╲__╱        spacing → lift between slices
```

## Features

- **Free rotation**, not 8 or 16 baked directions: any `yaw` at runtime.
- **Cheap**: one texture, a 1x art-pixel software rasterizer, nearest-neighbour filtering.
- **Pixel-art finish**: crisp 1 px ink outline and a projected ground shadow,
  matching the reference `viewer.html` look.
- **Tiny API**: load a strip, call `render`.
- **Flutter and Flame/Bonfire**: `CustomPainter` for plain canvases,
  `PositionComponent` for scenes with Y sorting and hit boxes.
- **No 3D engine, no shaders, no platform channels** — it is just `Canvas`.

## Installation

```bash
flutter pub add flutter_sprite_stack
```

Or add it manually:

```yaml
dependencies:
  flutter_sprite_stack: ^0.3.0
```

Requires Flutter 3.22+ and Dart 3.5+. Works on every platform Flutter supports,
including web.

## Quick start

```dart
import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';

final robot = await SpriteStack.load(
  'assets/robot_stack.png',
  sliceCount: 24, // must divide the image width exactly
);

// Any Canvas: bottom-centre is the ground contact point.
robot.render(
  canvas,
  position: const Offset(160, 240),
  yaw: 0.6,                        // radians
  pitch: SpriteStack.defaultPitch, // asin(0.75), the reference 0.75 squash
  scale: 6,                        // integer scale keeps pixels crisp
  spacing: 1,                      // lift per slice, in source pixels
  outline: true,                   // crisp 1 px ink outline around the stack
  shadow: true,                    // projected ground shadow
);
```

### Plain Flutter

```dart
CustomPaint(
  size: const Size(320, 320),
  painter: SpriteStackPainter(
    stack: robot,
    yaw: 0.6,
    scale: 6,
  ),
)
```

`SpriteStackPainter` anchors the stack at the bottom centre of the canvas and
re-paints when `yaw`, `pitch`, `scale`, `spacing`, `offset`, `outline`,
`shadow`, their colors or `stackPaint` change.

### Flame / Bonfire

```dart
add(
  SpriteStackComponent(
    stack: robot,
    position: Vector2(120, 200),
    yaw: 0.6,
    stackScale: 4,
    priority: 10, // Y-sort with the rest of the scene
  ),
);
```

The component keeps `size` in sync with the **projected** bounds — rotated
footprint, outline and ground shadow — so hit boxes, camera culling and
`priority`-based sorting match what is actually drawn. `yaw` spins the prop; it
does **not** touch the component's own `angle`, and the drawing stays anchored
by its feet while the bounds change.

## Animation

Animation is a **frame atlas**: the same horizontal strips stacked vertically,
frame `0` on top. Nothing else changes — the slice format, bounds and outline
are per row.

```
frame 0  [z0][z1][z2] … [zN]   ← sliceCount per row
frame 1  [z0][z1][z2] … [zN]
…
frame 4  [z0][z1][z2] … [zN]
```

```dart
final torch = await SpriteStackAnimation.load(
  'sprites/torch.png',
  sliceCount: 14,
  frameCount: 5,
  frameDuration: 0.13,
  loop: true,
);

// In a Ticker / Flame update:
torch.update(dt);
stackPainter.frame = torch.frame; // or render(..., frame: torch.frame)
```

`SpriteStackAnimation` handles timing, looping, ping-pong, `play`/`stop`/`reset`
and `onComplete`. The rendering cost does not change: a 5-frame torch still
draws `sliceCount` slices per frame.

In Flame/Bonfire, use the animated component — same bounds, culling and Y
sorting as the static one:

```dart
add(
  AnimatedSpriteStackComponent(
    animation: torch,
    position: Vector2(120, 200),
    stackScale: 4,
    priority: 10,
  ),
);
```

Animate transforms too when it fits better: a spinning coin, a bobbing item or a
pulsing warning light does not need frames at all.

## Motion (sway and lean)

`StackMotion` offsets each slice with a quadratic falloff from the ground, so the
base stays planted and the tip moves. It needs no extra frames — one strip is
enough for a tree, banner, kelp, grass or cape.

```dart
final motion = StackMotion(
  sway: 2.5,    // amplitude at the tip, in source pixels
  speed: 1.8,   // radians per second
  wave: 0.7,    // phase lag per slice: the motion travels up as a wave
  phase: 0,     // desync props that share the same strip
  lean: Offset.zero, // constant bend, e.g. prevailing wind (+y is down)
);

// Any Canvas:
robot.render(canvas, position: ground, motion: motion, time: elapsed);

// Flame/Bonfire: the component advances the clock for you.
SpriteStackComponent(stack: tree, motion: motion);
```

The sway is `sin(time * speed - slice * wave + phase) * sway * (slice / (n-1))²`.
The squared falloff is what pins slice `0` — it is the formula recommended by
`danielwh2/sprite-stacking`, and it is why the base does not slide.

The software rasterizer works at 1x art-pixel resolution, so motion shifts
slices in whole art pixels. That is the native grid of pixel art; for sub-pixel
smoothness at high display scales, animate the component position instead.

## Cutaways (roof off)

`SliceCut` hides slices above (or below) a continuous frontier. Hide a house's
roof and what remains are the wall cross-sections — a dollhouse view with the
player inside.

```dart
final roof = SliceCut(top: 19);       // slices 0..18, roof gone

// Animate it: `top` is continuous, so the roof disappears slice by slice.
final roof = SliceCut(top: sliceCount * (1 - progress));

house.render(canvas, position: ground, cut: roof);
```

In Flame/Bonfire, set it on the component — `size` follows the cut, so culling
and hit boxes shrink with the roof:

```dart
final house = SpriteStackComponent(stack: walls, position: Vector2(320, 200));
add(house);

// On enter:
house.cut = const SliceCut(top: 19);
```

The slice sitting at the cut is dissolved with a 4×4 Bayer dither, so the pixel
grid stays intact instead of blending the whole prop. Bounds follow the cut.

## Baking and spinning

The software rasterizer is CPU-bound: it rebuilds a 1x art-pixel buffer on
every call. For scenery that does not change every frame, bake it once and
replay a `Picture`:

```dart
final baked = robot.bake(scale: 4, yaw: 0.6);
baked.draw(canvas, groundPosition); // one drawPicture
// ...
baked.dispose();
```

A prop that spins should use `SpriteStackTurntable`: it bakes one frame per yaw
bucket, lazily, and quantises the angle for you. Pixel art hides the stepping,
so 48–72 buckets read as continuous rotation:

```dart
final turntable = SpriteStackTurntable(tree, buckets: 72, scale: 4);
turntable.warmUp(); // pay the cost up front

// Per frame:
turntable.draw(canvas, groundPosition, yaw);
```

Loading the same asset once per prop is wasted work too — `SpriteStackCache`
shares the decoded strip (image, RGBA read-back and footprint mask):

```dart
final stacks = SpriteStackCache();
final tree = await stacks.load('sprites/tree.png', sliceCount: 43);
final house = await stacks.load('sprites/house.png', sliceCount: 29);
```

## Projected bounds

`size` used to ignore yaw, so a 45° prop drew ~40% wider than its hit box.
`boundsFor` returns the real projected `size` plus the `ground` point, which is
what the component uses for culling and hit testing:

```dart
final bounds = stack.boundsFor(yaw: yaw, scale: 4);
final rect = bounds.rectAt(groundPosition); // ready for Rect.contains
```

## Asset format

- One **horizontal strip** PNG, every slice the same size.
- **Ground slice first** (left), top slice last (right).
- `sliceCount` is required at load time: the PNG carries no metadata.
  `sliceWidth = imageWidth / sliceCount`, `sliceHeight = imageHeight`.
- Transparent background, hard edges, no anti-aliasing.
- The front of the prop points **+Y (down)** in the source images; when driving
  it from a velocity, `yaw = atan2(vy, vx) - pi / 2`.

The strip can come from any voxel editor (MagicaVoxel layer export works) or
from four orthographic views.

## Creating assets

### Four-view pipeline (recommended)

The authoring workflow and the carving tool come from
**[danielwh2/sprite-stacking](https://github.com/danielwh2/sprite-stacking)**
(MIT) — this package exists because that project proved how well the technique
reads in motion, and it implements the same math and the same strip format.

Draw or generate four orthographic views — **TOP, SIDE, FRONT, BACK** — on a
flat background, all at the same scale, then carve them into slices:

```bash
pip install pillow numpy

python3 skills/sprite-stacking/scripts/views_to_slices.py views.png slices.png \
  --slices 24 \
  --shade 0.2 \
  --preview check.png
```

Useful flags:

| Flag | What it does |
| --- | --- |
| `--slices N` | Slice count. 15–20 chunky, 26–44 detailed, 36–56 showcase |
| `--round` | Clips each slice to the ellipse its side/front spans describe (towers, pots, balloons) |
| `--side-nose left\|right` | Which way the SIDE view faces |
| `--order auto\|reading` | Detect the four views by proportions, or trust reading order |
| `--shade 0..1` | Bakes side shading into the slices |
| `--colours N` | One shared palette across the four views |
| `--preview check.png` | Writes a contact sheet so you can inspect the result |

The same folder ships `viewer.html`, a standalone turntable/exploded/slice-scan
viewer that opens any strip you drop on it — handy for checking an asset before
wiring it into the game.

### For AI agents (skill / MCP)

The upstream repository ships an **agent skill** that teaches an assistant the
whole authoring loop: pick a tier, produce or draw a valid four-view sheet,
carve it, inspect the result, then integrate the strip. It works with Claude
Code, Codex, Cursor, OpenCode, Gemini CLI and any agent that can read a
`SKILL.md`:

```bash
npx skills add danielwh2/sprite-stacking
```

Manual installation:

| Agent | Folder |
| --- | --- |
| Claude Code | `~/.claude/skills/` |
| Codex, Cursor, OpenCode, Gemini CLI, Pi | `~/.agents/skills/` |

The skill includes `SKILL.md`, `references/engines.md` (Web/Godot/Unity/Phaser
recipes), `scripts/views_to_slices.py` and `scripts/viewer.html`. Agents that
support MCP can expose that workflow as tools by wrapping the script; the
output format is exactly what `SpriteStack.load` consumes.

**Credit:** the four-view carving pipeline, the skill and the viewer are by
Daniel White ([danielwh2/sprite-stacking](https://github.com/danielwh2/sprite-stacking),
MIT). This package is the Flutter runtime for the strips that pipeline
produces.

## API

| Member | Meaning |
| --- | --- |
| `SpriteStack.load(path, sliceCount:)` | Loads a strip from a Flutter asset |
| `SpriteStack.decode(bytes, sliceCount:)` | Decodes a strip from memory |
| `SpriteStack.fromImage(image, sliceCount:)` | Wraps an already decoded `ui.Image` |
| `render(canvas, position:, yaw:, pitch:, scale:, spacing:, paint:, outline:, shadow:, pixelSnap:, outlineColor:, shadowColor:)` | Draws the stack |
| `boundsFor(yaw:, pitch:, scale:, spacing:, outline:, shadow:)` | Projected `size` + `ground` point |
| `bake(yaw:, pitch:, scale:, spacing:, ...)` | Renders once into a `BakedSpriteStack` |
| `SpriteStackTurntable(stack, buckets:, ...)` | Lazily baked yaw frames |
| `SpriteStackCache()` | Shares decoded stacks by asset path |
| `SpriteStackAnimation.load(path, sliceCount:, frameCount:, ...)` | Loads and plays a frame atlas |
| `SpriteStackAnimation` | Timing, loop, ping-pong, `play`/`stop`/`reset` |
| `AnimatedSpriteStackComponent(animation:, ...)` | Flame/Bonfire component with animation |
| `render(..., frame:)` / `SpriteStackPainter.frame` | Draws a specific atlas frame |
| `StackMotion(sway:, speed:, wave:, phase:, lean:)` | Per-slice sway/lean, no extra frames |
| `SliceCut(top:, bottom:)` | Hides slices above/below a frontier (roof cutaway) |
| `sliceWidth`, `sliceHeight`, `sliceSize`, `sliceCount` | Strip geometry |
| `heightFor(pitch:, spacing:)` | Rendered height in source pixels |
| `SpriteStack.defaultPitch` | `asin(0.75)` rad (~49°) |
| `dispose()` | Releases the decoded image |
| `SpriteStackPainter(...)` | `CustomPainter` for plain Flutter |
| `SpriteStackComponent(...)` | Flame/Bonfire `PositionComponent` |

`pitch` is clamped to `0..π/2` and its squash to `0.08..1`, so the stack never
collapses to nothing.

## Performance

- The software rasterizer renders into a 1x art-pixel buffer with nearest
  inverse sampling, then draws the opaque pixels grouped by color as integer
  squares. Cost scales with the prop's on-screen footprint, not the slice
  count, so 16-slice and 43-slice props cost about the same.
- The `fromImage` fallback keeps the old per-slice `drawImageRect` path (one
  draw per slice, plus four outline passes when enabled).
- If a scene gets heavy, bake it: `stack.bake(...)` replays a `Picture` with a
  single draw call, and `SpriteStackTurntable` bakes a whole rotation lazily.
- Cache the `SpriteStack` (and therefore the `ui.Image` and the RGBA buffer)
  per asset with `SpriteStackCache`, not per instance.
- `pixelSnap` (on by default) rounds the ground anchor to whole pixels, so a
  moving prop does not shimmer between pixel rows.
- Keep `scale` at an integer value and filtering at nearest for crisp pixels.
- Y-sort whole stacks by their ground point; never interleave slices of two
  props.

## Limitations

- **Painter's algorithm**: props that intersect each other cannot resolve per
  voxel. Two overlapping stacks draw in `priority` order.
- **No per-voxel lighting or reflections.** The built-in shadow is a flat
  projected ground shadow; shading has to be baked into the slices — the
  carving script does that with `--shade`.
- **Uniform slices only**: `sliceCount` must match the asset and divide its
  width exactly.
- A very large `scale` plus many slices costs fill rate; cache or pre-bake if
  it shows up in a profile.

## Example

```bash
cd example
flutter run -d chrome
```

The demo ships a Formula 1 car, a cottage and a leafy green tree carved
with the sprite-stacking skill (`example/sprites/car/slices.png`,
`example/sprites/house/slices.png` and `example/sprites/tree/slices.png`) plus
the generated `robot_stack.png`, with sliders for yaw, pitch, scale and spacing
plus toggles for auto-spin, the 1 px outline and the ground shadow.

## Contributing

Issues and pull requests are welcome at
[RafaelBarbosatec/flutter_sprite_stack](https://github.com/RafaelBarbosatec/flutter_sprite_stack).

## License

MIT — see [LICENSE](LICENSE).

The sprite-stacking authoring pipeline and skill referenced above are MIT,
Copyright (c) 2026 Daniel White.
