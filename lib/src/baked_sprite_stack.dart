import 'dart:math' as math;
import 'dart:ui';

import 'sprite_stack.dart';
import 'sprite_stack_bounds.dart';

/// A [SpriteStack] rendered once into a [Picture] and replayed with [draw].
///
/// The software rasterizer is CPU-bound: it allocates a 1x art-pixel buffer and
/// walks every opaque pixel on each call. Baking records the result of one
/// render, so drawing it again costs a single `drawPicture` — the right choice
/// for scenery that does not change every frame.
///
/// Create one with [SpriteStack.bake]. The picture is recorded around the
/// **ground contact point**, so [draw] only translates the canvas.
class BakedSpriteStack {
  /// Wraps an already recorded picture.
  ///
  /// [picture] must be recorded with the ground contact point at the origin,
  /// which is what [SpriteStack.bake] does.
  BakedSpriteStack.fromPicture(this.picture, this.bounds, this.yaw)
      : _disposed = false;

  /// The recorded render, with its ground point at the origin.
  final Picture picture;

  /// Projected bounds of this frame.
  final SpriteStackBounds bounds;

  /// Yaw this frame was baked at, in radians.
  final double yaw;

  bool _disposed;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Replays the baked frame with its ground point at [groundPosition].
  void draw(Canvas canvas, Offset groundPosition) {
    assert(!_disposed, 'BakedSpriteStack used after dispose()');
    canvas.save();
    canvas.translate(groundPosition.dx, groundPosition.dy);
    canvas.drawPicture(picture);
    canvas.restore();
  }

  /// Releases the recorded picture.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    picture.dispose();
  }
}

/// A lazily baked turntable: one [BakedSpriteStack] per yaw bucket.
///
/// Pixel art hides the quantisation, so a few dozen buckets are enough to spin
/// a prop smoothly. Each bucket is rendered the first time it is needed; call
/// [warmUp] to pay that cost up front instead of during gameplay.
///
/// ```dart
/// final turntable = SpriteStackTurntable(tree, buckets: 72, scale: 4);
/// turntable.warmUp();
/// // Per frame:
/// turntable.draw(canvas, groundPosition, yaw);
/// ```
class SpriteStackTurntable {
  SpriteStackTurntable(
    this.stack, {
    this.buckets = 72,
    this.pitch = SpriteStack.defaultPitch,
    this.scale = 1,
    this.spacing = 1,
    this.outline = true,
    this.shadow = true,
    this.outlineColor = const Color(0xFF181C24),
    this.shadowColor = const Color(0xFFBAC6D4),
    this.pixelSnap = true,
  }) : assert(buckets > 0, 'buckets must be greater than 0');

  /// The stack every bucket is baked from.
  final SpriteStack stack;

  /// How many distinct yaw angles are baked.
  final int buckets;

  /// Camera tilt used for every bucket.
  final double pitch;

  /// Uniform scale used for every bucket.
  final double scale;

  /// Lift between slices used for every bucket.
  final double spacing;

  /// Whether baked frames include the 1 px outline.
  final bool outline;

  /// Whether baked frames include the projected ground shadow.
  final bool shadow;

  /// Outline ink color.
  final Color outlineColor;

  /// Ground shadow color.
  final Color shadowColor;

  /// Whether baked frames snap the ground point to whole pixels.
  final bool pixelSnap;

  final Map<int, BakedSpriteStack> _frames = {};

  /// Yaw covered by a single bucket, in radians.
  double get yawStep => 2 * math.pi / buckets;

  /// How many buckets have been baked so far.
  int get bakedFrameCount => _frames.length;

  /// Bucket index closest to [yaw].
  int bucketFor(double yaw) {
    final turn = (yaw / (2 * math.pi)) % 1.0;
    return (turn * buckets).round() % buckets;
  }

  /// The frame for [bucket], baked on first use.
  BakedSpriteStack frameAt(int bucket) {
    final index = bucket % buckets;
    return _frames.putIfAbsent(index, () {
      return stack.bake(
        yaw: index * yawStep,
        pitch: pitch,
        scale: scale,
        spacing: spacing,
        outline: outline,
        shadow: shadow,
        outlineColor: outlineColor,
        shadowColor: shadowColor,
        pixelSnap: pixelSnap,
      );
    });
  }

  /// The frame closest to [yaw], baked on first use.
  BakedSpriteStack frameFor(double yaw) => frameAt(bucketFor(yaw));

  /// Bakes every bucket now, so the first full turn does not hitch.
  void warmUp() {
    for (var i = 0; i < buckets; i++) {
      frameAt(i);
    }
  }

  /// Draws the frame closest to [yaw] with its ground point at [groundPosition].
  void draw(Canvas canvas, Offset groundPosition, double yaw) {
    frameFor(yaw).draw(canvas, groundPosition);
  }

  /// Disposes every baked frame.
  void dispose() {
    for (final frame in _frames.values) {
      frame.dispose();
    }
    _frames.clear();
  }
}
