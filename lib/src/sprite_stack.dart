import 'dart:async';
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
/// `drawImageRect` per slice (plus a few extra when [outline] or [shadow] are
/// enabled).
class SpriteStack {
  SpriteStack._(this.image, this.sliceCount, this._footprint)
      : sliceWidth = image.width ~/ sliceCount,
        sliceHeight = image.height;

  /// Builds a stack from an already decoded strip image.
  ///
  /// Throws [ArgumentError] when [sliceCount] is not positive or when the image
  /// width is not divisible by it.
  ///
  /// Stacks created this way do not have a pre-computed union footprint, so
  /// [render] falls back to the ground slice for [shadow].
  factory SpriteStack.fromImage(Image image, {required int sliceCount}) {
    if (sliceCount <= 0) {
      throw ArgumentError.value(
          sliceCount, 'sliceCount', 'must be greater than 0');
    }
    if (image.width % sliceCount != 0) {
      throw ArgumentError(
        'Image width ${image.width} is not divisible by sliceCount $sliceCount',
      );
    }
    return SpriteStack._(image, sliceCount, null);
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
    if (sliceCount <= 0) {
      throw ArgumentError.value(
          sliceCount, 'sliceCount', 'must be greater than 0');
    }

    final codec = await instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    if (image.width % sliceCount != 0) {
      image.dispose();
      codec.dispose();
      throw ArgumentError(
        'Image width ${image.width} is not divisible by sliceCount $sliceCount',
      );
    }
    final byteData = await image.toByteData(format: ImageByteFormat.rawRgba);
    final pixels = byteData?.buffer.asUint8List();

    final footprint = pixels == null
        ? null
        : await _buildFootprintImage(
            pixels,
            sliceCount: sliceCount,
            sliceWidth: image.width ~/ sliceCount,
            sliceHeight: image.height,
          );

    return SpriteStack._(image, sliceCount, footprint);
  }

  /// The strip: slices side by side, ground slice on the left.
  final Image image;

  /// How many cross-sections the strip contains.
  final int sliceCount;

  /// Width of a single slice, in source pixels.
  final int sliceWidth;

  /// Height of a single slice, in source pixels.
  final int sliceHeight;

  /// Union of every slice's alpha, used as the projected ground shadow.
  ///
  /// This is the top-down silhouette of the whole object, exactly like the
  /// reference viewer renders its shadow. Null when the stack was built with
  /// [SpriteStack.fromImage], in which case [render] falls back to the ground
  /// slice.
  final Image? _footprint;

  /// Default pitch: `asin(0.75)`, the same 0.75 vertical squash the reference
  /// viewer uses for its angled top-down camera.
  static const double defaultPitch = 0.848062078981481;

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

  /// Draws the stack with its **bottom-center** at [position].
  ///
  /// [yaw] is the rotation around the vertical axis, in radians.
  /// [pitch] tilts the camera (`0`..`pi / 2`).
  /// [spacing] is the lift between slices, in source pixels.
  /// [scale] scales the whole prop. Keep it an integer for crisp pixels.
  /// [outline] draws a crisp 1 px outer outline around the finished stack, the
  /// same way the reference viewer does, so the silhouette stays clean instead
  /// of reading as individual slices.
  /// [shadow] draws the projected ground shadow (the union of all slices)
  /// before the stack.
  /// [outlineColor] and [shadowColor] control those two passes.
  void render(
    Canvas canvas, {
    required Offset position,
    double yaw = 0,
    double pitch = defaultPitch,
    double scale = 1,
    double spacing = 1,
    Paint? paint,
    bool outline = true,
    bool shadow = true,
    Color outlineColor = const Color(0xFF181C24),
    Color shadowColor = const Color(0xFFBAC6D4),
  }) {
    final squash = squashFor(pitch);
    final effectivePaint = paint ??
        (Paint()
          ..filterQuality = FilterQuality.none
          ..isAntiAlias = false);

    final sourceWidth = sliceWidth.toDouble();
    final sourceHeight = sliceHeight.toDouble();

    // Center of the ground slice, so its bottom edge sits on `position`.
    final groundSliceCenterY = position.dy - sourceHeight * squash * scale / 2;

    // 1. Projected ground shadow: the union footprint (or the ground slice as
    // a fallback) rotated like the stack, flat on the ground, offset +2,+3 art
    // px exactly like the reference renderer.
    if (shadow && sliceCount > 0) {
      final shadowImage = _footprint ?? image;
      final shadowSource = Rect.fromLTWH(0, 0, sourceWidth, sourceHeight);
      final shadowPaint = Paint()
        ..filterQuality = FilterQuality.none
        ..isAntiAlias = false
        ..colorFilter = ColorFilter.mode(shadowColor, BlendMode.srcIn);
      final shadowCenter = Offset(
        position.dx + 2 * scale,
        position.dy + 3 * scale - sourceHeight * squash * scale / 2,
      );
      _drawSliceAt(
        canvas,
        shadowImage,
        shadowSource,
        shadowCenter,
        yaw,
        squash,
        scale,
        shadowPaint,
      );
    }

    // 2. Crisp 1 px outer outline. Drawing the whole stack tinted solid once
    // in each of the four neighbour directions and then the real stack on top
    // leaves exactly the 4-connected 1 px ring, matching the reference
    // rasterizer's outline pass.
    if (outline && sliceCount > 0) {
      final outlinePaint = Paint()
        ..filterQuality = FilterQuality.none
        ..isAntiAlias = false
        ..colorFilter = ColorFilter.mode(outlineColor, BlendMode.srcIn);
      for (final offset in _outlineOffsets) {
        final ox = offset.dx * scale;
        final oy = offset.dy * scale;
        for (var slice = 0; slice < sliceCount; slice++) {
          final center = Offset(
            position.dx + ox,
            groundSliceCenterY - slice * spacing * scale + oy,
          );
          _drawSliceAt(
            canvas,
            image,
            Rect.fromLTWH(
                slice * sourceWidth, 0, sourceWidth, sourceHeight),
            center,
            yaw,
            squash,
            scale,
            outlinePaint,
          );
        }
      }
    }

    // 3. The stack itself, bottom to top.
    for (var slice = 0; slice < sliceCount; slice++) {
      final center = Offset(
        position.dx,
        groundSliceCenterY - slice * spacing * scale,
      );
      _drawSliceAt(
        canvas,
        image,
        Rect.fromLTWH(slice * sourceWidth, 0, sourceWidth, sourceHeight),
        center,
        yaw,
        squash,
        scale,
        effectivePaint,
      );
    }
  }

  void _drawSliceAt(
    Canvas canvas,
    Image sliceImage,
    Rect source,
    Offset center,
    double yaw,
    double squash,
    double scale,
    Paint paint,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale, scale * squash);
    canvas.rotate(yaw);
    canvas.drawImageRect(
      sliceImage,
      source,
      Rect.fromCenter(
        center: Offset.zero,
        width: source.width,
        height: source.height,
      ),
      paint,
    );
    canvas.restore();
  }

  static const List<Offset> _outlineOffsets = [
    Offset(0, -1),
    Offset(0, 1),
    Offset(-1, 0),
    Offset(1, 0),
  ];

  /// Releases the decoded image. Do not use the stack afterwards.
  void dispose() {
    image.dispose();
    _footprint?.dispose();
  }
}

/// Builds a 1x art-pixel image of the union of every slice's alpha, so it can
/// be drawn as the projected ground shadow.
Future<Image?> _buildFootprintImage(
  Uint8List pixels, {
  required int sliceCount,
  required int sliceWidth,
  required int sliceHeight,
}) async {
  final stripWidth = sliceCount * sliceWidth;
  final out = Uint8List(sliceWidth * sliceHeight * 4);
  for (var y = 0; y < sliceHeight; y++) {
    final rowBase = y * stripWidth;
    for (var x = 0; x < sliceWidth; x++) {
      var opaque = false;
      for (var slice = 0; slice < sliceCount; slice++) {
        final alphaOffset =
            ((rowBase + slice * sliceWidth + x) * 4) + 3;
        if (pixels[alphaOffset] > 0) {
          opaque = true;
          break;
        }
      }
      if (opaque) {
        final offset = (y * sliceWidth + x) * 4;
        out[offset] = 255;
        out[offset + 1] = 255;
        out[offset + 2] = 255;
        out[offset + 3] = 255;
      }
    }
  }

  final completer = Completer<Image>();
  decodeImageFromPixels(
    out,
    sliceWidth,
    sliceHeight,
    PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}
