import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;

/// A sprite-stacked prop.
///
/// The asset is a **horizontal strip of cross-sections**, ground slice first
/// (left). Slice `0` is the bottom of the object and the last slice is the top.
/// Each slice has the same size, so a strip of `N` slices is
/// `(N * sliceWidth) x sliceHeight` pixels.
///
/// Rendering is done at runtime: every slice is drawn rotated by [yaw],
/// vertically squashed by the [pitch] and lifted one [spacing] step, from the
/// ground up. That is the classic sprite-stacking trick and costs one
/// `drawImageRect` per slice.
class SpriteStack {
  SpriteStack._(this.image, this.sliceCount)
    : sliceWidth = image.width ~/ sliceCount,
      sliceHeight = image.height;

  /// Builds a stack from an already decoded strip image.
  ///
  /// Throws [ArgumentError] when [sliceCount] is not positive or when the image
  /// width is not divisible by it.
  factory SpriteStack.fromImage(Image image, {required int sliceCount}) {
    if (sliceCount <= 0) {
      throw ArgumentError.value(
        sliceCount,
        'sliceCount',
        'must be greater than 0',
      );
    }
    if (image.width % sliceCount != 0) {
      throw ArgumentError(
        'Image width ${image.width} is not divisible by sliceCount $sliceCount',
      );
    }
    return SpriteStack._(image, sliceCount);
  }

  /// Loads and decodes a strip from a Flutter asset.
  static Future<SpriteStack> load(
    String assetPath, {
    required int sliceCount,
  }) async {
    final data = await rootBundle.load(assetPath);
    return decode(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      sliceCount: sliceCount,
    );
  }

  /// Decodes a strip from raw PNG/WebP/GIF bytes.
  static Future<SpriteStack> decode(
    Uint8List bytes, {
    required int sliceCount,
  }) async {
    final codec = await instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return SpriteStack.fromImage(frame.image, sliceCount: sliceCount);
  }

  /// The strip: slices side by side, ground slice on the left.
  final Image image;

  /// How many cross-sections the strip contains.
  final int sliceCount;

  /// Width of a single slice, in source pixels.
  final int sliceWidth;

  /// Height of a single slice, in source pixels.
  final int sliceHeight;

  /// Default pitch: a slightly elevated camera, in radians (~31°).
  static const double defaultPitch = 0.55;

  static final Paint _defaultPaint = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false;

  bool _disposed = false;

  /// Whether [dispose] has already run.
  bool get isDisposed => _disposed;

  /// Size of one slice in source pixels.
  Size get sliceSize => Size(sliceWidth.toDouble(), sliceHeight.toDouble());

  /// Converts a [pitch] angle into the vertical squash applied to each slice.
  ///
  /// `0` looks at the object edge-on and `pi / 2` looks straight down. The
  /// result is clamped to `0.08..1` so the stack never collapses completely.
  static double squashFor(double pitch) {
    final clamped = pitch.clamp(0.0, math.pi / 2).toDouble();
    return math.sin(clamped).clamp(0.08, 1.0).toDouble();
  }

  /// Height of the rendered stack, in source pixels.
  double heightFor({double pitch = defaultPitch, double spacing = 1}) =>
      sliceHeight * squashFor(pitch) + (sliceCount - 1) * spacing;

  /// Axis-aligned bounds of the rendered prop, in device pixels.
  ///
  /// Unlike [heightFor], this accounts for [yaw]: a rotated slice is wider than
  /// the source slice. Useful to size hit boxes, cull props and allocate
  /// offscreen buffers.
  SpriteStackBounds boundsFor({
    double yaw = 0,
    double pitch = defaultPitch,
    double scale = 1,
    double spacing = 1,
    bool pixelSnap = false,
  }) {
    final squash = squashFor(pitch);
    final cos = math.cos(yaw).abs();
    final sin = math.sin(yaw).abs();
    final width = (sliceWidth * cos + sliceHeight * sin) * scale;
    final sliceVisualHeight = (sliceWidth * sin + sliceHeight * cos) * squash;
    final height =
        sliceVisualHeight * scale + (sliceCount - 1) * spacing * scale;

    final snappedWidth = pixelSnap ? width.ceilToDouble() : width;
    final snappedHeight = pixelSnap ? height.ceilToDouble() : height;
    return SpriteStackBounds(
      size: Size(snappedWidth, snappedHeight),
      ground: Offset(snappedWidth / 2, snappedHeight),
    );
  }

  /// Draws the stack with its **bottom-center** at [position].
  ///
  /// [yaw] is the rotation around the vertical axis, in radians.
  /// [pitch] tilts the camera (`0`..`pi / 2`).
  /// [spacing] is the lift between slices, in source pixels.
  /// [scale] scales the whole prop.
  /// [pixelSnap] rounds the ground point and every slice lift to whole device
  /// pixels, which keeps pixel art crisp. Disable it for sub-pixel smooth
  /// motion.
  void render(
    Canvas canvas, {
    required Offset position,
    double yaw = 0,
    double pitch = defaultPitch,
    double scale = 1,
    double spacing = 1,
    bool pixelSnap = true,
    Paint? paint,
  }) {
    final squash = squashFor(pitch);
    final effectivePaint = paint ?? _defaultPaint;

    final sourceWidth = sliceWidth.toDouble();
    final sourceHeight = sliceHeight.toDouble();
    final destination = Rect.fromCenter(
      center: Offset.zero,
      width: sourceWidth,
      height: sourceHeight,
    );

    final anchorX = pixelSnap ? position.dx.roundToDouble() : position.dx;
    final anchorY = pixelSnap ? position.dy.roundToDouble() : position.dy;

    // Center of the ground slice, so its bottom edge sits on `position`.
    final groundCenterY = pixelSnap
        ? (anchorY - sourceHeight * squash * scale / 2).roundToDouble()
        : anchorY - sourceHeight * squash * scale / 2;

    for (var slice = 0; slice < sliceCount; slice++) {
      final lift = pixelSnap
          ? (slice * spacing * scale).roundToDouble()
          : slice * spacing * scale;
      canvas.save();
      canvas.translate(anchorX, groundCenterY - lift);
      canvas.scale(scale, scale * squash);
      canvas.rotate(yaw);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(slice * sourceWidth, 0, sourceWidth, sourceHeight),
        destination,
        effectivePaint,
      );
      canvas.restore();
    }
  }

  /// Renders the prop once into an offscreen [Image] for a fixed camera.
  ///
  /// Drawing the baked image later costs a single `drawImage`, which is the
  /// cheapest option for static props or props that rotate in coarse steps.
  /// Re-bake whenever `yaw`, `pitch`, `scale` or `spacing` change.
  ///
  /// [padding] adds transparent margin around the image.
  Future<BakedSpriteStack> bake({
    double yaw = 0,
    double pitch = defaultPitch,
    double scale = 1,
    double spacing = 1,
    bool pixelSnap = true,
    double padding = 0,
    Paint? paint,
  }) async {
    final bounds = boundsFor(
      yaw: yaw,
      pitch: pitch,
      scale: scale,
      spacing: spacing,
      pixelSnap: true,
    );
    final width = (bounds.size.width + padding * 2).ceil();
    final height = (bounds.size.height + padding * 2).ceil();
    if (width <= 0 || height <= 0) {
      throw StateError('baked image would be empty ($width x $height)');
    }

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(padding + bounds.ground.dx, padding + bounds.ground.dy);
    render(
      canvas,
      position: Offset.zero,
      yaw: yaw,
      pitch: pitch,
      scale: scale,
      spacing: spacing,
      pixelSnap: pixelSnap,
      paint: paint,
    );
    final picture = recorder.endRecording();
    final baked = await picture.toImage(width, height);
    picture.dispose();

    return BakedSpriteStack._(
      baked,
      Offset(padding + bounds.ground.dx, padding + bounds.ground.dy),
    );
  }

  /// Releases the decoded image. Do not use the stack afterwards.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    image.dispose();
  }
}

/// Bounds of a rendered stack.
class SpriteStackBounds {
  const SpriteStackBounds({required this.size, required this.ground});

  /// Axis-aligned size of the prop, in device pixels.
  final Size size;

  /// Where the ground contact point sits inside [size], measured from the
  /// top-left corner.
  final Offset ground;
}

/// A stack rendered once into a single [Image].
///
/// Use [draw] to place it, keeping the same ground-contact semantics as
/// [SpriteStack.render].
class BakedSpriteStack {
  BakedSpriteStack._(this.image, this.groundOffset);

  /// The pre-rendered prop.
  final Image image;

  /// Ground contact point inside [image], from its top-left corner.
  final Offset groundOffset;

  /// Size of the baked image.
  Size get size => Size(image.width.toDouble(), image.height.toDouble());

  bool _disposed = false;

  /// Draws the baked prop with its ground contact at [position].
  void draw(Canvas canvas, Offset position, {Paint? paint}) {
    canvas.drawImage(image, position - groundOffset, paint);
  }

  /// Releases the baked image.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    image.dispose();
  }
}
