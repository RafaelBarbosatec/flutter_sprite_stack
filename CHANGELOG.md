# Changelog

## 0.2.0

- `SpriteStack.boundsFor` returns the axis-aligned bounds of the rendered prop,
  accounting for yaw, pitch, scale and slice spacing.
- `SpriteStackComponent.size` now follows those bounds, so hit boxes and
  visibility culling match the drawn prop; `containsLocalPoint` uses the same
  bounds and supports `Anchor.bottomCenter`.
- `SpriteStack.bake` / `BakedSpriteStack` render a prop once into a single
  image for one-draw placement of static props.
- `SpriteStackCache` shares decoded strips between widgets and components.
- `pixelSnap` (default `true`) rounds the ground point and every slice lift to
  whole pixels. Pass `false` for sub-pixel smooth motion.
- Documentation previews: `doc/preview.png`, `doc/turntable.gif` and the
  `tool/make_preview.py` generator.

## 0.1.0

- `SpriteStack`: load/decode a horizontal slice strip and render it with free
  yaw, pitch, scale and slice spacing.
- `SpriteStackPainter` for plain Flutter canvases.
- `SpriteStackComponent` for Flame/Bonfire, with size kept in sync for hit
  boxes and Y sorting.
- Offline-cached projection helpers (`squashFor`, `heightFor`).
- Example app with sliders and a generated demo asset.
