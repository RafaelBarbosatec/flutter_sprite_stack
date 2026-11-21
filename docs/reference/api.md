---
title: API
description: SpriteStack, SpriteStackPainter and SpriteStackComponent reference.
---

# API

| Member | Meaning |
| --- | --- |
| `SpriteStack.load(path, sliceCount:)` | Loads a strip from a Flutter asset |
| `SpriteStack.decode(bytes, sliceCount:)` | Decodes a strip from memory |
| `SpriteStack.fromImage(image, sliceCount:)` | Wraps an already decoded `ui.Image` |
| `render(canvas, position:, yaw:, pitch:, scale:, spacing:, paint:, outline:, shadow:, outlineColor:, shadowColor:)` | Draws the stack |
| `sliceWidth`, `sliceHeight`, `sliceSize`, `sliceCount` | Strip geometry |
| `heightFor(pitch:, spacing:)` | Rendered height in source pixels |
| `SpriteStack.defaultPitch` | `asin(0.75)` rad (~49°) |
| `dispose()` | Releases the decoded image |
| `SpriteStackPainter(...)` | `CustomPainter` for plain Flutter |
| `SpriteStackComponent(...)` | Flame/Bonfire `PositionComponent` |

`pitch` is clamped to `0..π/2` and its squash to `0.08..1`, so the stack never
collapses to nothing.

## Render parameters

| Parameter | Default | Meaning |
| --- | --- | --- |
| `position` | required | Bottom-centre ground contact point |
| `yaw` | `0` | Rotation around the vertical axis, radians |
| `pitch` | `defaultPitch` | Camera tilt, `0` (edge-on) to `π/2` (top-down) |
| `scale` | `1` | Uniform scale; keep it integer for crisp pixels |
| `spacing` | `1` | Lift between slices, source pixels |
| `outline` | `true` | Crisp 1 px outer outline around the finished stack |
| `shadow` | `true` | Projected ground shadow |
| `outlineColor` | `0xFF181C24` | Outline ink color |
| `shadowColor` | `0xFFBAC6D4` | Ground shadow color |
| `paint` | `null` | Optional paint, e.g. a color filter for the body |
