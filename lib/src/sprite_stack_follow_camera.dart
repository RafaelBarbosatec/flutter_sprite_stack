import 'dart:math' as math;

import 'sprite_stack_camera.dart';
import 'sprite_stack_point.dart';

/// Smooth third-person follow for a [SpriteStackCamera].
///
/// The camera does not snap to the subject: it chases a point [lookAhead] units
/// in front of it and swings its yaw towards the subject's facing, both with an
/// exponential delay. The delay is the point — while the camera catches up, the
/// subject's relative yaw (`object.yaw - camera.yaw`) is non-zero, so a turn is
/// visible instead of the subject staying locked to the same screen angle.
///
/// All rates are per second and frame-rate independent: `1 - exp(-rate * dt)`.
/// A rate of `3` means roughly a 330 ms time constant.
///
/// ```dart
/// final follow = SpriteStackFollowCamera(lookAhead: 60, yawRate: 3);
///
/// // per frame
/// car.position = car.position + velocity * dt;
/// car.yaw = math.atan2(velocity.y, velocity.x) - math.pi / 2;
/// follow.update(
///   scene.camera,
///   subject: car.position,
///   yaw: car.yaw,
///   velocity: velocity,
///   dt: dt,
/// );
/// ```
///
/// The camera's [SpriteStackCamera.distance] and [SpriteStackCamera.pitch] are
/// left alone: framing stays in the caller's hands.
class SpriteStackFollowCamera {
  SpriteStackFollowCamera({
    this.positionRate = 6,
    this.yawRate = 3,
    this.lookAhead = 60,
    this.height = 25,
    this.deadZone = 0,
  })  : assert(positionRate >= 0, 'positionRate must not be negative'),
        assert(yawRate >= 0, 'yawRate must not be negative'),
        assert(deadZone >= 0, 'deadZone must not be negative');

  /// How fast the target chases the subject, per second. `0` freezes it.
  double positionRate;

  /// How fast the camera yaw follows the subject's yaw, per second.
  ///
  /// Lower values leave the camera behind in turns, which is what makes the
  /// subject's rotation readable.
  double yawRate;

  /// Distance in front of the subject the camera aims at, along its velocity.
  ///
  /// Falls back to the subject's facing when the velocity is zero.
  double lookAhead;

  /// Height above the subject the camera aims at, in world units.
  double height;

  /// Radius in world units inside which the target does not move.
  ///
  /// Hides sub-pixel jitter on slow movement; `0` follows every frame.
  double deadZone;

  /// Exponential smoothing factor for [rate] over [dt] seconds.
  static double smoothing(double rate, double dt) {
    if (rate <= 0 || dt <= 0) return 0;
    return 1 - math.exp(-rate * dt);
  }

  /// Moves [from] towards [to] by the shortest arc, by [factor] (`0..1`).
  static double approachAngle(double from, double to, double factor) {
    final delta = (to - from + math.pi) % (2 * math.pi) - math.pi;
    return from + delta * factor.clamp(0.0, 1.0);
  }

  /// World direction a prop faces at [yaw], in the asset convention (front is
  /// `+Y`, so `yaw = atan2(vy, vx) - pi / 2` for a velocity).
  static SpriteStackPoint forwardOf(double yaw) =>
      SpriteStackPoint(-math.sin(yaw), math.cos(yaw), 0);

  /// Points [camera] at [subject], with the configured lag.
  ///
  /// [yaw] is the subject's facing, [velocity] its world velocity (used for
  /// [lookAhead]); pass `null` to aim along [yaw] instead. Returns the new
  /// target so callers can read it without touching the camera.
  SpriteStackPoint update(
    SpriteStackCamera camera, {
    required SpriteStackPoint subject,
    required double yaw,
    required double dt,
    SpriteStackPoint? velocity,
  }) {
    final direction = (velocity != null && velocity.length > 1e-6)
        ? velocity.normalized
        : forwardOf(yaw);
    final wanted =
        subject + direction * lookAhead + SpriteStackPoint(0, 0, height);

    final target = camera.target;
    final moved = SpriteStackPoint(
      wanted.x - target.x,
      wanted.y - target.y,
      0,
    );
    if (deadZone <= 0 || moved.length > deadZone) {
      final factor = smoothing(positionRate, dt);
      camera.target = SpriteStackPoint(
        target.x + (wanted.x - target.x) * factor,
        target.y + (wanted.y - target.y) * factor,
        target.z + (wanted.z - target.z) * factor,
      );
    }

    camera.yaw = approachAngle(camera.yaw, yaw, smoothing(yawRate, dt));
    return camera.target;
  }
}
