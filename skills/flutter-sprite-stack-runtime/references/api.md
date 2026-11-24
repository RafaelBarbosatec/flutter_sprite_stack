# API reference (0.4.0)

Everything is exported from `package:flutter_sprite_stack/flutter_sprite_stack.dart`.

## SpriteStack

| Member | Meaning |
| --- | --- |
| `SpriteStack.load(assetPath, {required sliceCount, frameCount = 1})` | Decodes a strip or atlas from a Flutter asset |
| `SpriteStack.decode(bytes, {required sliceCount, frameCount = 1})` | Same, from memory |
| `sliceWidth`, `sliceHeight`, `sliceCount`, `frameCount` | Cell geometry |
| `sliceSize` | `Size(sliceWidth, sliceHeight)` |
| `heightFor({pitch, spacing})` | Stack height in source pixels |
| `SpriteStack.squashFor(pitch)` | Vertical squash for a pitch angle |
| `SpriteStack.defaultPitch` | `0.848` rad — the reference viewer's 3/4 camera |
| `render(...)` | Draw one frame (see below) |
| `boundsFor(...)` | Projected `SpriteStackBounds` |
| `bake(...)` | Record into a `BakedSpriteStack` |
| `dispose()` | Releases the decoded `ui.Image` |

### render

```dart
void render(
  Canvas canvas, {
  required Offset position,   // ground contact point
  double yaw = 0,             // radians around Y
  double pitch = defaultPitch,// 0 = edge-on, pi/2 = top-down
  double scale = 1,           // keep it an integer for crisp pixels
  double spacing = 1,         // lift between slices, source pixels
  int frame = 0,              // atlas row, clamped
  StackMotion? motion,
  double time = 0,            // clock for motion, seconds
  SliceCut? cut,
  Paint? paint,               // forces the slice path (skips the software rasterizer)
  bool outline = true,        // crisp 1 px outer ring
  bool shadow = true,         // projected ground shadow
  bool pixelSnap = true,
  Color outlineColor = const Color(0xFF181C24),
  Color shadowColor = const Color(0xFFBAC6D4),
})
```

### boundsFor

```dart
SpriteStackBounds boundsFor({
  double yaw = 0,
  double pitch = defaultPitch,
  double scale = 1,
  double spacing = 1,
  SliceCut? cut,
  bool outline = true,
  bool shadow = true,
})
```

`size` is the full projected size; `ground` is where the ground point sits
inside it. `rectAt(groundPosition)` places the rect in world space,
`localRect` is it relative to the ground point.

## SpriteStackAnimation

```dart
SpriteStackAnimation.load(path, {
  required int sliceCount,
  required int frameCount,
  double frameDuration = 0.1,
  bool loop = true,
  bool pingPong = false,
  bool autoPlay = true,
})

SpriteStackAnimation(stack, {
  frameDuration = 0.1, loop = true, pingPong = false,
  onComplete, onFrame, startFrame = 0,
})
```

| Member | Meaning |
| --- | --- |
| `update(dt)` | Advance; no-op when stopped/finished |
| `frame` | Visible frame index (handles loop and ping-pong) |
| `elapsed` | Seconds of playback |
| `isPlaying`, `isFinished` | Playback state |
| `play()`, `stop()`, `reset()` | `reset()` rewinds **and pauses**; call `play()` after |
| `onComplete` | Once, when a non-looping animation reaches the last frame |
| `onFrame(int)` | After each update that changes the visible frame |

A single `update` with a long `dt` reports only the frame it lands on; skipped
frames do not fire `onFrame`.

## StackMotion

```dart
const StackMotion({
  double sway = 0,          // amplitude at the tip, source pixels
  double speed = 1.6,       // rad/s
  double wave = 0.8,        // phase lag per slice, rad
  double phase = 0,         // initial phase, rad
  Offset lean = Offset.zero // constant bend at the tip
})
```

`offsetAt(slice, sliceCount, time)` returns
`sin(time · speed − slice · wave + phase) · sway · (z/(n−1))² + lean · (z/(n−1))²`.
Slice 0 never moves. `isEmpty` is true when `sway == 0 && lean == Offset.zero`.
The software rasterizer rounds the offset to whole source pixels.

## SliceCut

```dart
const SliceCut({double top = double.infinity, double bottom = 0})
```

| Member | Meaning |
| --- | --- |
| `top` | Hide slices at or above this frontier (fractional allowed) |
| `bottom` | Hide slices below this frontier |
| `isActive` | Whether anything is hidden |
| `isVisible(slice)` / `visibilityAt(slice)` | Per-slice visibility `0..1` |
| `visibleSliceCount(sliceCount)` | Used by `boundsFor` |

A slice straddling the frontier is drawn with a 4×4 Bayer dither. Both frontiers
are clamped by the renderer, so animating `top` past the ends is safe.

## BakedSpriteStack

| Member | Meaning |
| --- | --- |
| `picture` | Recorded `ui.Picture` |
| `bounds`, `yaw`, `frame` | What was baked |
| `draw(canvas, groundPosition)` | Replays at the ground point |
| `dispose()` | Disposes the picture; drawing afterwards asserts |
| `isDisposed` | Guard for callers |

`bake()` accepts `yaw`, `pitch`, `scale`, `spacing`, `frame`, `motion`, `time`,
`cut`, `pixelSnap`, `outline`, `shadow`, `outlineColor`, `shadowColor`. It
freezes all of them.

## SpriteStackTurntable

```dart
SpriteStackTurntable(stack, {
  int buckets = 72, double pitch = SpriteStack.defaultPitch,
  double scale = 1, double spacing = 1,
  bool outline = true, bool shadow = true,
  Color outlineColor, Color shadowColor, bool pixelSnap = true,
})
```

| Member | Meaning |
| --- | --- |
| `yawStep` | `2π / buckets` |
| `bucketFor(yaw)` | Nearest bucket index |
| `frameAt(bucket)` / `frameFor(yaw)` | Bakes lazily on first use |
| `bakedFrameCount` | How many are cached |
| `warmUp()` | Bake all buckets up front |
| `draw(canvas, groundPosition, yaw)` | Draw the nearest bucket |
| `dispose()` | Dispose every baked frame |

Baking is quantised in Y only, so the prop jumps by `yawStep`; with 72 buckets
that is 5° and invisible on pixel art.

## SpriteStackCache

| Member | Meaning |
| --- | --- |
| `SpriteStackCache()` / `.instance` | New cache / process-wide default |
| `load(path, {required sliceCount})` | Decodes once; concurrent calls share one load |
| `contains(path)` / `operator [](path)` | Inspect without loading |
| `evict(path)` | Dispose one entry (do not evict while rendering) |
| `clear()` | Dispose everything |
| `length` | Cached entries |

The default loader ignores `frameCount`; if you cache an atlas, load it
yourself or use a custom `loader`.

## Draw counts

| Path | Per frame |
| --- | --- |
| software rasterizer (default for `load`/`decode`) | composes an RGBA buffer in Dart, then **one `drawPoints` per distinct color** |
| slice path (`paint != null`, or stacks built with `fromImage`) | 1 outline + 1 shadow + `sliceCount` `drawImageRect` |
| `BakedSpriteStack.draw` | 1 `drawPicture` |
| `SpriteStackTurntable.draw` | 1 `drawPicture` |

The software path is what keeps rotation crisp, but its cost tracks the palette,
not the slice count. See `performance.md` before putting hundreds of stacks on
screen.
