# Asset format

Everything the loader enforces, and the numbers behind it.

## Dimensions

```text
sliceCount  = imageWidth  / sliceWidth
frameCount  = imageHeight / sliceHeight
```

`SpriteStack.decode` throws unless **both** divisions are exact:

```text
Image 448x80 does not split into 14 slices x 5 frames
```

So for a 224×80 atlas with 14 slices and 5 frames: `sliceWidth = 16`,
`sliceHeight = 16`. The cell is square here, but it does not have to be — only
the divisions matter.

## Slice order

- Index **0 is the ground contact** and is drawn first, at the bottom.
- Index `sliceCount - 1` is the top of the prop.
- Within a frame, slices go left to right.
- Frames go top to bottom, frame `0` first.

The renderer does not reorder, rotate or re-centre anything: what you pack is
what gets drawn.

## Memory

Decoded RGBA is `width × height × 4` bytes, held once per `SpriteStack`:

| Asset | Decoded | Notes |
| --- | --- | --- |
| 24 slices × 32×32, 1 frame | 96 KB | demo robot |
| 14 slices × 16×16, 5 frames | 70 KB | demo torch |
| 15 slices × 38×72, 1 frame | 160 KB | demo car (non-square cells) |
| 48 slices × 29×48, 1 frame | 261 KB | demo cottage |
| 24 slices × 64×64, 8 frames | 3.0 MB | the point where you want `SpriteStackCache` or `bake()` |

Atlas frames are cheap in **draws** (still `sliceCount` per frame) and expensive
in **memory** (linear in `frameCount`). Prefer `StackMotion` when the silhouette
does not change.

## Transparency

The renderer composites the whole cell, so:

- background alpha must be `0`
- a pixel is either fully painted or absent; semi-transparent pixels show as a
  halo around pixel art
- an asset with **no** transparent pixel at all is almost always an opaque
  background mistake

## Naming and layout in a Flutter app

```text
assets/
  props/
    crate.png            # 20 slices
    cottage.png          # 48 slices
    torch.png            # 14 slices × 5 frames
```

```yaml
flutter:
  assets:
    - assets/props/
```

Keeping `sliceCount` next to the asset in code (or in a small registry map) is
worth it: the number is not stored in the PNG, and a wrong number either throws
(non-divisible width) or silently renders the prop as a different shape
(divisible but wrong).

```dart
class Props {
  static const cottage = (path: 'assets/props/cottage.png', slices: 48);
  static const torch = (path: 'assets/props/torch.png', slices: 14, frames: 5);
}
```

## What the validator checks

| Check | Severity | Why |
| --- | --- | --- |
| width ÷ slices, height ÷ frames | error | loader throws |
| no transparent pixel anywhere | error | opaque background |
| blank frame | error | nothing to draw |
| empty slices below the first painted one | error | prop floats above ground/shadow |
| empty slices between painted ones | warning | visible gap, or a real hollow detail |
| empty slices above the last painted one | warning | wasted memory / headroom |
| lateral drift of slice content | warning | per-slice cropping causes wobble |
| semi-transparent pixels > 2% | warning | halo around pixel art |
| frame silhouette widths differ by > 1 px | warning | pivot or camera changed between frames |

## Generating frames

`example/sprites/torch/make_frames.py` is a working example: it models the
torch procedurally and writes five 224×16 strips with identical canvases, then
`make_atlas.py` packs them. Copy that shape for any procedural prop:

1. one function `frame(t) -> RGBA buffer` of the same size
2. loop over the frame count
3. write each frame with `png_rw.write_png`
4. pack with `make_atlas.py --slices N`
5. validate with `validate_atlas.py --slices N --frames M`
