import 'dart:ui';

import 'package:flame/components.dart';

import 'sprite_stack.dart';
import 'sprite_stack_bounds.dart';

/// Flame/Bonfire component that renders a [SpriteStack].
///
/// The component keeps `size` in sync with the **projected** bounds of the
/// prop — rotated footprint plus outline and ground shadow — so hit boxes,
/// visible-area culling and `priority`-based Y sorting match what is actually
/// drawn. [yaw] spins the prop in place; it does not touch the component's own
/// `angle`.
///
/// The anchor is [Anchor.topLeft], but the drawing is positioned by the ground
/// contact point ([groundLocal]), so the prop stays planted while it spins.
class SpriteStackComponent extends PositionComponent {
  SpriteStackComponent({
    required this.stack,
    double yaw = 0,
    double pitch = SpriteStack.defaultPitch,
    double stackScale = 1,
    double spacing = 1,
    this.pixelSnap = true,
    bool outline = true,
    bool shadow = true,
    this.outlineColor = const Color(0xFF181C24),
    this.shadowColor = const Color(0xFFBAC6D4),
    super.position,
    super.priority,
  })  : _yaw = yaw,
        _pitch = pitch,
        _stackScale = stackScale,
        _spacing = spacing,
        _outline = outline,
        _shadow = shadow,
        super(
          anchor: Anchor.topLeft,
          size: _boundsSize(
            stack: stack,
            yaw: yaw,
            pitch: pitch,
            stackScale: stackScale,
            spacing: spacing,
            outline: outline,
            shadow: shadow,
          ),
        ) {
    _ground = _groundFor(
      stack: stack,
      yaw: _yaw,
      pitch: _pitch,
      stackScale: _stackScale,
      spacing: _spacing,
      outline: _outline,
      shadow: _shadow,
    );
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

  /// Whether the baked-in 1 px outline is drawn.
  bool get outline => _outline;
  set outline(bool value) {
    if (value == _outline) return;
    _outline = value;
    _refreshBounds();
  }

  bool _outline;

  /// Whether the projected ground shadow is drawn.
  bool get shadow => _shadow;
  set shadow(bool value) {
    if (value == _shadow) return;
    _shadow = value;
    _refreshBounds();
  }

  bool _shadow;

  /// Rounds the ground anchor to whole pixels.
  bool pixelSnap;

  /// Outline color for the finished stack.
  Color outlineColor;

  /// Ground shadow color.
  Color shadowColor;

  /// Ground contact point, relative to the component's top-left corner.
  ///
  /// The default anchor is [Anchor.topLeft], but drawing is anchored here so
  /// growing bounds never shift the prop.
  Offset get groundLocal => _ground;

  Offset _ground = Offset.zero;

  /// Projected bounds for the current yaw, pitch, scale and spacing.
  SpriteStackBounds get bounds => stack.boundsFor(
        yaw: _yaw,
        pitch: _pitch,
        scale: _stackScale,
        spacing: _spacing,
        outline: _outline,
        shadow: _shadow,
      );

  static Vector2 _boundsSize({
    required SpriteStack stack,
    required double yaw,
    required double pitch,
    required double stackScale,
    required double spacing,
    required bool outline,
    required bool shadow,
  }) {
    final size = stack
        .boundsFor(
          yaw: yaw,
          pitch: pitch,
          scale: stackScale,
          spacing: spacing,
          outline: outline,
          shadow: shadow,
        )
        .size;
    return Vector2(size.width, size.height);
  }

  static Offset _groundFor({
    required SpriteStack stack,
    required double yaw,
    required double pitch,
    required double stackScale,
    required double spacing,
    required bool outline,
    required bool shadow,
  }) =>
      stack
          .boundsFor(
            yaw: yaw,
            pitch: pitch,
            scale: stackScale,
            spacing: spacing,
            outline: outline,
            shadow: shadow,
          )
          .ground;

  @override
  void render(Canvas canvas) {
    stack.render(
      canvas,
      position: _ground,
      yaw: _yaw,
      pitch: _pitch,
      scale: _stackScale,
      spacing: _spacing,
      pixelSnap: pixelSnap,
      outline: _outline,
      shadow: _shadow,
      outlineColor: outlineColor,
      shadowColor: shadowColor,
    );
  }

  /// Recomputes `size` and the ground point after changing the camera.
  ///
  /// The setters already do this; the method is kept for callers that mutate
  /// several fields at once.
  void updateBounds() => _refreshBounds();

  void _refreshBounds() {
    final projected = bounds;
    size.setValues(projected.size.width, projected.size.height);
    _ground = projected.ground;
  }
}
