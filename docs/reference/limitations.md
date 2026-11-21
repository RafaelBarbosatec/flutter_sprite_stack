---
title: Limitations
description: What flutter_sprite_stack does not do.
---

# Limitations

- **Painter's algorithm**: props that intersect each other cannot resolve per
  voxel. Two overlapping stacks draw in `priority` order.
- **No per-voxel lighting or reflections.** The built-in shadow is a flat
  projected ground shadow; shading has to be baked into the slices — the carving
  script does that with `--shade`.
- **Uniform slices only**: `sliceCount` must match the asset and divide its width
  exactly.
- A very large `scale` plus many slices costs fill rate; cache or pre-bake if it
  shows up in a profile.
