import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';

/// Pre-renders a [SpriteStack] into [Picture]s, one per yaw bucket.
///
/// The software rasterizer in [SpriteStack.render] is great for a single prop
/// but too heavy to run every frame for a whole scene. In a game the yaw only
/// has to be quantized (a few degrees is invisible with pixel art), so each
/// bucket is rendered once and replayed with `drawPicture`.
///
/// Pictures are drawn around the **centre of the ground slice** (the origin).
class CachedStack {
  CachedStack(
    this.stack, {
    this.scale = 1,
    this.buckets = 72,
    this.pitch = SpriteStack.defaultPitch,
    this.spacing = 1,
    this.shadowColor = const Color(0x55000000),
  });

  final SpriteStack stack;
  final double scale;
  final int buckets;
  final double pitch;
  final double spacing;
  final Color shadowColor;

  final Map<int, Picture> _cache = {};

  /// Size of the ground-slice footprint on screen.
  Size get footprint => Size(
        stack.sliceWidth * scale,
        stack.sliceHeight * SpriteStack.squashFor(pitch) * scale,
      );

  int _bucketFor(double yaw) {
    final turn = (yaw / (2 * math.pi)) % 1.0;
    return (turn * buckets).round() % buckets;
  }

  Picture _pictureFor(int bucket) {
    return _cache.putIfAbsent(bucket, () {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      stack.render(
        canvas,
        position: Offset(0, footprint.height / 2),
        yaw: bucket * 2 * math.pi / buckets,
        pitch: pitch,
        scale: scale,
        spacing: spacing,
        shadowColor: shadowColor,
      );
      return recorder.endRecording();
    });
  }

  /// Renders every bucket now so the first turn does not hitch.
  void warmUp() {
    for (var i = 0; i < buckets; i++) {
      _pictureFor(i);
    }
  }

  /// Draws the stack with its ground-slice centre at the canvas origin.
  void paint(Canvas canvas, double yaw) {
    canvas.drawPicture(_pictureFor(_bucketFor(yaw)));
  }

  void dispose() {
    for (final picture in _cache.values) {
      picture.dispose();
    }
    _cache.clear();
  }
}
