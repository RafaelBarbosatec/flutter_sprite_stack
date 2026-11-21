---
title: Performance
description: Draw budgets, outline cost, and when to bake sprites.
---

# Performance

- One `drawImageRect` per slice, from a single decoded texture. The outline pass
  draws the stack four extra times (4-connected ink ring), so a 24-slice prop
  costs 24 draws with `outline: false` and ~120 with `outline: true`.
- A hundred 24-slice props is ~2.4k draws without outlines — fine for Flame; if a
  scene gets heavy, disable outlines or bake 16 directions ahead of time and use
  a normal sprite sheet instead.
- Cache the `SpriteStack` (and therefore the `ui.Image`) per asset, not per
  instance.
- Keep `scale` at an integer value and filtering at nearest for crisp pixels.
- Y-sort whole stacks by their ground point; never interleave slices of two
  props.
