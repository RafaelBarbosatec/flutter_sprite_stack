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
- If a scene gets heavy, disable outlines or bake 16 directions ahead of time
  and use a normal sprite sheet instead.
- Cache the `SpriteStack` (and therefore the `ui.Image`) per asset, not per
  instance.
- Keep `scale` at an integer value and filtering at nearest for crisp pixels.
- Y-sort whole stacks by their ground point; never interleave slices of two
  props.
