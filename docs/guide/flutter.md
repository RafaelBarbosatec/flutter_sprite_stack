---
title: Plain Flutter
description: Render a SpriteStack with CustomPaint and SpriteStackPainter.
---

# Plain Flutter

Wrap a `SpriteStack` in a `CustomPaint` using `SpriteStackPainter`:

```dart
CustomPaint(
  size: const Size(320, 320),
  painter: SpriteStackPainter(
    stack: robot,
    yaw: 0.6,
    scale: 6,
  ),
)
```

`SpriteStackPainter` anchors the stack at the bottom centre of the canvas and
re-paints when `yaw`, `pitch`, `scale`, `spacing`, `offset`, `outline`, `shadow`,
their colors or `stackPaint` change.

You can also call `render` directly on any `Canvas`:

```dart
stack.render(
  canvas,
  position: const Offset(160, 240),
  yaw: 0.6,
  scale: 6,
);
```
