---
name: flutter-sprite-stack-runtime
description: Use the flutter_sprite_stack package in Flutter and any canvas-based engine — loading strips and frame atlases, drawing with CustomPainter, turning props with yaw, animating frames, adding wind/sway with StackMotion, opening roofs with SliceCut, choosing between live render, bake, turntable and cache, extracting the voxel volume and greedy mesh, and placing props in an orbit-camera 3D scene.
license: MIT
metadata:
  package: flutter_sprite_stack
  version: "0.4.0"
---

# Sprite-stack runtime

`flutter_sprite_stack` draws a horizontal strip of cross-sections as a solid
prop and lets you rotate it for free: `yaw` shears the slices, `pitch` squashes
them, and everything else is the same `sliceCount` draws.

```dart
final stack = await SpriteStack.load('assets/cottage.png', sliceCount: 48);
stack.render(canvas, position: groundPoint, yaw: 0.6, scale: 4);
```

## Pick the integration

| Situation | Use |
| --- | --- |
| one-off draw inside a `CustomPainter` | `stack.render(...)` |
| prop inside a game loop (Flame, Bonfire, custom) | call `stack.render(...)` from your own component |
| prop whose frames animate | `SpriteStackAnimation` + `render(frame:)` |
| scenery drawn every frame, never deforms | `stack.bake(...)` → `BakedSpriteStack` |
| prop spins constantly | `SpriteStackTurntable` |
| many instances of the same asset | `SpriteStackCache` |
| prop needs volume for a 3D scene or collision | `stack.toVolume()` + `SpriteStackMesher` |
| rotating 3D diorama over a ground plane | `SpriteStackScene` + `SpriteStackCamera` |

## CustomPainter

```dart
class StackPainter extends CustomPainter {
  StackPainter(this.stack, this.yaw);

  final SpriteStack stack;
  final double yaw;

  @override
  void paint(Canvas canvas, Size size) {
    stack.render(
      canvas,
      position: Offset(size.width / 2, size.height * 0.75),
      yaw: yaw,
      scale: 4,
    );
  }

  @override
  bool shouldRepaint(StackPainter old) =>
      old.stack != stack || old.yaw != yaw;
}
```

`position` is the **ground contact point**, not the top-left corner.

## Game engines (Flame, Bonfire, custom loop)

The package ships no engine component on purpose: it only needs a `Canvas`. In
Flame or Bonfire, wrap it in any component that exposes `render(Canvas)` and
size it from `boundsFor`:

```dart
class StackProp extends PositionComponent {
  StackProp({required this.stack, required Vector2 ground, this.yaw = 0})
      : super(position: ground, size: Vector2.zero()) {
    final b = stack.boundsFor(yaw: yaw, scale: 4);
    size = Vector2(b.size.width, b.size.height);
  }

  final SpriteStack stack;
  final double yaw;

  @override
  void render(Canvas canvas) {
    stack.render(canvas, position: Offset(size.x / 2, size.y), yaw: yaw, scale: 4);
  }
}
```

Use `priority` (or Bonfire's Y-sort) to place props behind/in front of actors.
For many props of the same asset, pre-render with `stack.bake(...)` or
`SpriteStackTurntable` and replay the `Picture` instead of rasterizing per
frame.

## Orbit scene (3D camera)

`SpriteStackScene` puts stacks in a world with an orbiting camera, still with no
engine dependency. It projects each ground point with perspective, subtracts the
camera yaw from the prop yaw, scales by depth and paints far to near.

```dart
final scene = SpriteStackScene(
  camera: SpriteStackCamera.orbit(yaw: 0.8, pitch: 0.6, distance: 900),
  zoom: 2.4,                     // art pixels per world unit at the target
  sky: const SpriteStackSky(
    top: Color(0xFF070D16),
    horizon: Color(0xFF27435E),
    bottom: Color(0xFF16232F),   // match the ground's fadeColor
  ),
  ground: const SpriteStackGround(extent: 700, step: 70),
  objects: [
    SpriteStackSceneObject(
      stack: house,
      position: const SpriteStackPoint(-230, -40, 0), // z is up
      yaw: 0.5,
    ),
  ],
);

// per frame, from a Ticker/CustomPainter
scene.camera.yaw += dt * 0.2;
scene.paint(canvas, size);
```

World units are art pixels, so a 48 px wide house is 48 units wide. `zoom` is
the scale at the camera's target plane; closer props grow. `pitch` is clamped
just short of straight down.

- `scene.projectObject(object, size)` → `position`, `depth`, `scale`, `yaw`,
  `bounds`; use `isVisibleIn(size)` to cull.
- `SpriteStackSky` paints a gradient backdrop anchored to the ground plane's
  vanishing line (`scene.horizonY(size)`): `top` → `horizon` above the line,
  `bottom` below it. It follows the camera pitch, so orbiting keeps it still.
  Set `bottom` to the ground's `fadeColor` to hide the edge of the floor;
  `horizonFraction` pins the line for stylised backdrops. It wins over the flat
  `background`.
- `SpriteStackGround` paints the floor as near-clipped projected cells: `fill`,
  `checker` (alternates by `(ix + iy)`), `colorAt(x, y)` for procedural floors,
  and `fadeColor`/`fadeDistance` to blend into the horizon. `step: 0` hides the
  grid lines. Cells are flat colours, not textures.
- `SpriteStackFollowCamera` follows a subject: `target` chases a point
  `lookAhead` units ahead, `yaw` follows the subject's facing on the shortest
  arc, both with `1 - exp(-rate * dt)`. The lag is what makes a turn visible:
  the prop is drawn at `object.yaw - camera.yaw`, so a camera that copies the
  yaw instantly shows a sprite that never rotates.
- `scene.stats` counts `drawn` / `culled` / `behindCamera` / `tooSmall` after
  each paint; `minimumProjectedPixels` (default `0.5`) culls sub-pixel props
  before the rasterizer. No occlusion culling.
- Sorting is **per object** (painter's algorithm); intersecting props cannot
  resolve per pixel.
- The volume/mesh is not drawn — pair it with `toVolume()` for collision or
  exact bounds.
- Update `object.time` yourself when using `StackMotion`; the scene has no clock.

## Animation (frame atlas)

A frame atlas is several strips stacked vertically; `frameCount` says how many.

```dart
final torch = await SpriteStackAnimation.load(
  'assets/torch.png',
  sliceCount: 32,
  frameCount: 8,
  frameDuration: 0.12,
  loop: true,
);

// In your update loop:
torch.update(dt);

// In your draw call:
torch.stack.render(canvas, position: ground, yaw: yaw, scale: 4, frame: torch.frame);
```

Rendering cost is unchanged: `sliceCount` draws per frame.

```dart
torch.pingPong = true;         // 0→4→0 instead of wrapping
torch.onComplete = () { … };   // called once when loop == false finishes
torch.onFrame = (frame) { … }; // one call per update that changes frame
torch.play(); torch.stop(); torch.reset();
```

## Motion (sway, lean — no extra frames)

```dart
stack.render(
  canvas,
  position: ground,
  yaw: yaw,
  scale: 4,
  motion: const StackMotion(sway: 2.5, speed: 1.8, wave: 0.7),
  time: elapsedSeconds,
);
```

`StackMotion` offsets each slice by `sin(time · speed − z · wave + phase) · sway
· (z / (n−1))²`. The square pins slice 0 to the ground and moves the tip by
exactly `sway` source pixels. `lean` is a constant bend for wind direction.
Advance `time` yourself in your game loop.

## Cutaway (`SliceCut`) — roof off, interior visible

```dart
// Keep slices 0..29, drop the roof.
stack.render(canvas, position: ground, yaw: yaw, scale: 4,
  cut: const SliceCut(top: 30));

// Animate the roof off when the player walks in:
final top = 30 + 18 * (1 - roofProgress);
stack.render(..., cut: SliceCut(top: top));
```

`top` and `bottom` are in **slices**, and may be fractional. The slice sitting
exactly on the frontier dissolves with a 4×4 Bayer dither, so the pixel grid
survives. `boundsFor(cut:)` shrinks with the cut, so culling stays correct.
The default `top: double.infinity` keeps everything.

**Draw order matters.** A single stack cannot put the player *between* the front
and back walls. What works with one asset:

1. draw the house first, cut the roof;
2. draw the player after — it draws over the remaining cross-sections, reading
   as "inside" in a top-down/dollhouse camera.

If the front wall must occlude the player, split the cottage into two assets
(back walls + front walls) and draw: back, player, front.

## Bake, turntable, cache

```dart
final baked = stack.bake(yaw: 0.6, scale: 4);   // one drawPicture
baked.draw(canvas, groundPoint);
baked.dispose();                                 // required

final turntable = SpriteStackTurntable(stack, buckets: 72, scale: 4);
turntable.warmUp();                              // bake before gameplay
turntable.draw(canvas, groundPoint, yaw);
turntable.dispose();

final stacks = SpriteStackCache.instance;
final a = await stacks.load('assets/crate.png', sliceCount: 20);
final b = await stacks.load('assets/crate.png', sliceCount: 20); // same object
```

Bake kills per-slice work but **freezes** camera, frame and motion: a baked prop
cannot sway, animate or change `yaw` continuously. Use it for scenery; use
`SpriteStackTurntable` when the scenery rotates.

## Bounds and hit testing

Never size a prop as `sliceWidth × sliceCount × spacing`: that ignores `yaw`,
`pitch`, the outline and the shadow.

```dart
final bounds = stack.boundsFor(yaw: yaw, scale: 4, cut: cut);
final rect = bounds.rectAt(groundPoint);  // place/hit-test with this
```

## Volume and mesh (3D groundwork)

The slices are cross-sections, so the strip also describes the prop's volume.
Use it to size, cull, collide and depth-sort props in a 3D scene. The mesh is
**not** drawn: the sprite stack keeps every pixel.

```dart
final volume = stack.toVolume();                    // load/decode only
final mesh = const SpriteStackMesher().build(volume);

volume.width; volume.depth; volume.height;          // grid, in art pixels
volume.isSolid(x, y, z);                            // out of range = false
volume.solidVoxelCount;
volume.bounds;                                      // tight box, or null
mesh.quadCount; mesh.triangleCount;
mesh.quads.first.corners;                           // voxel units, CCW from outside
mesh.quads.first.normal;
```

`x` is the slice column, `y` the slice row (depth) and `z` the slice index.
`alphaThreshold` (default `128`) decides solid vs empty; a volume is built per
frame. Stacks built with `fromImage` throw `StateError` because they keep no raw
pixels.

Faces have no colour or UV on purpose. Greedy meshing merges coplanar exposed
faces and skips faces between two solid voxels, so a solid `2×2×2` block is 6
quads (12 triangles) instead of 96. Build the volume and mesh once per asset and
frame — never every game frame.

## Pitfalls

| Symptom | Cause |
| --- | --- |
| prop is offset from where you placed it | `position` is the ground point, not top-left |
| blurry edges | non-integer `scale` with `pixelSnap: true`; use 2, 3, 4… |
| prop flickers behind other props | `priority` / Y-sort not set from the ground point |
| animation runs at fixed speed regardless of movement | drive `frame` from your own phase instead of `frameDuration` |
| baked prop never animates | `bake()` freezes frame, yaw and motion — use live render |
| bounds wrong after changing `cut` | recompute `boundsFor(cut: …)` whenever the cut moves |
| memory grows per instance | share one `SpriteStack` via `SpriteStackCache`, do not `load` per entity |
| `Picture` leaked | `BakedSpriteStack.dispose()` / `SpriteStackTurntable.dispose()` |

## More

- `references/api.md` — every parameter of every public API.
- `references/performance.md` — draw counts, memory, when to bake.
