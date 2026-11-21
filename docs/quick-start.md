---
title: Quick Start
description: Load a strip and render your first sprite stack.
---

# Quick Start

```dart
import 'package:flutter_sprite_stack/sprite_stack.dart';

final tree = await SpriteStack.load(
  'assets/tree_stack.png',
  sliceCount: 43, // must divide the image width exactly
);

// Any Canvas: bottom-centre is the ground contact point.
tree.render(
  canvas,
  position: const Offset(160, 240),
  yaw: 0.6,                        // radians
  pitch: SpriteStack.defaultPitch, // asin(0.75), the reference 0.75 squash
  scale: 6,                        // integer scale keeps pixels crisp
  spacing: 1,                      // lift per slice, in source pixels
  outline: true,                   // crisp 1 px ink outline around the stack
  shadow: true,                    // projected ground shadow
);
```

`SpriteStack.defaultPitch` is `asin(0.75)` — the same 0.75 vertical squash the
reference sprite-stacking viewer uses for its angled top-down camera.
