---
title: Flame / Bonfire
description: Use SpriteStackComponent in Flame scenes with Y sorting and hit boxes.
---

# Flame / Bonfire

```dart
add(
  SpriteStackComponent(
    stack: robot,
    position: Vector2(120, 200),
    yaw: 0.6,
    stackScale: 4,
    priority: 10, // Y-sort with the rest of the scene
  ),
);
```

The component keeps `size` in sync (slice width × rendered height) so hit boxes
and `priority`-based sorting behave like any other `PositionComponent`.

`yaw` spins the prop in place; it does **not** touch the component's own
`angle`.

Use `updateBounds()` after changing `pitch`, `spacing` or `stackScale` so the
component size stays correct:

```dart
component.pitch = 0.8;
component.updateBounds();
```
