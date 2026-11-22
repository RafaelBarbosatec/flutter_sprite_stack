# Changelog

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
