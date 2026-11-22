---
title: Performance
description: Draw budgets, outline cost, and when to bake sprites.
---

# Performance

- The software rasterizer renders into a 1x art-pixel buffer with nearest
  inverse sampling, then draws the opaque pixels grouped by color as integer
  squares. Cost scales with the prop's on-screen footprint, not the slice
  count, so 16-slice and 43-slice props cost about the same.
- The `fromImage` fallback keeps the old per-slice `drawImageRect` path (one
  draw per slice, plus four outline passes when enabled).
- Every `render` call rebuilds the art-pixel buffer, the occupancy mask and
  the per-color point lists, so a whole scene of props is CPU-bound. Bake what
  does not change: `stack.bake(...)` records a `Picture` and replaying it is a
  single `drawPicture`. `SpriteStackTurntable` does that per yaw bucket and
  `warmUp()` pays the cost up front.
- Cache the `SpriteStack` (and therefore the `ui.Image` and its RGBA buffer)
  per asset with `SpriteStackCache`, not per instance.
- `pixelSnap` rounds the ground anchor to whole pixels; keep it on for moving
  props, otherwise the upscaled grid shimmers.
- Keep `scale` at an integer value and filtering at nearest for crisp pixels.
- Y-sort whole stacks by their ground point; never interleave slices of two
  props.
