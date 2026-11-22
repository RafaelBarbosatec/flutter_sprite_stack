# Changelog

## 0.2.0

- `SpriteStack.boundsFor` returns the axis-aligned bounds of the rendered body,
  accounting for yaw, pitch, scale and slice spacing.
- `SpriteStackComponent.size` now follows those bounds and updates when `yaw`,
  `pitch`, `stackScale` or `spacing` change, so hit boxes and visibility
  culling match the drawn prop; `containsLocalPoint` uses the same bounds.
- `SpriteStack.bake` / `BakedSpriteStack` render a prop once into a single
  image for one-draw placement of static props.
- `SpriteStackCache` shares decoded strips between widgets and components.
- `pixelSnap` (default `true`) rounds the ground anchor and every slice lift to
  whole pixels in both the software rasterizer and the fallback slice path.
- Documentation previews: `doc/preview.png`, `doc/turntable.gif` and the
  `tool/make_preview.py` generator, plus a pub.dev screenshot entry.

## 0.1.0

- `SpriteStack`: load/decode a horizontal slice strip and render it with free
  yaw, pitch, scale and slice spacing.
- `SpriteStackPainter` for plain Flutter canvases.
- `SpriteStackComponent` for Flame/Bonfire, with size kept in sync for hit
  boxes and Y sorting.
- Offline-cached projection helpers (`squashFor`, `heightFor`).
- Example app with sliders and a generated demo asset.
- Example Bonfire game: drive the sprite-stacked F1 car around a circuit.
