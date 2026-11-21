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
/// Rendering is done at runtime in a 1x art-pixel buffer exactly like the
/// reference `viewer.html`: every slice is inverse-mapped per screen pixel with
/// nearest sampling, the finished stack is outlined once and the whole buffer
/// is then scaled up with integer pixels. That gives the same uniform,
/// seam-free pixel-art silhouette as the HTML preview.
class SpriteStack {
  SpriteStack._(this.image, this.sliceCount, this._pixels, this._footprintMask)
      : sliceWidth = image.width ~/ sliceCount,
        sliceHeight = image.height;

  /// Builds a stack from an already decoded strip image.
  ///
  /// Throws [ArgumentError] when [sliceCount] is not positive or when the image
  /// width is not divisible by it.
  ///
  /// Stacks created this way do not have pre-extracted pixels, so [render]
  /// falls back to the older per-slice `drawImageRect` path (and the ground
  /// slice is used for [shadow]).
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
    return SpriteStack._(image, sliceCount, null, null);
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
    final sliceWidth = image.width ~/ sliceCount;
    final sliceHeight = image.height;

    final footprintMask = pixels == null
        ? null
        : _buildFootprintMask(
            pixels,
            sliceCount: sliceCount,
            sliceWidth: sliceWidth,
            sliceHeight: sliceHeight,
          );

    return SpriteStack._(image, sliceCount, pixels, footprintMask);
  }

  /// The strip: slices side by side, ground slice on the left.
  final Image image;

  /// How many cross-sections the strip contains.
  final int sliceCount;

  /// Width of a single slice, in source pixels.
  final int sliceWidth;

  /// Height of a single slice, in source pixels.
  final int sliceHeight;

  /// Raw RGBA pixels of the strip, when the stack was built with [load] or
  /// [decode]. Used by the software rasterizer.
  final Uint8List? _pixels;

  /// Union of every slice's alpha (one byte per art pixel), used as the
  /// projected ground shadow by the software rasterizer.
  final Uint8List? _footprintMask;

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
  /// same way the reference viewer does.
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

    if (_pixels != null && paint == null) {
      _renderSoftware(
        canvas,
        position: position,
        yaw: yaw,
        squash: squash,
        scale: scale,
        spacing: spacing,
        outline: outline,
        shadow: shadow,
        outlineColor: outlineColor,
        shadowColor: shadowColor,
      );
      return;
    }

    _renderSlices(
      canvas,
      position: position,
      yaw: yaw,
      squash: squash,
      scale: scale,
      spacing: spacing,
      paint: paint,
      outline: outline,
      shadow: shadow,
      outlineColor: outlineColor,
      shadowColor: shadowColor,
    );
  }

  // ---------------------------------------------------------------------
  // Software rasterizer (matches viewer.html): 1x art-pixel buffer, nearest
  // inverse sampling, one outline pass, then integer scale-up.
  // ---------------------------------------------------------------------
  void _renderSoftware(
    Canvas canvas, {
    required Offset position,
    required double yaw,
    required double squash,
    required double scale,
    required double spacing,
    required bool outline,
    required bool shadow,
    required Color outlineColor,
    required Color shadowColor,
  }) {
    final pixels = _pixels!;
    final w = sliceWidth;
    final h = sliceHeight;
    final n = sliceCount;

    final ca = math.cos(yaw);
    final sa = math.sin(yaw);

    final diag = math.sqrt((w * w + h * h).toDouble()).ceil() + 6;
    final liftMax = ((n - 1) * spacing).ceil();
    final shadowPad = shadow ? (n * 1.4).ceil() : 0;
    final cw = diag + 16 + shadowPad * 2;
    final ch =
        (diag * squash).ceil() + liftMax + 20 + (shadowPad * squash).ceil();
    final cx = cw >> 1;
    final baseY = ch -
        ((diag * squash) / 2).ceil() -
        8 -
        (shadowPad * squash * 0.45).ceil();

    final out = Uint8List(cw * ch * 4); // RGBA
    final alpha = Uint8List(cw * ch); // body occupancy

    // 1. Projected ground shadow: the union footprint rendered like one slice,
    // offset +2,+3 art px from the ground slice centre.
    if (shadow && _footprintMask != null) {
      final shadowArgb = shadowColor.toARGB32();
      _rasterFootprint(
        out,
        cw,
        ch,
        cx + 2,
        baseY + 3,
        ca,
        sa,
        squash,
        (shadowArgb >> 16) & 0xFF,
        (shadowArgb >> 8) & 0xFF,
        shadowArgb & 0xFF,
        (shadowArgb >> 24) & 0xFF,
      );
    }

    // 2. Body slices, bottom to top, overwriting.
    final invSquash = 1 / math.max(squash, 0.1);
    for (var z = 0; z < n; z++) {
      final lift = (z * spacing).round();
      final yCenter = baseY - lift;
      final halfW = (w * ca.abs() + h * sa.abs()) / 2;
      final halfH = (w * sa.abs() + h * ca.abs()) / 2 * squash;
      final xMin = math.max(0, (cx - halfW).floor() - 1);
      final xMax = math.min(cw - 1, (cx + halfW).ceil() + 1);
      final yMin = math.max(0, (yCenter - halfH).floor() - 1);
      final yMax = math.min(ch - 1, (yCenter + halfH).ceil() + 1);
      final stripWidth = n * w;
      final zBase = z * w;

      for (var y = yMin; y <= yMax; y++) {
        final dy = (y - yCenter) * invSquash;
        var sx = (xMin - cx) * ca + dy * sa + w * 0.5;
        var sy = -(xMin - cx) * sa + dy * ca + h * 0.5;
        var idx = y * cw + xMin;
        for (var x = xMin; x <= xMax; x++, idx++, sx += ca, sy -= sa) {
          if (sx < 0 || sy < 0) continue;
          final ix = sx.floor();
          final iy = sy.floor();
          if (ix >= w || iy >= h) continue;
          final sp = (iy * stripWidth + zBase + ix) * 4;
          if (pixels[sp + 3] == 0) continue;
          final dp = idx * 4;
          out[dp] = pixels[sp];
          out[dp + 1] = pixels[sp + 1];
          out[dp + 2] = pixels[sp + 2];
          out[dp + 3] = pixels[sp + 3];
          alpha[idx] = 1;
        }
      }
    }

    // 3. Crisp 1 px outer outline (4-connected ring outside the body).
    if (outline) {
      final outlineArgb = outlineColor.toARGB32();
      final or = (outlineArgb >> 16) & 0xFF;
      final og = (outlineArgb >> 8) & 0xFF;
      final ob = outlineArgb & 0xFF;
      final oa = (outlineArgb >> 24) & 0xFF;
      for (var y = 1; y < ch - 1; y++) {
        var idx = y * cw + 1;
        for (var x = 1; x < cw - 1; x++, idx++) {
          if (alpha[idx] != 0) continue;
          if (alpha[idx - 1] != 0 ||
              alpha[idx + 1] != 0 ||
              alpha[idx - cw] != 0 ||
              alpha[idx + cw] != 0) {
            final dp = idx * 4;
            out[dp] = or;
            out[dp + 1] = og;
            out[dp + 2] = ob;
            out[dp + 3] = oa;
          }
        }
      }
    }

    // The ground slice centre is a fixed anchor, exactly like the reference
    // viewer's `baseY`. Anchoring to a fixed point keeps the prop from bobbing
    // while it spins.
    final anchorY = position.dy - h * squash * scale / 2;
    _drawBuffer(
      canvas,
      out,
      cw,
      ch,
      cx,
      baseY,
      anchorX: position.dx,
      anchorY: anchorY,
      scale: scale,
    );
  }

  void _rasterFootprint(
    Uint8List out,
    int cw,
    int ch,
    int fcx,
    int fcy,
    double ca,
    double sa,
    double squash,
    int r,
    int g,
    int b,
    int a,
  ) {
    final w = sliceWidth;
    final h = sliceHeight;
    final mask = _footprintMask!;
    final invSquash = 1 / math.max(squash, 0.1);
    final halfW = (w * ca.abs() + h * sa.abs()) / 2;
    final halfH = (w * sa.abs() + h * ca.abs()) / 2 * squash;
    final xMin = math.max(0, (fcx - halfW).floor() - 1);
    final xMax = math.min(cw - 1, (fcx + halfW).ceil() + 1);
    final yMin = math.max(0, (fcy - halfH).floor() - 1);
    final yMax = math.min(ch - 1, (fcy + halfH).ceil() + 1);

    for (var y = yMin; y <= yMax; y++) {
      final dy = (y - fcy) * invSquash;
      var sx = (xMin - fcx) * ca + dy * sa + w * 0.5;
      var sy = -(xMin - fcx) * sa + dy * ca + h * 0.5;
      var idx = y * cw + xMin;
      for (var x = xMin; x <= xMax; x++, idx++, sx += ca, sy -= sa) {
        if (sx < 0 || sy < 0) continue;
        final ix = sx.floor();
        final iy = sy.floor();
        if (ix >= w || iy >= h) continue;
        if (mask[iy * w + ix] == 0) continue;
        final dp = idx * 4;
        out[dp] = r;
        out[dp + 1] = g;
        out[dp + 2] = b;
        out[dp + 3] = a;
      }
    }
  }

  void _drawBuffer(
    Canvas canvas,
    Uint8List out,
    int cw,
    int ch,
    int cx,
    int baseY, {
    required double anchorX,
    required double anchorY,
    required double scale,
  }) {
    final strokeWidth = math.max(scale, 0.01);
    final pointsByColor = <int, List<Offset>>{};
    for (var y = 0; y < ch; y++) {
      var idx = y * cw * 4;
      for (var x = 0; x < cw; x++, idx += 4) {
        if (out[idx + 3] == 0) continue;
        final color = (out[idx + 3] << 24) |
            (out[idx] << 16) |
            (out[idx + 1] << 8) |
            out[idx + 2];
        final point = Offset(
          anchorX + (x - cx) * scale + strokeWidth / 2,
          anchorY + (y - baseY) * scale + strokeWidth / 2,
        );
        pointsByColor.putIfAbsent(color, () => <Offset>[]).add(point);
      }
    }

    for (final entry in pointsByColor.entries) {
      final paint = Paint()
        ..color = Color(entry.key)
        ..strokeWidth = strokeWidth
        ..isAntiAlias = false
        ..strokeCap = StrokeCap.butt;
      canvas.drawPoints(PointMode.points, entry.value, paint);
    }
  }

  // ---------------------------------------------------------------------
  // Fallback: per-slice drawImageRect path (used by fromImage / custom paint).
  // ---------------------------------------------------------------------
  void _renderSlices(
    Canvas canvas, {
    required Offset position,
    required double yaw,
    required double squash,
    required double scale,
    required double spacing,
    Paint? paint,
    required bool outline,
    required bool shadow,
    required Color outlineColor,
    required Color shadowColor,
  }) {
    final effectivePaint = paint ??
        (Paint()
          ..filterQuality = FilterQuality.none
          ..isAntiAlias = false);

    final sourceWidth = sliceWidth.toDouble();
    final sourceHeight = sliceHeight.toDouble();
    final groundSliceCenterY = position.dy - sourceHeight * squash * scale / 2;

    if (shadow && sliceCount > 0) {
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
        image,
        Rect.fromLTWH(0, 0, sourceWidth, sourceHeight),
        shadowCenter,
        yaw,
        squash,
        scale,
        shadowPaint,
      );
    }

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
  void dispose() => image.dispose();
}

/// Builds a 1x art-pixel mask of the union of every slice's alpha.
Uint8List _buildFootprintMask(
  Uint8List pixels, {
  required int sliceCount,
  required int sliceWidth,
  required int sliceHeight,
}) {
  final stripWidth = sliceCount * sliceWidth;
  final mask = Uint8List(sliceWidth * sliceHeight);
  for (var y = 0; y < sliceHeight; y++) {
    final rowBase = y * stripWidth;
    for (var x = 0; x < sliceWidth; x++) {
      var opaque = false;
      for (var slice = 0; slice < sliceCount; slice++) {
        final alphaOffset = ((rowBase + slice * sliceWidth + x) * 4) + 3;
        if (pixels[alphaOffset] > 0) {
          opaque = true;
          break;
        }
      }
      if (opaque) mask[y * sliceWidth + x] = 255;
    }
  }
  return mask;
}
