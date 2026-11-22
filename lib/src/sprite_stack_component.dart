import 'dart:ui';

import 'package:flame/components.dart';

import 'sprite_stack.dart';

/// Flame/Bonfire component that renders a [SpriteStack].
///
/// The component keeps `size` in sync with the **rotated** bounds of the prop
/// (not just the source slice size), so hit boxes and visibility culling match
/// what is actually drawn. [yaw] spins the prop in place; it does not touch the
/// component's own `angle`.
///
/// With the default [Anchor.topLeft], `position` keeps the 0.1.x semantics:
/// the ground point sits at `position + (layoutWidth / 2, layoutHeight)`, where
/// the layout uses the unrotated slice width. Pass [Anchor.bottomCenter] to
/// make `position` be the ground contact point itself — recommended for new
/// code, because growing bounds then expand symmetrically around the ground.
class SpriteStackComponent extends PositionComponent {
  SpriteStackComponent({
    required this.stack,
    double yaw = 0,
    double pitch = SpriteStack.defaultPitch,
    double stackScale = 1,
    double spacing = 1,
    this.pixelSnap = true,
    super.position,
    super.priority,
    Anchor? anchor,
  }) : _yaw = yaw,
       _pitch = pitch,
       _stackScale = stackScale,
       _spacing = spacing,
       super(
         anchor: anchor ?? Anchor.topLeft,
         size: stack
             .boundsFor(
               yaw: yaw,
               pitch: pitch,
               scale: stackScale,
               spacing: spacing,
               pixelSnap: true,
             )
             .size,
       );

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

  /// Rounds the ground point and every slice lift to whole pixels.
  bool pixelSnap;

  /// Ground contact point in local coordinates.
  ///
  /// Uses the unrotated layout for [Anchor.topLeft] to preserve the 0.1.x
  /// behaviour; every other anchor uses the bottom-center of the (already
  /// rotation-aware) `size`.
  Offset get groundLocal {
    if (anchor.x == Anchor.topLeft.x && anchor.y == Anchor.topLeft.y) {
      return Offset(
        stack.sliceWidth * _stackScale / 2,
        stack.heightFor(pitch: _pitch, spacing: _spacing) * _stackScale,
      );
    }
    return Offset(size.x / 2, size.y);
  }

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
