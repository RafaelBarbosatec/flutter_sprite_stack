import 'dart:math' as math;

import 'package:bonfire/bonfire.dart';
import 'package:flutter/services.dart';

import 'cached_stack.dart';
import 'race_state.dart';
import 'smoke.dart';
import 'touch_controls.dart';
import 'track.dart';

/// Player-controlled Formula 1 car drawn with a sprite stack.
///
/// The stack art faces *down* at yaw 0, so `yaw = heading - pi / 2`.
class F1Car extends Player with WithCollision {
  F1Car({
    required Vector2 center,
    required this.visual,
    required this.track,
    required this.race,
    required this.touch,
    double heading = 0,
  }) : _heading = heading,
       super(
         position: center - Vector2.all(_bodySize / 2),
         size: Vector2.all(_bodySize),
         speed: 0,
       ) {
    setupMovementByJoystick(enabled: false);
  }

  static const double _bodySize = 44;
  static const double _maxSpeed = 480;
  static const double _maxGrassSpeed = 150;
  static const double _maxReverse = 120;
  static const double _acceleration = 260;
  static const double _brake = 650;
  static const double _turnRate = 2.8;

  final CachedStack visual;
  final Track track;
  final RaceState race;

  /// On-screen controls (steering buttons and pedals).
  final DriveInput touch;

  double _heading;
  double _speed = 0;

  final math.Random _random = math.Random();
  double _smokeClock = 0;

  bool _checkpoint = false;
  double? _lastX;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(CircleHitbox(radius: _bodySize / 2, position: Vector2.zero()));
    // Hitting a barrier scrubs speed.
    collision.onMovementBlockedListener((other, data) => _speed *= 0.6);
  }

  @override
  void update(double dt) {
    _drive(dt);
    super.update(dt);
    _emitSmoke(dt);
    _trackRace(dt);
  }

  /// Exhaust smoke: more and bigger puffs the faster (or harder) the car goes.
  void _emitSmoke(double dt) {
    final speed = _speed.abs();
    if (speed < 25 || !hasGameRef) return;

    final load = (speed / _maxSpeed).clamp(0.0, 1.0);
    _smokeClock += dt;
    final interval = 0.11 - 0.07 * load;
    if (_smokeClock < interval) return;
    _smokeClock = 0;

    // Rear of the car along the heading (the exhaust sits ~25 px behind the
    // centre and ~5 px above the ground in the stack).
    final dir = Vector2(math.cos(_heading), math.sin(_heading));
    final back = _speed >= 0 ? -dir : dir;
    final origin = center + back * 26 + Vector2(0, -5);
    final jitter = Vector2(
      (_random.nextDouble() - 0.5) * 8,
      (_random.nextDouble() - 0.5) * 8,
    );

    gameRef.add(
      buildSmokePuff(
        position: origin + jitter,
        velocity: back * (18 + 30 * load) + jitter * 1.5,
        random: _random,
        priority: priority + 1,
        intensity: load,
      ),
    );
  }

  void _drive(double dt) {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    bool down(LogicalKeyboardKey a, LogicalKeyboardKey b) =>
        keys.contains(a) || keys.contains(b);

    var throttle = 0.0;
    var steer = 0.0;
    if (down(LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.keyW)) {
      throttle += 1;
    }
    if (down(LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.keyS)) {
      throttle -= 1;
    }
    if (down(LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.keyA)) {
      steer -= 1;
    }
    if (down(LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.keyD)) {
      steer += 1;
    }
    final handbrake = keys.contains(LogicalKeyboardKey.space);

    // On-screen controls add to the keyboard input.
    if (touch.gas) throttle += 1;
    if (touch.brake) throttle -= 1;
    if (touch.left) steer -= 1;
    if (touch.right) steer += 1;
    throttle = throttle.clamp(-1.0, 1.0);
    steer = steer.clamp(-1.0, 1.0);

    final onGrass = track.cellAt(center) == TrackCell.grass;
    final topSpeed = onGrass ? _maxGrassSpeed : _maxSpeed;

    if (throttle > 0) {
      _speed += _acceleration * dt * (_speed < 0 ? 3 : 1);
    } else if (throttle < 0) {
      _speed -= (_speed > 5 ? _brake : _acceleration * 0.6) * dt;
    } else {
      // Coasting drag.
      _speed -= _speed * (onGrass ? 2.5 : 0.45) * dt;
    }
    if (handbrake) {
      _speed -= _speed.sign * math.min(_speed.abs(), _brake * dt);
    }
    if (_speed > topSpeed) {
      _speed = math.max(topSpeed, _speed - 700 * dt);
    }
    _speed = _speed.clamp(-_maxReverse, _maxSpeed * 1.0);

    final grip = (_speed / 140).clamp(-1.0, 1.0);
    // Less steering lock at high speed.
    final lock = 1 - 0.55 * (_speed.abs() / _maxSpeed);
    _heading += steer * _turnRate * lock * grip * dt;

    if (_speed.abs() < 1) {
      _speed = 0;
      stop();
    } else {
      moveByAngle(
        _speed >= 0 ? _heading : _heading + math.pi,
        speed: _speed.abs(),
      );
    }
  }

  void _trackRace(double dt) {
    race.tick(dt, _speed.abs() * 0.6);
    if (!race.started && _speed.abs() > 10) {
      // Timer starts on the first throttle press.
      race.startRace();
    }

    final c = center;
    final lineX = track.startLineX;
    final lastX = _lastX;
    _lastX = c.x;
    if (lastX == null) return;

    final onTopHalf = c.y < track.midY;
    // The car runs clockwise-backwards: bottom straight left→right,
    // top straight right→left.
    if (onTopHalf && lastX > lineX && c.x <= lineX) {
      _checkpoint = true;
    } else if (!onTopHalf && lastX < lineX && c.x >= lineX && _checkpoint) {
      _checkpoint = false;
      if (race.started) race.completeLap();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    visual.paint(canvas, _heading - math.pi / 2);
    canvas.restore();
  }
}
