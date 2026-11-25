import 'dart:math' as math;

import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpriteStackFollowCamera', () {
    test('exponential smoothing is frame-rate independent', () {
      final camera = SpriteStackCamera.orbit(
        yaw: 0,
        pitch: 0.3,
        distance: 300,
        target: const SpriteStackPoint(0, 0, 30),
      );
      final follow = SpriteStackFollowCamera(positionRate: 6, yawRate: 3);
      const subject = SpriteStackPoint(200, 120, 0);

      final coarse = SpriteStackCamera.orbit(
        yaw: 0,
        pitch: 0.3,
        distance: 300,
        target: const SpriteStackPoint(0, 0, 30),
      );
      follow.update(coarse, subject: subject, yaw: 0, dt: 1 / 30);

      for (var i = 0; i < 2; i++) {
        follow.update(camera, subject: subject, yaw: 0, dt: 1 / 60);
      }

      expect(camera.target.x, closeTo(coarse.target.x, 1e-9));
      expect(camera.target.y, closeTo(coarse.target.y, 1e-9));
      expect(camera.target.z, closeTo(coarse.target.z, 1e-9));
    });

    test('settles behind a subject moving in a straight line', () {
      final camera = SpriteStackCamera.orbit(yaw: 0, pitch: 0.3, distance: 300);
      final follow = SpriteStackFollowCamera(yawRate: 3, lookAhead: 0);
      const yaw = -math.pi / 2; // facing +X

      for (var i = 0; i < 600; i++) {
        follow.update(
          camera,
          subject: SpriteStackPoint(i.toDouble(), 0, 0),
          yaw: yaw,
          velocity: const SpriteStackPoint(1, 0, 0),
          dt: 1 / 60,
        );
      }

      expect(camera.yaw, closeTo(yaw, 1e-6));
    });

    test('lags by omega * dt * (1 - f) / f in a steady turn', () {
      const rate = 3.0;
      const omega = 0.5;
      const dt = 1 / 60;
      final camera = SpriteStackCamera.orbit(yaw: 0, pitch: 0.3, distance: 300);
      final follow = SpriteStackFollowCamera(yawRate: rate, lookAhead: 0);

      var angle = 0.0;
      for (var i = 0; i < 300; i++) {
        angle += omega * dt;
        follow.update(
          camera,
          subject: SpriteStackPoint(
            300 * math.cos(angle),
            300 * math.sin(angle),
            0,
          ),
          yaw: angle,
          dt: dt,
        );
      }

      // e = (e + omega*dt)(1 - f) at equilibrium, with f the smoothing factor.
      final f = 1 - math.exp(-rate * dt);
      final expected = omega * dt * (1 - f) / f;
      final lag = (angle - camera.yaw).abs();
      expect(lag, closeTo(expected, 1e-3));
      // A visible lag: the car keeps rotating on screen in the turn.
      expect(lag, greaterThan(0.1));
    });

    test('approachAngle takes the short way round', () {
      expect(
        SpriteStackFollowCamera.approachAngle(0.1, 2 * math.pi - 0.08, 1),
        closeTo(-0.08, 1e-9),
      );
      expect(
        SpriteStackFollowCamera.approachAngle(-0.1, 0.08, 1),
        closeTo(0.08, 1e-9),
      );
      expect(
        SpriteStackFollowCamera.approachAngle(0, 2.0, 0.5),
        closeTo(1.0, 1e-9),
      );
    });

    test('freezes the target inside the dead zone but keeps turning', () {
      final camera = SpriteStackCamera.orbit(
        yaw: 0,
        pitch: 0.3,
        distance: 300,
        target: const SpriteStackPoint(0, 0, 0),
      );
      final follow = SpriteStackFollowCamera(
        positionRate: 6,
        yawRate: 3,
        lookAhead: 0,
        height: 0,
        deadZone: 50,
      );

      follow.update(
        camera,
        subject: const SpriteStackPoint(10, 0, 0),
        yaw: 1,
        dt: 1 / 60,
      );

      expect(camera.target, const SpriteStackPoint(0, 0, 0));
      expect(camera.yaw, greaterThan(0));
    });

    test('forwardOf follows the asset convention', () {
      final plusY = SpriteStackFollowCamera.forwardOf(0);
      expect(plusY.x, closeTo(0, 1e-12));
      expect(plusY.y, closeTo(1, 1e-12));

      // yaw = atan2(vy, vx) - pi / 2 for a +X velocity.
      final plusX = SpriteStackFollowCamera.forwardOf(-math.pi / 2);
      expect(plusX.x, closeTo(1, 1e-12));
      expect(plusX.y, closeTo(0, 1e-12));
    });

    test('smoothing is zero at zero dt and never overshoots', () {
      expect(SpriteStackFollowCamera.smoothing(6, 0), 0);
      expect(SpriteStackFollowCamera.smoothing(0, 1), 0);
      expect(SpriteStackFollowCamera.smoothing(6, 1), lessThan(1));
      expect(SpriteStackFollowCamera.smoothing(6, 1), greaterThan(0.99));
    });
  });
}
