---
title: Introduction
description: Render sprite-stacking props in Flutter with free turntable rotation from a horizontal strip of top-down cross-sections.
---

# flutter_sprite_stack

Render **sprite-stacking** props in Flutter with free turntable rotation.

A sprite stack is a set of horizontal cross-sections of a 3D shape. Drawing them
bottom-up — each one rotated and vertically squashed — produces a fake-3D
billboard you can spin in any direction. It is the same trick pixel-art games
have used since the 90s.

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
- **Cheap**: one texture, one `drawImageRect` per slice, nearest-neighbour filtering.
- **Pixel-art finish**: crisp 1 px ink outline and a projected ground shadow,
  matching the reference `viewer.html` look.
- **Tiny API**: load a strip, call `render`.
- **Flutter and Flame/Bonfire**: `CustomPainter` for plain canvases,
  `PositionComponent` for scenes with Y sorting and hit boxes.
- **No 3D engine, no shaders, no platform channels** — it is just `Canvas`.

## How it works

The renderer draws every slice from the ground up. For each slice it:

1. rotates the slice around its centre by `yaw`;
2. squashes it vertically by `sin(pitch)`;
3. lifts it by `spacing` source pixels;
4. draws it with nearest-neighbour filtering.

A 1 px outline is traced around the finished stack once, so the silhouette stays
clean instead of reading as individual slices, and the union of all slices is
projected as a ground shadow before the stack is drawn.
