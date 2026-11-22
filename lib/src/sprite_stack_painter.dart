import 'package:flutter/rendering.dart';

import 'sprite_stack.dart';

/// Paints a [SpriteStack] centered horizontally at the bottom of the canvas.
///
/// Handy for plain Flutter screens and for `CustomPaint` overlays.
class SpriteStackPainter extends CustomPainter {
  SpriteStackPainter({
    required this.stack,
    this.yaw = 0,
    this.pitch = SpriteStack.defaultPitch,
    this.scale = 1,
    this.spacing = 1,
    this.offset = Offset.zero,
    this.frame = 0,
    this.pixelSnap = true,
    this.outline = true,
    this.shadow = true,
    this.outlineColor = const Color(0xFF181C24),
    this.shadowColor = const Color(0xFFBAC6D4),
    this.stackPaint,
  });

  final SpriteStack stack;

  /// Rotation around the vertical axis, in radians.
  final double yaw;

  /// Camera tilt, `0` (edge-on) to `pi / 2` (top-down).
  final double pitch;

  final double scale;

  /// Lift between slices, in source pixels.
  final double spacing;

  /// Optional offset applied on top of the default bottom-center anchor.
  final Offset offset;

  /// Atlas frame to draw.
  final int frame;

  /// Rounds the ground anchor to whole pixels.
  final bool pixelSnap;

  /// Whether to draw the crisp 1 px outer outline.
  final bool outline;

  /// Whether to draw the projected ground shadow.
  final bool shadow;

  /// Outline color for the finished stack.
  final Color outlineColor;

  /// Ground shadow color.
  final Color shadowColor;

  /// Optional paint, e.g. to apply a color filter to the body.
  final Paint? stackPaint;

  @override
  void paint(Canvas canvas, Size size) {
    stack.render(
      canvas,
      position: Offset(size.width / 2, size.height) + offset,
      yaw: yaw,
      pitch: pitch,
      scale: scale,
      spacing: spacing,
      frame: frame,
      pixelSnap: pixelSnap,
      paint: stackPaint,
      outline: outline,
      shadow: shadow,
      outlineColor: outlineColor,
      shadowColor: shadowColor,
    );
  }

  @override
  bool shouldRepaint(covariant SpriteStackPainter oldDelegate) =>
      oldDelegate.stack != stack ||
      oldDelegate.yaw != yaw ||
      oldDelegate.pitch != pitch ||
      oldDelegate.scale != scale ||
      oldDelegate.spacing != spacing ||
      oldDelegate.offset != offset ||
      oldDelegate.frame != frame ||
      oldDelegate.pixelSnap != pixelSnap ||
      oldDelegate.outline != outline ||
      oldDelegate.shadow != shadow ||
      oldDelegate.outlineColor != outlineColor ||
      oldDelegate.shadowColor != shadowColor ||
      oldDelegate.stackPaint != stackPaint;
}
