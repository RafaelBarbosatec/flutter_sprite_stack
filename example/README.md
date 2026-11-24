# flutter_sprite_stack_example

Demo app for the `flutter_sprite_stack` package.

## Screens

| Screen | What it shows |
| --- | --- |
| Turntable (`lib/main.dart`) | One prop at a time, drag to rotate, sliders for yaw / pitch / scale / spacing, mobile layout with a scrollable control panel. |
| Torch (`lib/torch_screen.dart`) | Animated frame atlas (`frames.png`). |
| F1 game (`lib/f1_game/`) | Bonfire-based race using stacked props. |

## Sprites

Each folder under `sprites/` is a self-contained model: a Python script builds a
voxel volume and writes `slices.png` (the strip the app loads), plus
`views.png`, `check.png` and `turntable.gif` proof sheets.

| Folder | Model | Slices | Slice size |
| --- | --- | --- | --- |
| `car/` | Formula 1 car | 15 | 38×72 |
| `house/` | Cottage with porch and fence | 29 | 48×48 |
| `tree/` | Leafy tree | 43 | 33×33 |
| `spaceship/` | Star-Wars-style starfighter (X-Wing) | 21 | 45×65 |
| `palmeira/` | Imperial palm (trunk, arching fronds, coconuts) | 26 | 25×25 |
| `torch/` | Animated torch frame atlas | 8 frames | 20×20 |

Regenerate a model with:

```bash
cd sprites/palmeira   # or car, house, tree, spaceship
python3 make_volume.py
```

Requires Python 3 with Pillow and NumPy. The palm script reads its export
helpers from `sprites/_stack_export.py`, which in turn uses the slicer helpers
from the sprite-stacking skill folder (`views_to_slices.py`); adjust `SLICER`
there if your skill lives elsewhere.

Remember to register any new strip in `pubspec.yaml` under `flutter: assets:`.
