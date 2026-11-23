# Performance

Numbers here are structural (what the code does), not benchmark results. Measure
on your target device before optimising.

## What each path costs

### Live render, software rasterizer (default after `SpriteStack.load`)

`render()` composes the rotated stack into an RGBA buffer in Dart:

1. allocate `cw × ch × 4` bytes plus an alpha mask, **per call**;
2. loop every destination pixel of every slice, sampling the source strip;
3. group the result by color and emit one `Canvas.drawPoints` per distinct
   color.

So the per-frame cost is roughly

```text
pixels touched ≈ scale² × (sliceWidth × sliceHeight + lift) × sliceCount
draw calls     = number of distinct RGBA colors in the composed frame
```

Consequences:

- Big `scale` is expensive: 4× scale touches 16× the pixels.
- A shaded sprite with hundreds of colors costs hundreds of draw calls; a flat
  16-color palette costs 16. This is the single biggest lever.
- Calling `render()` twice per frame doubles all of it. Render once.

### Live render, slice path

Forced by passing `paint:` to `render`, and used automatically for stacks built
with `SpriteStack.fromImage`. Cost:

```text
draw calls = sliceCount + (outline ? 1 : 0) + (shadow ? 1 : 0)
```

No Dart-side pixel loop, so it is usually cheaper than the software path when
the palette is large — but rotation is filtered by the canvas, not resampled by
hand, so edges are softer.

### Baked

`stack.bake(...)` records the composed result once into a `ui.Picture`.
Replaying it is a single `drawPicture`: no allocation, no pixel loop, no palette
grouping. It freezes `yaw`, `pitch`, `frame`, `motion` and `cut`.

Use it for scenery that never changes. Do not use it for anything that rotates
or animates every frame.

### Turntable

`SpriteStackTurntable(stack, buckets: N)` bakes one picture per yaw bucket:
`N` pictures, each the size of the projected bounds. With 72 buckets a cottage
at 4× scale (~232×260 px) is ~72 × 240 KB ≈ 17 MB of GPU-backed pictures — fine
for one hero prop, too much for a forest.

Cheaper alternative for many rotating props: live render at a low scale, or
bake fewer buckets (24 is usually enough for pixel art that is not the focus).

## Memory

| What | Bytes |
| --- | --- |
| one decoded `SpriteStack` | `width × height × 4` |
| bakes | `buckets × bounds.width × bounds.height × 4` (approximate, picture-backed) |
| render scratch | `≈ (diagonal + lift)² × 4` per call, freed after the frame |

Shared instances are essential: 200 entities that each `SpriteStack.load` the
same PNG hold 200 decoded images. `SpriteStackCache` keeps one.

## Checklist before shipping

- [ ] one `SpriteStack` per asset, shared by every entity (`SpriteStackCache`)
- [ ] integer `scale` (`2`, `3`, `4`) — halves the resampling and keeps pixels crisp
- [ ] `render()` called once per frame per component
- [ ] static scenery baked; rotating scenery either turntabled or rendered live
- [ ] `dispose()` on `SpriteStack`, `BakedSpriteStack` and `SpriteStackTurntable`
      when the owning screen is torn down
- [ ] `motion` used instead of extra atlas frames for sway/lean
- [ ] frame atlases kept small: memory grows linearly with `frameCount`
- [ ] culling uses `boundsFor(...)`, not `sliceWidth × sliceCount`
