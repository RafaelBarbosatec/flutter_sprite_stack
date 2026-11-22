import 'dart:ui';

import 'package:flame/components.dart';

import 'sprite_stack.dart';

/// Flame/Bonfire component that renders a [SpriteStack].
///
/// The component keeps `size` in sync with the **rotated** bounds of the prop
/// (not just the source slice size), so hit boxes and visibility culling match
/// what is actually drawn. [yaw] spins the prop in place; it does not touch the
/// component's own `angle`.
class SpriteStackComponent extends PositionComponent {
  SpriteStackComponent({
    required this.stack,
    double yaw = 0,
    double pitch = SpriteStack.defaultPitch,
    double stackScale = 1,
    double spacing = 1,
    this.pixelSnap = true,
    this.outline = true,
    this.shadow = true,
    this.outlineColor = const Color(0xFF181C24),
    this.shadowColor = const Color(0xFFBAC6D4),
    super.position,
    super.priority,
  })  : _yaw = yaw,
        _pitch = pitch,
        _stackScale = stackScale,
        _spacing = spacing,
        super(
          anchor: Anchor.topLeft,
          size: _boundsSize(
            stack: stack,
            yaw: yaw,
            pitch: pitch,
            stackScale: stackScale,
            spacing: spacing,
          ),
        );

  static Vector2 _boundsSize({
    required SpriteStack stack,
    required double yaw,
    required double pitch,
    required double stackScale,
    required double spacing,
  }) {
    final size = stack
        .boundsFor(
          yaw: yaw,
          pitch: pitch,
          scale: stackScale,
          spacing: spacing,
          pixelSnap: true,
        )
        .size;
    return Vector2(size.width, size.height);
  }

  final SpriteStack stack;

  /// Rotation around the vertical axis, in radians.
  double get yaw => _yaw;
  set yaw(double value) {
    if (value == _yaw) return;
    _yaw = value;
    _refreshBounds();
  }

  double _yaw;

  /// Camera tilt, `0` (edge-on) to `pi / 2` (top-down).
  double get pitch => _pitch;
  set pitch(double value) {
    if (value == _pitch) return;
    _pitch = value;
    _refreshBounds();
  }

  double _pitch;

  /// Uniform scale applied when drawing.
  double get stackScale => _stackScale;
  set stackScale(double value) {
    if (value == _stackScale) return;
    _stackScale = value;
    _refreshBounds();
  }

  double _stackScale;

  /// Lift between slices, in source pixels.
  double get spacing => _spacing;
  set spacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    _refreshBounds();
  }

  double _spacing;

  /// Rounds the ground anchor and slice lifts to whole pixels.
  bool pixelSnap;

  /// Whether to draw the crisp 1 px outer outline.
  bool outline;

  /// Whether to draw the projected ground shadow.
  bool shadow;

  /// Outline color for the finished stack.
  Color outlineColor;

  /// Ground shadow color.
  Color shadowColor;

  /// Ground contact point in local coordinates.
  ///
  /// The default anchor is [Anchor.topLeft], so the ground stays at
  /// `position + (layoutWidth / 2, layoutHeight)` and growing bounds never
  /// shift the prop.
  Offset get groundLocal => Offset(
        stack.sliceWidth * _stackScale / 2,
        stack.heightFor(pitch: _pitch, spacing: _spacing) * _stackScale,
      );

  @override
  void render(Canvas canvas) {
    stack.render(
      canvas,
      position: groundLocal,
      yaw: _yaw,
      pitch: _pitch,
      scale: _stackScale,
      spacing: _spacing,
      pixelSnap: pixelSnap,
      outline: outline,
      shadow: shadow,
      outlineColor: outlineColor,
      shadowColor: shadowColor,
    );
  }

  @override
  bool containsLocalPoint(Vector2 point) {
    final bounds = stack.boundsFor(
      yaw: _yaw,
      pitch: _pitch,
      scale: _stackScale,
      spacing: _spacing,
    );
    final ground = groundLocal;
    return (point.x - ground.dx).abs() <= bounds.size.width / 2 &&
        point.y <= ground.dy &&
        point.y >= ground.dy - bounds.size.height;
  }

  /// Recomputes `size` after changing [pitch], [spacing], [stackScale] or
  /// [yaw]. The setters already do this; the method is kept for callers that
  /// mutate state in bulk.
  void updateBounds() => _refreshBounds();

  void _refreshBounds() {
    final bounds = stack.boundsFor(
      yaw: _yaw,
      pitch: _pitch,
      scale: _stackScale,
      spacing: _spacing,
      pixelSnap: true,
    );
    size.setValues(bounds.size.width, bounds.size.height);
  }
}
