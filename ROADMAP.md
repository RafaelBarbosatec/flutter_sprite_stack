# Roadmap

Direction for the 3D scene layer of `flutter_sprite_stack`, in build order.
Version numbers are cut when a milestone lands; until then everything lives under
`Unreleased` in the [changelog](CHANGELOG.md).

Guiding constraint: **the sprite stack stays the renderer.** The scene projects,
sorts and positions props; the volume/mesh is geometry for later collision, not a
second renderer.

## Now — a 3D environment worth looking at

Shipped:

- [x] `SpriteStack.toVolume()` + `SpriteStackVolume`: occupancy, tight bounds and
      pixel/slice/index access (`x` column, `y` depth, `z` height).
- [x] `SpriteStackMesher`: greedy-meshed exposed faces, geometry only (no colour,
      no UV).
- [x] `SpriteStackScene` + `SpriteStackCamera`: orbit camera (yaw/pitch/distance),
      perspective projection, per-object depth sorting, projected yaw
      (`object.yaw - camera.yaw`) and culling bounds.
- [x] `SpriteStackGround`: near-clipped grid on `z = 0`.
- [x] `OrbitSceneScreen` example: drag to orbit, auto-rotate, props keep their
      world facing.

Polish that makes the environment read as a place (still no gameplay):

- [ ] sky/backdrop beyond a flat `background` colour (vertical gradient, optional
      horizon) and a distance fade so the ground grid dissolves instead of
      ending in a hard edge.
- [ ] ground surface options: a repeated tile texture or coloured plane on
      `z = 0` instead of only lines.
- [ ] scene composition: groups/named objects and an easy way to place a
      "room", "island" or "street" as a reusable block.
- [ ] camera helpers: pan the `target`, clamp zoom/distance, and a
      `screenToGround(Offset, Size)` helper built on `SpriteStackCamera.basis`
      for click-to-place.
- [ ] a scene-level clock (`update(dt)`) so `StackMotion` and animated frames
      advance without every caller wiring its own ticker.

## Next (tentative) — walk around the environment, no collision

Goal: a controllable character moving on the ground plane with a camera that
follows it. Props are pass-through **on purpose**; this phase is about movement
feel and framing, not blockers.

- [ ] a controller that reads input, moves a `SpriteStackSceneObject` on `z = 0`
      and derives `object.yaw` from velocity
      (`atan2(vy, vx) - pi / 2`, the convention from the asset format).
- [ ] third-person follow camera: `target` tracks the avatar with smoothing;
      yaw/pitch/distance remain user-controlled.
- [ ] optional first-person toggle and an orbit-while-standing mode.
- [ ] soft world bounds so the character cannot walk off the ground.
- [ ] walk demo in `example/`: character stack moving between the props, with
      touch controls on mobile.
- [ ] frame/animation hooks for a walk cycle (`SpriteStackAnimation` +
      `object.frame`).

Acceptance: you can cross the diorama, walk around the house and between the
trees, and the camera keeps the character readable from any orbit angle.

## Later — collision and world interaction

Deferred until the environment and (if it happens) walk mode feel right.

- [ ] per-prop collision proxy from `SpriteStackVolume.bounds` or the merged
      quads (AABB first, capsule if needed). Collision uses the volume, never the
      sprite pixels.
- [ ] swept movement with sliding against props and a step height for curbs.
- [ ] walkable vs blocking authoring metadata, so the ground plane and props are
      classified once.
- [ ] camera occlusion: pull the camera in when a prop sits between it and the
      avatar.
- [ ] picking/placement: ray vs volume bounds.
- [ ] optional character/ground height sampling if the environment gets ramps.

## Explicit non-goals for now

- A per-pixel textured rasterizer or GPU pipeline. The scene calls
  `SpriteStack.render` per prop; it is not a textured-quad renderer.
- Dynamic lighting and real-time shadows beyond the baked slice shading and the
  flat ground shadow.
- Physics beyond walking on the ground plane.
- Multiplayer/networking.
