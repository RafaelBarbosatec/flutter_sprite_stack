---
title: Creating Assets
description: Carve four orthographic views into a slice strip with the sprite-stacking skill.
---

# Creating Assets

## Four-view pipeline (recommended)

The authoring workflow and carving tool come from
[danielwh2/sprite-stacking](https://github.com/danielwh2/sprite-stacking)
(MIT). This package implements the same math and the same strip format.

Draw or generate four orthographic views — **TOP, SIDE, FRONT, BACK** — on a
flat background, all at the same scale, then carve them into slices:

```bash
pip install pillow numpy

python3 skills/sprite-stacking/scripts/views_to_slices.py views.png slices.png \
  --slices 24 \
  --shade 0.2 \
  --preview check.png
```

Useful flags:

| Flag | What it does |
| --- | --- |
| `--slices N` | Slice count. 15–20 chunky, 26–44 detailed, 36–56 showcase |
| `--round` | Clips each slice to the ellipse its side/front spans describe (towers, pots, balloons, tree crowns) |
| `--side-nose left\|right` | Which way the SIDE view faces |
| `--order auto\|reading` | Detect the four views by proportions, or trust reading order |
| `--shade 0..1` | Bakes side shading into the slices |
| `--colours N` | One shared palette across the four views |
| `--preview check.png` | Writes a contact sheet so you can inspect the result |

The same folder ships `viewer.html`, a standalone turntable/exploded/slice-scan
viewer that opens any strip you drop on it — handy for checking an asset before
wiring it into the game.

## For AI agents (skill)

The upstream repository ships an **agent skill** that teaches an assistant the
whole authoring loop: pick a tier, produce or draw a valid four-view sheet,
carve it, inspect the result, then integrate the strip:

```bash
npx skills add danielwh2/sprite-stacking
```

**Credit:** the four-view carving pipeline, the skill and the viewer are by
Daniel White ([danielwh2/sprite-stacking](https://github.com/danielwh2/sprite-stacking),
MIT). This package is the Flutter runtime for the strips that pipeline produces.
