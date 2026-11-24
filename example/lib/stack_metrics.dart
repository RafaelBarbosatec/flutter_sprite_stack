import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';

/// Vertical squash used by [measureProjectedHeight] (the default camera).
final double _referenceSquash =
    SpriteStack.squashFor(SpriteStack.defaultPitch);

/// Height of the stack's *actual pixels* (lift excluded), in art pixels,
/// averaged over a full turn.
///
/// [SpriteStack.heightFor] measures the slice box, but the visible silhouette
/// is smaller: the strip has transparent padding and the projected slices
/// overlap each other. Centering with the box leaves the prop visibly
/// off-centre (up to ~12% of its height), so this renders the stack offscreen
/// once and measures the real pixels.
///
/// The result is a single average instead of a per-angle value on purpose:
/// re-measuring every frame is what makes a spinning prop bob up and down.
Future<double> measureProjectedHeight(SpriteStack stack) async {
  const steps = 6;
  final side =
      stack.sliceWidth + stack.sliceHeight + stack.sliceCount + 32;
  final anchor = Offset(side / 2, side - 16.0);

  final heights = <double>[];
  for (var i = 0; i < steps; i++) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    stack.render(
      canvas,
      position: anchor,
      yaw: i * math.pi / steps,
      scale: 1,
      shadow: false,
    );
    final image = await recorder.endRecording().toImage(side, side);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();

    var top = side;
    for (var y = 0; y < side && y < top; y++) {
      final row = y * side * 4 + 3;
      for (var x = 0; x < side; x++) {
        if (bytes[row + x * 4] != 0) {
          top = y;
          break;
        }
      }
    }
    image.dispose();
    if (top < side) heights.add(anchor.dy - top);
  }

  if (heights.isEmpty) return stack.heightFor() - (stack.sliceCount - 1);
  final average = heights.reduce((a, b) => a + b) / heights.length;
  // `render` above ran with spacing 1, so drop that lift.
  return math.max(1.0, average - (stack.sliceCount - 1));
}

/// Offset that puts [stack]'s body in the middle of [canvas].
///
/// [SpriteStackPainter] places the bottom of the stack at the bottom of the
/// canvas, so the body has to be lifted by half of its height. Pass
/// [projectedHeight] (from [measureProjectedHeight]) for exact centring;
/// without it the slice box from [SpriteStack.heightFor] is used.
Offset stackCenterOffset(
  SpriteStack stack, {
  required Size canvas,
  required double scale,
  required double pitch,
  double spacing = 1,
  double? projectedHeight,
}) {
  final lift = (stack.sliceCount - 1) * spacing;
  final height = projectedHeight == null
      ? stack.heightFor(pitch: pitch, spacing: spacing)
      : lift +
          projectedHeight * SpriteStack.squashFor(pitch) / _referenceSquash;
  return Offset(0, canvas.height / 2 + height * scale / 2 - canvas.height);
}
