---
name: flutter-sprite-stack-runtime
description: Use the flutter_sprite_stack package in Flutter and any canvas-based engine — loading strips and frame atlases, drawing with CustomPainter, turning props with yaw, animating frames, adding wind/sway with StackMotion, opening roofs with SliceCut, and choosing between live render, bake, turntable and cache.
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
