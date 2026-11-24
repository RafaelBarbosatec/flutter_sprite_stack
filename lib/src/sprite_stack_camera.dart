import 'dart:math' as math;

import 'sprite_stack_point.dart';

/// An orbiting camera for a `SpriteStackScene`.
///
/// The camera looks at [target] from a sphere of radius [distance]. [yaw] moves
/// it around the vertical axis and [pitch] raises it towards a top-down view
/// (`pi / 2` is clamped just short of straight down, where the basis would
/// degenerate).
///
/// World units are art pixels (see [SpriteStackPoint]), so a scene can place
/// props at their natural size.
class SpriteStackCamera {
  SpriteStackCamera.orbit({
    this.yaw = 0.6,
    double pitch = 0.55,
    this.distance = 900,
    this.target = SpriteStackPoint.zero,
    this.near = 1,
  }) : _pitch = _clampPitch(pitch);

  /// Highest allowed pitch: just short of `pi / 2`.
  static const double maxPitch = math.pi / 2 - 0.001;

  static double _clampPitch(double value) =>
      value.clamp(0.0, maxPitch).toDouble();

  /// Rotation around the vertical axis, in radians.
  double yaw;

  double _pitch;

  /// Distance from [target] to the camera, in world units.
  double distance;

  /// Point the camera looks at.
  SpriteStackPoint target;

  /// Anything closer than this to the camera is clipped.
  final double near;

  /// Elevation above the ground plane, in radians (`0..pi / 2`).
  double get pitch => _pitch;
  set pitch(double value) => _pitch = _clampPitch(value);

  /// Camera position in world space.
  SpriteStackPoint get eye {
    final cosPitch = math.cos(_pitch);
    return SpriteStackPoint(
      target.x + distance * math.sin(yaw) * cosPitch,
      target.y - distance * math.cos(yaw) * cosPitch,
      target.z + distance * math.sin(_pitch),
    );
  }

  /// Orthonormal camera basis, recomputed from [eye], [target] and [pitch].
  SpriteStackCameraBasis get basis {
    final eye = this.eye;
    final forward = (target - eye).normalized;
    var right = forward.cross(const SpriteStackPoint(0, 0, 1));
    if (right.length < 1e-9) {
      // Looking straight down/up: any horizontal axis works as "right".
      right = const SpriteStackPoint(1, 0, 0);
    } else {
      right = right.normalized;
    }
    final up = right.cross(forward).normalized;
    return SpriteStackCameraBasis(
      eye: eye,
      forward: forward,
      right: right,
      up: up,
    );
  }
}

/// Orthonormal basis of a [SpriteStackCamera]: where it is and which way its
/// axes point.
class SpriteStackCameraBasis {
  const SpriteStackCameraBasis({
    required this.eye,
    required this.forward,
    required this.right,
    required this.up,
  });

  /// Camera position in world space.
  final SpriteStackPoint eye;

  /// Unit vector from [eye] towards the target.
  final SpriteStackPoint forward;

  /// Unit vector pointing right on screen.
  final SpriteStackPoint right;

  /// Unit vector pointing up on screen.
  final SpriteStackPoint up;

  /// Camera-space depth of [point]: smaller is closer, negative is behind.
  double depthOf(SpriteStackPoint point) => (point - eye).dot(forward);

  /// Camera-space horizontal coordinate of [point].
  double horizontalOf(SpriteStackPoint point) => (point - eye).dot(right);

  /// Camera-space vertical coordinate of [point].
  double verticalOf(SpriteStackPoint point) => (point - eye).dot(up);
}
