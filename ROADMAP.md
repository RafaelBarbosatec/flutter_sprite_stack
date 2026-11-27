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
      perspective projection, per-object depth sorting, projected yaw and pitch
      from the camera-to-prop vector (world-aligned by default, `billboard`
      opt-in for a fixed screen facing) and culling bounds.
- [x] `SpriteStackGround`: near-clipped grid on `z = 0`.
- [x] `OrbitSceneScreen` example: drag to orbit, auto-rotate, props follow the
      projected ground grid.

Polish that makes the environment read as a place (still no gameplay):

- [x] sky/backdrop beyond a flat `background` colour: `SpriteStackSky` gradient
      anchored to the camera's horizon, with a `horizonFraction` override, plus
      `scene.horizonY(size)` for anything else that needs the line.
- [x] ground surface options: solid `fill`, alternating `checker` cells,
      procedural `colorAt(x, y)` and `fadeColor`/`fadeDistance` for distance
      fade (`step: 0` hides the lines).
- [ ] textured ground: a tiled image needs subdivision or `drawVertices` for a
      correct perspective mapping; deferred until a flat-colored floor is not
      enough.
- [x] screen-space `roll` in the renderer (`render(roll:, rollPivot:)`,
      `boundsFor`, `bake`, painter, turntable) for banking and leaning props.
      A true 3D roll needs the volume re-sliced along tilted planes — out of
      scope; `yaw` is what reveals another side.
- [x] visibility counters (`scene.stats`) and sub-pixel culling
      (`minimumProjectedPixels`); occlusion culling still needs a depth buffer.
- [ ] scene composition: groups/named objects and an easy way to place a
      "room", "island" or "street" as a reusable block.
- [ ] camera helpers: pan the `target`, clamp zoom/distance, and a
      `screenToGround(Offset, Size)` helper built on `SpriteStackCamera.basis`
      for click-to-place.
- [ ] a scene-level clock (`update(dt)`) so `StackMotion` and animated frames
      advance without every caller wiring its own ticker.

## Next (tentative) — walk around the environment

Goal: a controllable character moving on the ground plane with a camera that
follows it. Collision landed ahead of schedule (see below), so the walk demo
ships with it and a switch to turn it off.

- [x] a controller that moves a `SpriteStackSceneObject` on `z = 0` and derives
      `object.yaw` from velocity (`atan2(vy, vx) - pi / 2`, the convention from
      the asset format) — see the chase and flight demos.
- [x] third-person follow camera: `SpriteStackFollowCamera` tracks the subject
      with exponential smoothing (position + shortest-arc yaw + look-ahead);
      distance/pitch remain user-controlled.
- [ ] optional first-person toggle and an orbit-while-standing mode.
- [ ] soft world bounds so the character cannot walk off the ground.
- [x] walk demo in `example/`: `CollisionScreen` drags a robot between the
      props, with a collision on/off switch.
- [ ] frame/animation hooks for a walk cycle (`SpriteStackAnimation` +
      `object.frame`).

Acceptance: you can cross the diorama, walk around the house and between the
trees, and the camera keeps the character readable from any orbit angle.

## Shipped — collision and world interaction

- [x] per-prop collision proxy from `SpriteStackVolume.bounds`: a yaw-rotated
      box on the ground plane (`SpriteStackCollider`), with an explicit
      `size`/`offset`/`height` for stacks without raw pixels.
- [x] swept movement with sliding: `SpriteStackScene.move` substeps the move
      and pushes the character out along the contact normal, so a diagonal move
      into a wall slides instead of stopping.
- [x] `stepHeight` to walk over short props, `blocks()` for overlap queries and
      `scene.stats`-style coverage through `SpriteStackMoveResult.hits`.
- [x] blocking vs walk-through authoring: a prop blocks iff it has a
      `collider`.
- [ ] true step-up onto props (the character rises to the prop surface) rather
      than only ignoring short bodies.
- [ ] camera occlusion: pull the camera in when a prop sits between it and the
      avatar.
- [ ] picking/placement: ray vs volume bounds.
- [ ] optional character/ground height sampling if the environment gets ramps.

## Later — beyond the ground plane

- [ ] textured ground and ramps, which need height sampling and a real surface.
- [ ] camera collision and first-person mode.
- [ ] scene composition blocks ("room", "island", "street") with baked colliders.

## Explicit non-goals for now

- A per-pixel textured rasterizer or GPU pipeline. The scene calls
  `SpriteStack.render` per prop; it is not a textured-quad renderer.
- Dynamic lighting and real-time shadows beyond the baked slice shading and the
  flat ground shadow.
- Physics beyond walking on the ground plane.
- Multiplayer/networking.
