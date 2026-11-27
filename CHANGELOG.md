## Unreleased

### Fixed

- **Props no longer drift across their own footprint when the camera orbits.**
  `SpriteStack.render` anchors a stack at the bottom-centre of the ground slice,
  and that edge is by definition the one facing the viewer: a scene that passed
  the projected ground point there re-read it as a different world spot for
  every camera yaw, so props slid by up to half their footprint depth (30–130 px
  in the diorama) and looked tilted against their collision boxes.
  `SpriteStack.render`, `boundsFor` and `bake` now take an `anchor`:
  `SpriteStackAnchor.bottomCentre` (the old behaviour, still the default) or
  `SpriteStackAnchor.footprintCentre`, which pivots on the centre of the opaque
  footprint. `SpriteStackScene` draws props with `footprintCentre`.
- `SpriteStackSceneObject.position` is now the centre of the ground footprint:
  `collisionBodyOf` centres the box there instead of half a slice depth forward,
  and `SpriteStackCollider.offset` is measured from that centre. The sprite and
  its collision proxy now coincide as the camera moves.
- `SpriteStack.footprintFor({frame})` exposes the union of the opaque art of a
  frame — the pivot the new anchor uses — and `SpriteStack.anchorOffset(...)`
  reports the screen-space shift it applies.
- `SpriteStackSceneObject.anchor` restores the old anchoring per prop when set
  to `SpriteStackAnchor.bottomCentre`.

### Collision

- `SpriteStackCollider` on `SpriteStackSceneObject`: a prop with a collider
  blocks movement, a prop without one is walk-through. The proxy is a box on
  the ground plane sized from `SpriteStackVolume.bounds` by default, so
  collision follows the geometry and not the sprite pixels, stays independent
  of the camera, and rotates with `object.yaw`. `padding`, `offset` and
  `height` tune it; `size` replaces the volume for stacks built with
  `SpriteStack.fromImage`, which have no raw pixels. The volume is built once
  per object and cached.
- `SpriteStackScene.move(position, delta:, radius:, ignore:, stepHeight:,
  maxSubsteps:)`: sweeps a ground circle in substeps no longer than `radius`,
  pushes it out along the contact normal and returns a `SpriteStackMoveResult`
  (`position`, `applied`, `hits`, `collided`). Sliding falls out of the normal
  resolution, and a broad-phase AABB reject skips the substeps in open space.
- `SpriteStackScene.blocks(...)` and `collisionBodies(...)` expose the same
  test for spawn checks and debug drawing; `SpriteStackCollisionBody` has
  `overlaps`, `resolve` and a world `bounds` AABB.
- `stepHeight` ignores bodies no taller than it, so a curb can be walked over.
- `scene.paintCollisionDebug(canvas, size, ...)` draws the resolved collision
  boxes over a painted frame — the same oriented box `move` uses, with a post at
  each corner for the height — plus an optional character circle. Bodies below
  `stepHeight` are drawn in a second colour. `scene.projectPoint(point, size)`
  is the underlying world-to-screen projection, useful for any overlay.
- New `CollisionScreen` example: drag a robot between the props, with switches
  to turn collision off and to show the collision boxes.

### Performance

- `SpriteStackScene` detail tiers: `outlineMinimumPixels` and
  `shadowMinimumPixels` skip the ink and the ground shadow for props that are
  only a few pixels across (each is a full sweep of the rasterizer's buffer,
  and at that size reads as a blot). `drawOutlines` / `drawShadows` switch a
  whole pass off. `SpriteStackSceneDetail` bundles them into `sharp`,
  `balanced`, `fast` and `minimal` presets, applied with `scene.applyDetail`.
  Measured on CI: 60 tiny props went from 20.45 ms to 17.90 ms median.
- `SpriteStackScene.cacheStillFrames`: records the frame once and replays a
  `Picture` while nothing that affects it changes. Moving scenes pay only a
  hash per frame; a still diorama skips the software rasterizer entirely.
  `stillFrameHits` counts the replays and `clearStillCache()` drops the frame.
  Measured on CI: a 13-prop still frame went from 2.27 ms to 0.06 ms median
  (about 38x).
- `SpriteStackQualityGovernor`: a pure Dart governor that picks a
  `SpriteStackSceneDetail` from frame gaps, judging windows (median plus share
  of long frames), waiting for the camera to move so a change does not pop,
  dropping two levels at once when frames crawl, and backing off exponentially
  after a level-up proves slow.
- Slice LOD: `SpriteStack.render(sliceStep:)` draws every `N`th cross-section,
  always keeping the ground slice and the top one, with each drawn slice still
  at its true height — so the outline of a prop does not move. A scene turns
  this on by itself through `sliceLod` (default `true`) whenever a prop is
  drawn below 1:1, keeping drawn slices within `sliceLodPixels` device pixels of
  each other (default `1`); `SpriteStackSceneObject.sliceStep` overrides it per
  prop. `scene.stats.slicesDrawn` / `slicesTotal` and `sliceLodSaving` report
  the saving.
- The benchmark now reports still frames with and without the cache, 60 tiny
  props with and without the detail tiers, and the same props with slice LOD
  off and on.
- `SpriteStackScene` ground painting skips cells that are fully behind the
  near plane or far enough outside the canvas that they cannot contribute a
  pixel, before building and clipping their polygon. `colorAt` is now called
  only for cells that survive that check. Measured 4.4x faster on a 400-cell
  floor.
- The software rasterizer restricts the inverse-mapping pass to each slice's
  tight opaque rectangle instead of the whole rotated slice, and the draw and
  outline passes only visit the region the body and shadow actually wrote.
  Measured 1.7x faster for a 13-prop scene.
- `SpriteStackSky` reuses its gradient paint while the size, horizon and sky
  are unchanged.
- Added `test/performance_test.dart` (`PERF=1`) and a CI step that reports the
  spread of three rounds, so perf changes are measured instead of guessed.

## 0.4.0

- `SpriteStackSceneObject` props are world-aligned by default: the scene
  derives each prop's sprite yaw and pitch from the camera-to-prop vector, so
  they follow the projected ground grid and read as fixed objects on the map
  even when the camera translates. Set `billboard: true` for a true billboard
  that keeps a fixed screen facing.
- **Engine-free orbit scene**: `SpriteStackScene`, `SpriteStackCamera.orbit`,
  `SpriteStackSceneObject`, `SpriteStackGround` and
  `SpriteStackSceneProjection`. The camera projects each prop's ground point
  with perspective, derives the visible yaw and pitch from the camera-to-prop
  vector, scales by depth and paints far to near. Props follow the projected
  ground grid while the camera orbits, and an optional near-clipped ground grid
  makes the rotation readable.
- `SpriteStackPoint` moved to its own library and gained vector operators
  (`+`, `-`, `*`, `dot`, `cross`, `length`, `normalized`). Volume, mesh and
  scene share the same world units: one unit per art pixel and per slice.
- `SpriteStackGround` can paint the floor: solid `fill`, alternating `checker`
  cells, a procedural `colorAt(x, y)` callback and `fadeColor`/`fadeDistance`
  for distance fade. Cells are projected and near-clipped like the grid;
  `step: 0` hides the lines.
- `SpriteStackSky`: vertical gradient backdrop anchored to the horizon, the
  vanishing line of the ground plane (`scene.horizonY(size)`). `top` blends to
  `horizon` above the line; `bottom` fills below it, so setting it to the
  ground's `fadeColor` dissolves the floor edge into the backdrop.
  `horizonFraction` pins the horizon for stylised backdrops. It takes
  precedence over the flat `SpriteStackScene.background`.
- `SpriteStackFollowCamera`: third-person follow with frame-rate independent
  exponential smoothing (`1 - exp(-rate * dt)`), shortest-arc yaw, a
  `lookAhead` point and an optional `deadZone`. The camera lags the subject on
  purpose: the camera-to-prop angle only changes if it does, which is what makes
  a turn readable on screen.
- Visibility counters: `SpriteStackScene.stats` reports `drawn`, `culled`,
  `behindCamera` and `tooSmall` after each `paint`, and
  `minimumProjectedPixels` (default `0.5`) skips props too small to show a
  pixel before they reach the rasterizer.
- `render(roll:, rollPivot:)`, `boundsFor(roll:, rollPivot:)`,
  `SpriteStackPainter.roll` and `bake(roll:)`: tilt the finished sprite in
  screen space, like the pitch squash. `roll` rotates the silhouette around a
  pivot `rollPivot` of the way up the body (`0` = the ground point, `0.5` = the
  middle); it is a 2D drawing effect, not a re-projection, so it does not reveal
  a new side of the prop. `boundsFor` returns the rotated envelope, keeping
  culling exact.
- Example: `FlightScreen`, a spaceship banking into its turns over the ground
  on a stadium-shaped track (two straights, two semicircular turns).
- Example: `ChaseCameraScreen`, a car lapping a stadium-shaped track with a lag
  slider and a live culling readout. The straights matter: the camera's yaw
  stays constant along them, so the ground grid and the scenery glide past in a
  straight line instead of sweeping, and the sweep is confined to the turns.
- Example: `OrbitSceneScreen`, a drag-to-orbit diorama over a ground grid.
- Docs: orbit scene section in the README and the runtime agent skill.
- **Breaking:** removed the `flame` dependency and the engine components
  `SpriteStackComponent` and `AnimatedSpriteStackComponent`. The package now
  only needs `Canvas`, so it cannot conflict with Flame, Bonfire or any other
  engine version. Wrap `SpriteStack.render` in your own component (see
  [Game Engines](docs/guide/flame.mdx)); `boundsFor` still provides the
  projected size for culling and hit boxes.
- The runtime agent skill no longer references engine components and shows the
  manual wrapper instead.
- `SpriteStack.toVolume()` reconstructs a prop's voxel volume from its
  cross-sections (`load`/`decode` only — `fromImage` has no raw pixels), with
  `frame` selection and an `alphaThreshold` (default `128`).
- `SpriteStackVolume`: occupancy grid (`x` column, `y` depth, `z` slice),
  `isSolid`, `solidVoxelCount` and tight `bounds` that trim the transparent
  padding around the prop. Can also be built from raw RGBA pixels or from an
  occupancy buffer.
- `SpriteStackMesher`: greedy meshing of the exposed faces into merged,
  axis-aligned quads. The mesh is **geometry only** (no colour, no UV) — the
  sprite stack keeps the drawing job; the mesh delimits the prop for a 3D scene.
  `SpriteStackQuad` exposes corners, normal, axis/direction and area.
- Docs: volume/mesh section in the README with measured counts for the example
  assets (car 830 quads, house 1 724, tree 1 435), plus the runtime agent skill.
- Added an **Animation & Cutaways** guide covering frame playback, dynamic RPM,
  and `SliceCut` cutaways (roof-off houses with a smooth dithered frontier).
- Example: `HelicopterScreen`, an animated AH-64 style attack helicopter with
  spinning main and tail rotors, RPM and hover controls, sized for phones.
- Example: the helicopter sprite stack with 24 slices and an 8-frame atlas,
  generated by `example/sprites/helicopter/make_frames.py`.
- **Fixed:** `SpriteStackSceneObject.scale` no longer shifts the prop's screen
  position. It is the art scale, so it changes how big a prop is drawn and
  never where its ground point lands; it used to be folded into the projection
  itself, which pushed a prop out from screen centre in proportion to its
  scale (a `scale: 1.4` prop landed 40% further out than the grid cell it
  stands on). Because that error changed with depth as the camera moved, props
  looked like they were sliding across the map on their own while a follow
  camera drove past them. `SpriteStackSceneProjection.position` is now the
  perspective projection of the ground point and nothing else, while
  `SpriteStackSceneProjection.scale` keeps applying the art scale to the drawn
  size.

## 0.3.0

- **Frame atlases**: `load`, `decode` and `fromImage` accept `frameCount`.
  Frames are horizontal strips stacked vertically, frame `0` on top;
  `sliceHeight` becomes the height of one row.
- `render(frame:)`, `SpriteStackPainter.frame` and `bake(frame:)` draw a
  specific atlas row. Out-of-range values are clamped.
- `SpriteStackAnimation`: frame timing, looping, ping-pong, `play`/`stop`/
  `reset`, `isFinished`, `onComplete` and `onFrame`.
- `AnimatedSpriteStackComponent` for Flame/Bonfire — same bounds, culling and
  Y sorting as `SpriteStackComponent`.
- `StackMotion`: per-slice sway and lean with a quadratic falloff from the
  ground, so trees, banners and kelp move without extra frames. Wired into
  `render`, `bake`, `SpriteStackPainter` and `SpriteStackComponent` (which
  advances the clock in `update`).
- `SliceCut`: hides slices above or below a continuous frontier, for roof-off
  cutaways (a hollow house that reveals the interior). The frontier slice is
  dissolved with a 4×4 Bayer dither, bounds follow the cut, and the component
  refreshes its size when the cut changes.
- The ground shadow (software rasterizer) is built per frame.
- Example: "Animated torch" screen with an 8-frame atlas (32 slices, flickering flame, sparks, firelight) generated by
  `example/sprites/torch/make_frames.py`.
- Docs: atlas layout in the asset-format guide and animation APIs.
- **Agent skills**, shipped in `skills/` per the
  [Dart package skills](https://dart.dev/ai/package-skills) convention and
  installable with `dart run skills@ get -p flutter_sprite_stack`:
  `flutter-sprite-stack-assets` (authoring, `validate_atlas.py`,
  `make_atlas.py`) and `flutter-sprite-stack-runtime` (render, components,
  animation, `StackMotion`, `SliceCut`, bake/turntable/cache).
- `skills_lint` in `dev_dependencies` plus `test/skills_test.dart`, so an
  invalid skill fails CI.

## 0.2.0

- `SpriteStack.boundsFor` reports the **projected** bounds (rotated footprint,
  outline and ground shadow) instead of the flat slice box.
- `SpriteStackComponent.size` and its ground anchor follow those bounds, so
  culling and hit boxes match the drawing at any yaw. Camera setters refresh
  them automatically.
- `pixelSnap` (default `true`) rounds the ground anchor — and the per-slice
  lifts of the fallback path — to whole pixels.
- `SpriteStack.bake` records a frame into a `BakedSpriteStack` that replays with
  one `drawPicture`.
- `SpriteStackTurntable` bakes one frame per yaw bucket, lazily, with `warmUp`.
- `SpriteStackCache` shares decoded stacks by asset path.
- README and docs gained a turntable GIF, a pub.dev screenshot and the new API.

## 0.1.0

- `SpriteStack`: load/decode a horizontal slice strip and render it with free
  yaw, pitch, scale and slice spacing.
- `SpriteStackPainter` for plain Flutter canvases.
- `SpriteStackComponent` for Flame/Bonfire, with size kept in sync for hit
  boxes and Y sorting.
- Offline-cached projection helpers (`squashFor`, `heightFor`).
- Example app with sliders and a generated demo asset.
- Example Bonfire game: drive the sprite-stacked F1 car around a circuit.
