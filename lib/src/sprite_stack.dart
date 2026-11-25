import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;

import 'baked_sprite_stack.dart';
import 'slice_cut.dart';
import 'sprite_stack_bounds.dart';
import 'sprite_stack_motion.dart';
import 'sprite_stack_volume.dart';

/// A sprite-stacked prop.
///
/// The asset is a **horizontal strip of cross-sections**, ground slice first
/// (left). Slice `0` is the bottom of the object and the last slice is the top.
/// Each slice has the same size, so a strip of `N` slices is
/// `(N * sliceWidth) x sliceHeight` pixels.
///
/// A stack can also hold several **frames**: stack the strips vertically and
/// the atlas becomes `(N * sliceWidth) x (frameCount * sliceHeight)`, frame `0`
/// on top. All frames share the slice geometry; only the frame index changes
/// what is drawn. Use [SpriteStackAnimation] to drive that index over time.
///
/// Rendering is done at runtime in a 1x art-pixel buffer exactly like the
/// reference `viewer.html`: every slice is inverse-mapped per screen pixel with
/// nearest sampling, the finished stack is outlined once and the whole buffer
/// is then scaled up with integer pixels. That gives the same uniform,
/// seam-free pixel-art silhouette as the HTML preview.
class SpriteStack {
  SpriteStack._(
    this.image,
    this.sliceCount,
    this.frameCount,
    this._pixels,
    this._footprintMasks,
  )   : sliceWidth = image.width ~/ sliceCount,
        sliceHeight = image.height ~/ frameCount;

  /// Builds a stack from an already decoded strip (or frame atlas) image.
  ///
  /// Throws [ArgumentError] when [sliceCount] or [frameCount] is not positive,
  /// when the image width is not divisible by [sliceCount], or when its height
  /// is not divisible by [frameCount].
  ///
  /// Stacks created this way do not have pre-extracted pixels, so [render]
  /// falls back to the older per-slice `drawImageRect` path (and the ground
  /// slice is used for [shadow]).
  factory SpriteStack.fromImage(
    Image image, {
    required int sliceCount,
    int frameCount = 1,
  }) {
    _validate(
      sliceCount: sliceCount,
      frameCount: frameCount,
      width: image.width,
      height: image.height,
    );
    return SpriteStack._(image, sliceCount, frameCount, null, null);
  }

  /// Loads and decodes a strip from a Flutter asset.
  static Future<SpriteStack> load(
    String assetPath, {
    required int sliceCount,
    int frameCount = 1,
  }) async {
    final data = await rootBundle.load(assetPath);
    return decode(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      sliceCount: sliceCount,
      frameCount: frameCount,
    );
  }

  /// Decodes a strip (or a vertical atlas of frames) from raw image bytes.
  static Future<SpriteStack> decode(
    Uint8List bytes, {
    required int sliceCount,
    int frameCount = 1,
  }) async {
    if (sliceCount <= 0) {
      throw ArgumentError.value(
          sliceCount, 'sliceCount', 'must be greater than 0');
    }
    if (frameCount <= 0) {
      throw ArgumentError.value(
          frameCount, 'frameCount', 'must be greater than 0');
    }

    final codec = await instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    if (image.width % sliceCount != 0 || image.height % frameCount != 0) {
      image.dispose();
      codec.dispose();
      throw ArgumentError(
        'Image ${image.width}x${image.height} does not split into '
        '$sliceCount slices x $frameCount frames',
      );
    }
    final byteData = await image.toByteData(format: ImageByteFormat.rawRgba);
    final pixels = byteData?.buffer.asUint8List();
    final sliceWidth = image.width ~/ sliceCount;
    final sliceHeight = image.height ~/ frameCount;

    final footprintMasks = pixels == null
        ? null
        : _buildFootprintMasks(
            pixels,
            sliceCount: sliceCount,
            sliceWidth: sliceWidth,
            sliceHeight: sliceHeight,
            frameCount: frameCount,
          );

    return SpriteStack._(
      image,
      sliceCount,
      frameCount,
      pixels,
      footprintMasks,
    );
  }

  static void _validate({
    required int sliceCount,
    required int frameCount,
    required int width,
    required int height,
  }) {
    if (sliceCount <= 0) {
      throw ArgumentError.value(
          sliceCount, 'sliceCount', 'must be greater than 0');
    }
    if (frameCount <= 0) {
      throw ArgumentError.value(
          frameCount, 'frameCount', 'must be greater than 0');
    }
    if (width % sliceCount != 0) {
      throw ArgumentError(
        'Image width $width is not divisible by sliceCount $sliceCount',
      );
    }
    if (height % frameCount != 0) {
      throw ArgumentError(
        'Image height $height is not divisible by frameCount $frameCount',
      );
    }
  }

  /// The strip: slices side by side, ground slice on the left.
  final Image image;

  /// How many cross-sections the strip contains.
  final int sliceCount;

  /// How many animation frames the asset holds, stacked vertically.
  final int frameCount;

  /// Width of a single slice, in source pixels.
  final int sliceWidth;

  /// Height of a single slice (one frame row), in source pixels.
  final int sliceHeight;

  /// Raw RGBA pixels of the whole atlas, when the stack was built with [load]
  /// or [decode]. Used by the software rasterizer.
  final Uint8List? _pixels;

  /// Union of every slice's alpha (one byte per art pixel) for each frame, used
  /// as the projected ground shadow by the software rasterizer.
  final Uint8List? _footprintMasks;

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

  /// Reconstructs the voxel volume of this stack, for 3D scenes and tooling.
  ///
  /// Every slice is a horizontal cross-section, so stacking them in order
  /// rebuilds the object's volume. [frame] selects an atlas row (clamped, like
  /// [render]) and [alphaThreshold] decides which pixels count as solid: a
  /// pixel is solid when its alpha is `>=` the threshold.
  ///
  /// Only stacks built with [load] or [decode] keep their raw pixels. A stack
  /// built with [fromImage] cannot be read back synchronously, so this throws
  /// a [StateError] for it.
  ///
  /// ```dart
  /// final volume = stack.toVolume();
  /// final mesh = const SpriteStackMesher().build(volume);
  /// ```
  SpriteStackVolume toVolume({int frame = 0, int alphaThreshold = 128}) {
    final pixels = _pixels;
    if (pixels == null) {
      throw StateError(
        'SpriteStack.toVolume() needs raw pixels; build the stack with '
        'SpriteStack.load() or SpriteStack.decode() instead of '
        'SpriteStack.fromImage().',
      );
    }
    return SpriteStackVolume.fromPixels(
      pixels,
      sliceWidth: sliceWidth,
      sliceHeight: sliceHeight,
      sliceCount: sliceCount,
      frameCount: frameCount,
      frame: frame,
      alphaThreshold: alphaThreshold,
    );
  }

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
  /// [pixelSnap] rounds the ground anchor (and the per-slice lifts of the
  /// fallback path) to whole pixels, so an integer [scale] lands exactly on the
  /// device pixel grid instead of blurring every edge.
  /// [outlineColor] and [shadowColor] control those two passes.
  /// [frame] selects the row of a frame atlas; it is clamped to the available
  /// frames and ignored when [frameCount] is `1`.
  /// [motion] deforms each slice (sway, lean); [time] is the clock it reads, in
  /// seconds. Motion shifts slices in whole art pixels in the software
  /// rasterizer and continuously in the fallback path.
  /// [cut] hides slices above (or below) a frontier, for roof-off cutaways.
  /// [roll] tilts the finished sprite in screen space, around a pivot
  /// [rollPivot] of the way up the body (`0` = the ground point, `1` = the
  /// top). Like [pitch], it is a drawing effect, not a re-projection: the
  /// silhouette rotates but no new side of the prop is revealed.
  void render(
    Canvas canvas, {
    required Offset position,
    double yaw = 0,
    double pitch = defaultPitch,
    double scale = 1,
    double spacing = 1,
    int frame = 0,
    StackMotion? motion,
    double time = 0,
    SliceCut? cut,
    Paint? paint,
    bool outline = true,
    bool shadow = true,
    bool pixelSnap = true,
    Color outlineColor = const Color(0xFF181C24),
    Color shadowColor = const Color(0xFFBAC6D4),
    double roll = 0,
    double rollPivot = 0,
  }) {
    final squash = squashFor(pitch);

    // Roll tilts the finished sprite in screen space, around a pivot
    // `rollPivot` of the way up the body (`0` keeps the ground point planted).
    // It is a 2D effect like the pitch squash, not a re-projection: the shadow
    // and the slices move together.
    final pivot = roll == 0
        ? null
        : Offset(
            position.dx,
            position.dy -
                heightFor(pitch: pitch, spacing: spacing) * scale * rollPivot,
          );
    if (pivot != null) {
      canvas.save();
      canvas.translate(pivot.dx, pivot.dy);
      canvas.rotate(roll);
      canvas.translate(-pivot.dx, -pivot.dy);
    }
    final frameIndex = frameCount == 1 ? 0 : frame.clamp(0, frameCount - 1);
    final activeMotion = (motion == null || motion.isEmpty) ? null : motion;
    final activeCut = (cut == null || !cut.isActive) ? null : cut;

    if (_pixels != null && paint == null) {
      _renderSoftware(
        canvas,
        position: position,
        yaw: yaw,
        squash: squash,
        scale: scale,
        spacing: spacing,
        frame: frameIndex,
        motion: activeMotion,
        time: time,
        cut: activeCut,
        outline: outline,
        shadow: shadow,
        pixelSnap: pixelSnap,
        outlineColor: outlineColor,
        shadowColor: shadowColor,
      );
    } else {
      _renderSlices(
        canvas,
        position: position,
        yaw: yaw,
        squash: squash,
        scale: scale,
        spacing: spacing,
        frame: frameIndex,
        motion: activeMotion,
        time: time,
        cut: activeCut,
        paint: paint,
        outline: outline,
        shadow: shadow,
        pixelSnap: pixelSnap,
        outlineColor: outlineColor,
        shadowColor: shadowColor,
      );
    }
    if (pivot != null) canvas.restore();
  }

  /// Projected bounds of the stack for a given camera and scale.
  ///
  /// The stack is anchored by its ground contact point, so [position] is not a
  /// corner. Feed this into culling and hit testing instead of
  /// `sliceWidth × heightFor`, which ignores both yaw and the ground shadow:
  ///
  /// ```dart
  /// final bounds = stack.boundsFor(yaw: yaw, scale: 4);
  /// final rect = bounds.rectAt(groundPosition);
  /// ```
  ///
  /// The ground shadow is included vertically (but not its 2 px sideways
  /// offset) when [shadow] is `true`, so culling never clips the drop shadow.
  /// The software rasterizer rounds the lift per slice, so allow one pixel of
  /// slack.
  SpriteStackBounds boundsFor({
    double yaw = 0,
    double pitch = defaultPitch,
    double scale = 1,
    double spacing = 1,
    SliceCut? cut,
    bool outline = true,
    bool shadow = true,
    double roll = 0,
    double rollPivot = 0,
  }) {
    final ca = math.cos(yaw).abs();
    final sa = math.sin(yaw).abs();
    final squash = squashFor(pitch);
    final w = sliceWidth.toDouble();
    final h = sliceHeight.toDouble();

    // The 1 px outline is a 4-connected ring around the finished stack.
    final grow = outline ? 1.0 : 0.0;

    final width = (w * ca + h * sa) + grow * 2;
    final projectedSliceHeight = (w * sa + h * ca) * squash;
    final visibleSlices = cut == null || !cut.isActive
        ? sliceCount.toDouble()
        : cut.visibleSliceCount(sliceCount);
    final lift = math.max(0.0, visibleSlices - 1) * spacing;

    // Distance from the top of the bounds down to the ground point.
    final above = lift + projectedSliceHeight + grow;
    // Outline below the feet plus the projected ground shadow (+3 source px).
    final below = grow + (shadow ? 3 + projectedSliceHeight / 2 : 0.0);

    final w = width * scale;
    final h = (above + below) * scale;
    final gx = w / 2;
    final gy = above * scale;
    if (roll == 0) {
      return SpriteStackBounds(size: Size(w, h), ground: Offset(gx, gy));
    }

    // Rotate the box around the roll pivot and return its axis-aligned
    // envelope, plus where the ground point ends up inside it.
    final pivotY =
        gy - heightFor(pitch: pitch, spacing: spacing) * scale * rollPivot;
    final c = math.cos(roll);
    final s = math.sin(roll);
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final corner in <Offset>[
      Offset.zero,
      Offset(w, 0),
      Offset(w, h),
      Offset(0, h),
    ]) {
      final dx = corner.dx - gx;
      final dy = corner.dy - pivotY;
      final x = gx + dx * c - dy * s;
      final y = pivotY + dx * s + dy * c;
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }
    final anchorDx = -(gy - pivotY) * s;
    final anchorDy = (gy - pivotY) * c;
    return SpriteStackBounds(
      size: Size(maxX - minX, maxY - minY),
      ground: Offset(gx + anchorDx - minX, pivotY + anchorDy - minY),
    );
  }

  /// Renders this stack once into a [BakedSpriteStack].
  ///
  /// Replaying the result costs a single `drawPicture`, which makes this the
  /// cheap path for scenery drawn every frame. See also [SpriteStackTurntable]
  /// for a lazily baked set of yaw angles.
  BakedSpriteStack bake({
    double yaw = 0,
    double pitch = defaultPitch,
    double scale = 1,
    double spacing = 1,
    int frame = 0,
    StackMotion? motion,
    double time = 0,
    SliceCut? cut,
    bool outline = true,
    bool shadow = true,
    bool pixelSnap = true,
    Color outlineColor = const Color(0xFF181C24),
    Color shadowColor = const Color(0xFFBAC6D4),
    double roll = 0,
    double rollPivot = 0,
  }) {
    final frameIndex = frameCount == 1 ? 0 : frame.clamp(0, frameCount - 1);
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    render(
      canvas,
      position: Offset.zero,
      yaw: yaw,
      pitch: pitch,
      scale: scale,
      spacing: spacing,
      frame: frameIndex,
      motion: motion,
      time: time,
      cut: cut,
      outline: outline,
      shadow: shadow,
      pixelSnap: pixelSnap,
      outlineColor: outlineColor,
      shadowColor: shadowColor,
      roll: roll,
      rollPivot: rollPivot,
    );
    return BakedSpriteStack.fromPicture(
      recorder.endRecording(),
      boundsFor(
        yaw: yaw,
        pitch: pitch,
        scale: scale,
        spacing: spacing,
        cut: cut,
        outline: outline,
        shadow: shadow,
      ),
      yaw,
      frame: frameIndex,
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
    required int frame,
    required StackMotion? motion,
    required double time,
    required SliceCut? cut,
    required bool outline,
    required bool shadow,
    required bool pixelSnap,
    required Color outlineColor,
    required Color shadowColor,
  }) {
    final pixels = _pixels!;
    final w = sliceWidth;
    final h = sliceHeight;
    final n = sliceCount;
    final rowOffset = frame * h;

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
    if (shadow && _footprintMasks != null) {
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
        rowOffset,
        (shadowArgb >> 16) & 0xFF,
        (shadowArgb >> 8) & 0xFF,
        shadowArgb & 0xFF,
        (shadowArgb >> 24) & 0xFF,
      );
    }

    // 2. Body slices, bottom to top, overwriting.
    final invSquash = 1 / math.max(squash, 0.1);
    for (var z = 0; z < n; z++) {
      final visibility = cut?.visibilityAt(z) ?? 1.0;
      if (visibility <= 0) continue;
      final lift = (z * spacing).round();
      // Motion is applied in whole art pixels: the buffer is 1x, so a fraction
      // of a pixel cannot be represented without blurring the pixel grid.
      final shift = motion?.offsetAt(z, n, time) ?? Offset.zero;
      final sliceCx = cx + shift.dx.round();
      final yCenter = baseY - lift + shift.dy.round();
      final halfW = (w * ca.abs() + h * sa.abs()) / 2;
      final halfH = (w * sa.abs() + h * ca.abs()) / 2 * squash;
      final xMin = math.max(0, (sliceCx - halfW).floor() - 1);
      final xMax = math.min(cw - 1, (sliceCx + halfW).ceil() + 1);
      final yMin = math.max(0, (yCenter - halfH).floor() - 1);
      final yMax = math.min(ch - 1, (yCenter + halfH).ceil() + 1);
      final stripWidth = n * w;
      final zBase = z * w;

      for (var y = yMin; y <= yMax; y++) {
        final dy = (y - yCenter) * invSquash;
        var sx = (xMin - sliceCx) * ca + dy * sa + w * 0.5;
        var sy = -(xMin - sliceCx) * sa + dy * ca + h * 0.5;
        var idx = y * cw + xMin;
        for (var x = xMin; x <= xMax; x++, idx++, sx += ca, sy -= sa) {
          if (sx < 0 || sy < 0) continue;
          final ix = sx.floor();
          final iy = sy.floor();
          if (ix >= w || iy >= h) continue;
          final sp = ((rowOffset + iy) * stripWidth + zBase + ix) * 4;
          if (pixels[sp + 3] == 0) continue;
          if (visibility < 1 && !bayerAllows(x, y, visibility)) continue;
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
    // while it spins. Snapping it to whole pixels keeps the upscaled grid
    // aligned when the prop moves by fractions of a pixel.
    final rawAnchorY = position.dy - h * squash * scale / 2;
    final anchorX = pixelSnap ? position.dx.roundToDouble() : position.dx;
    final anchorY = pixelSnap ? rawAnchorY.roundToDouble() : rawAnchorY;
    _drawBuffer(
      canvas,
      out,
      cw,
      ch,
      cx,
      baseY,
      anchorX: anchorX,
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
    int rowOffset,
    int r,
    int g,
    int b,
    int a,
  ) {
    final w = sliceWidth;
    final h = sliceHeight;
    final mask = _footprintMasks!;
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
        if (mask[(rowOffset + iy) * w + ix] == 0) continue;
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
    required int frame,
    required StackMotion? motion,
    required double time,
    required SliceCut? cut,
    Paint? paint,
    required bool outline,
    required bool shadow,
    required bool pixelSnap,
    required Color outlineColor,
    required Color shadowColor,
  }) {
    final effectivePaint = paint ??
        (Paint()
          ..filterQuality = FilterQuality.none
          ..isAntiAlias = false);

    final ground = pixelSnap
        ? Offset(position.dx.roundToDouble(), position.dy.roundToDouble())
        : position;
    double snapY(double value) => pixelSnap ? value.roundToDouble() : value;

    final sourceWidth = sliceWidth.toDouble();
    final sourceHeight = sliceHeight.toDouble();
    final sourceTop = frame * sourceHeight;
    final groundSliceCenterY = ground.dy - sourceHeight * squash * scale / 2;

    if (shadow && sliceCount > 0) {
      final shadowPaint = Paint()
        ..filterQuality = FilterQuality.none
        ..isAntiAlias = false
        ..colorFilter = ColorFilter.mode(shadowColor, BlendMode.srcIn);
      final shadowCenter = Offset(
        ground.dx + 2 * scale,
        ground.dy + 3 * scale - sourceHeight * squash * scale / 2,
      );
      _drawSliceAt(
        canvas,
        image,
        Rect.fromLTWH(0, sourceTop, sourceWidth, sourceHeight),
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
          if (cut != null && cut.visibilityAt(slice) < 0.5) continue;
          final shift =
              motion?.offsetAt(slice, sliceCount, time) ?? Offset.zero;
          final center = Offset(
            ground.dx + ox + shift.dx * scale,
            snapY(groundSliceCenterY -
                slice * spacing * scale +
                oy +
                shift.dy * scale),
          );
          _drawSliceAt(
            canvas,
            image,
            Rect.fromLTWH(
                slice * sourceWidth, sourceTop, sourceWidth, sourceHeight),
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
      if (cut != null && cut.visibilityAt(slice) < 0.5) continue;
      final shift = motion?.offsetAt(slice, sliceCount, time) ?? Offset.zero;
      final center = Offset(
        ground.dx + shift.dx * scale,
        snapY(groundSliceCenterY - slice * spacing * scale + shift.dy * scale),
      );
      _drawSliceAt(
        canvas,
        image,
        Rect.fromLTWH(
            slice * sourceWidth, sourceTop, sourceWidth, sourceHeight),
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

/// Builds a 1x art-pixel mask per frame: the union of every slice's alpha.
Uint8List _buildFootprintMasks(
  Uint8List pixels, {
  required int sliceCount,
  required int sliceWidth,
  required int sliceHeight,
  required int frameCount,
}) {
  final stripWidth = sliceCount * sliceWidth;
  final framePixels = sliceWidth * sliceHeight;
  final mask = Uint8List(framePixels * frameCount);
  for (var frame = 0; frame < frameCount; frame++) {
    final frameBase = frame * framePixels;
    final firstRow = frame * sliceHeight;
    for (var y = 0; y < sliceHeight; y++) {
      final rowBase = (firstRow + y) * stripWidth;
      for (var x = 0; x < sliceWidth; x++) {
        var opaque = false;
        for (var slice = 0; slice < sliceCount; slice++) {
          final alphaOffset = ((rowBase + slice * sliceWidth + x) * 4) + 3;
          if (pixels[alphaOffset] > 0) {
            opaque = true;
            break;
          }
        }
        if (opaque) mask[frameBase + y * sliceWidth + x] = 255;
      }
    }
  }
  return mask;
}
