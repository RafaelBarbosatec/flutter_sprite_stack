import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';

/// Banked flight: a spaceship laps a stadium-shaped track (two straights, two
/// turns) in the air while the camera chases it and the hull rolls into every
/// turn.
///
/// The straights matter: the camera's yaw holds constant while the ship flies
/// one, so the ground grid and every prop glide past in a predictable
/// straight line below, instead of sweeping around the way they would on a
/// track that never stops curving. The roll comes from the heading change:
/// `roll = k * dYaw/dt`, clamped and smoothed. The ship is world-aligned and
/// viewed from behind, so a left turn banks the hull left on screen (a
/// negative screen-space roll).
class FlightScreen extends StatefulWidget {
  const FlightScreen({super.key});

  @override
  State<FlightScreen> createState() => _FlightScreenState();
}

class _FlightScreenState extends State<FlightScreen>
    with SingleTickerProviderStateMixin {
  static const double _speed = 280; // world units per second
  static const double _cruiseAltitude = 170;
  static const double _maxBank = 0.85; // ~49 degrees

  final SpriteStackCache _cache = SpriteStackCache();
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  final _Track _track = const _Track(straight: 650, radius: 280);

  late final SpriteStackScene _scene;
  late final SpriteStackSceneObject _ship;
  late final SpriteStackFollowCamera _follow;
  late final Ticker _ticker;

  double _distance = 0;
  double _roll = 0;

  /// Multiplier on the bank derived from the turn rate. The slider drives it,
  /// so `0` flies level and `2.5` banks past the clamp as soon as it turns.
  double _bankGain = 1.15;
  double _lastYaw = 0;
  Duration _lastElapsed = Duration.zero;
  bool _paused = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scene = SpriteStackScene(
      camera: SpriteStackCamera.orbit(
        yaw: 0,
        pitch: 0.45,
        distance: 1000,
        target: const SpriteStackPoint(0, 0, 200),
      ),
      zoom: 1.5,
      sky: const SpriteStackSky(
        top: Color(0xFF05090F),
        horizon: Color(0xFF2C4C6B),
        bottom: Color(0xFF16232F),
      ),
      ground: const SpriteStackGround(
        extent: 1000,
        step: 100,
        color: Color(0x2A2E4050),
        axisColor: Color(0x554E6A84),
        cellSize: 100,
        checker: [Color(0xFF101B26), Color(0xFF16232F)],
        fadeColor: Color(0xFF16232F),
        fadeDistance: 2600,
      ),
    );
    _follow = SpriteStackFollowCamera(
      // Chase behind the ship; a long distance keeps the scenery in front of
      // the camera with a gentle perspective, like the OrbitScene example.
      positionRate: 5,
      yawRate: 2.4,
      lookAhead: 70,
      height: 30,
    );
    _ticker = createTicker(_tick)..start();
    _load();
  }

  Future<void> _load() async {
    try {
      final ship =
          await _cache.load('sprites/spaceship/slices.png', sliceCount: 21);
      final tree = await _cache.load('sprites/tree/slices.png', sliceCount: 43);
      final palm =
          await _cache.load('sprites/palmeira/slices.png', sliceCount: 26);
      if (!mounted) return;

      _ship = SpriteStackSceneObject(
        stack: ship,
        position: const SpriteStackPoint(0, 0, _cruiseAltitude),
        scale: 1,
        // World-aligned (the default) so it turns and banks on its heading;
        // the ground props below are world-aligned too, so they stay fixed on
        // the map while the camera flies past.
        billboard: false,
        // An airborne prop should not carry the ground shadow baked under its
        // feet; the shadow would float with it.
        shadow: false,
        rollPivot: 0.45,
      );
      _scene.objects.add(_ship);

      final random = math.Random(11);
      final props = <SpriteStack>[tree, palm];
      for (var i = 0; i < 12; i++) {
        // Spread evenly along the lap, offset to either side of the track so
        // the ship passes near them without flying through them.
        final distance = (i + random.nextDouble() * 0.7) * _track.length / 12;
        final point = _track.pointAt(distance);
        final ahead = _track.pointAt(distance + 4);
        final headingX = ahead.dx - point.dx;
        final headingY = ahead.dy - point.dy;
        final headingLength = math.sqrt(
          headingX * headingX + headingY * headingY,
        );
        final normalX = headingLength > 0 ? -headingY / headingLength : 1.0;
        final normalY = headingLength > 0 ? headingX / headingLength : 0.0;
        final side = random.nextBool() ? 1.0 : -1.0;
        final offset = (220 + random.nextDouble() * 260) * side;
        _scene.objects.add(
          SpriteStackSceneObject(
            stack: props[i % props.length],
            position: SpriteStackPoint(
              point.dx + normalX * offset,
              point.dy + normalY * offset,
              0,
            ),
            yaw: random.nextDouble() * math.pi * 2,
            scale: 1.1 + random.nextDouble() * 0.6,
          ),
        );
      }

      final start = _poseAt(0);
      _lastYaw = start.yaw;
      _scene.camera
        ..target = start.position + const SpriteStackPoint(0, 0, 30)
        ..yaw = start.yaw;

      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  _Pose _poseAt(double distance) {
    final point = _track.pointAt(distance);
    final ahead = _track.pointAt(distance + 4);
    final vx = ahead.dx - point.dx;
    final vy = ahead.dy - point.dy;
    final altitude = _cruiseAltitude +
        math.sin(distance / _track.length * 2 * math.pi * 2) * 45;
    return _Pose(
      position: SpriteStackPoint(point.dx, point.dy, altitude),
      velocity: SpriteStackPoint(vx, vy, 0),
      // Asset convention: the front of the prop is +Y in the source art.
      yaw: math.atan2(vy, vx) - math.pi / 2,
    );
  }

  void _tick(Duration elapsed) {
    final dt = _lastElapsed == Duration.zero
        ? 0.0
        : (elapsed - _lastElapsed).inMicroseconds / 1000000;
    _lastElapsed = elapsed;

    if (_loading || dt <= 0) {
      _frame.value++;
      return;
    }

    if (!_paused) _distance += dt * _speed;
    final pose = _poseAt(_distance);

    if (!_paused) {
      // Bank into the turn. The ship is drawn from behind (billboard: false +
      // the follow camera), so a left turn (positive heading rate) banks the
      // hull left on screen — a negative roll in Flutter's screen space.
      final turnRate = _wrap(pose.yaw - _lastYaw) / dt;
      final wanted =
          (-turnRate * _bankGain).clamp(-_maxBank, _maxBank).toDouble();
      _roll += (wanted - _roll) * (1 - math.exp(-4 * dt));
      _lastYaw = pose.yaw;
    }

    _ship
      ..position = pose.position
      ..yaw = pose.yaw
      ..roll = _roll;

    _follow.update(
      _scene.camera,
      subject: pose.position,
      yaw: pose.yaw,
      velocity: pose.velocity,
      dt: _paused ? 0 : dt,
    );
    _frame.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    _cache.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Banked flight')),
      body: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _ScenePainter(_scene, _frame)),
            ),
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ),
          Positioned(
            left: 12,
            top: 12,
            child: _Pill(
              child: ValueListenableBuilder<int>(
                valueListenable: _frame,
                builder: (context, _, __) {
                  final degrees = (_roll * 180 / math.pi).abs();
                  final stats = _scene.stats;
                  return Text(
                    'bank ${degrees.toStringAsFixed(0)}° · '
                    '${stats.drawn} drawn · ${stats.culled} culled',
                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                  );
                },
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _Pill(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => setState(() => _paused = !_paused),
                        icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                        color: Colors.white70,
                        iconSize: 20,
                      ),
                      const Text(
                        'lag',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                      Expanded(
                        child: Slider(
                          value: _follow.yawRate,
                          min: 0.4,
                          max: 8,
                          onChanged: (value) => setState(
                            () => _follow.yawRate = value,
                          ),
                        ),
                      ),
                      Text(
                        '${(1 / _follow.yawRate).toStringAsFixed(2)} s',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 48),
                      const Text(
                        'roll',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                      Expanded(
                        child: Slider(
                          value: _bankGain,
                          min: 0,
                          max: 2.5,
                          onChanged: (value) => setState(
                            () => _bankGain = value,
                          ),
                        ),
                      ),
                      Text(
                        '${_bankGain.toStringAsFixed(2)}×',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

double _wrap(double angle) {
  final turn = angle % (2 * math.pi);
  return turn > math.pi ? turn - 2 * math.pi : turn;
}

class _Pose {
  const _Pose({
    required this.position,
    required this.velocity,
    required this.yaw,
  });

  final SpriteStackPoint position;
  final SpriteStackPoint velocity;
  final double yaw;
}

/// A stadium-shaped track: two straights joined by two semicircular turns.
///
/// A continuously-curving closed loop (the previous shape here) never lets
/// the chase camera stop rotating to stay behind the ship, so the ground
/// sweeps past for the *entire* lap — every static prop reads as if it were
/// drifting, because the camera's viewing angle never settles. On the
/// straights of a stadium track the camera only translates (its yaw is
/// constant), so the ground grid and every prop glide past in a straight,
/// predictable line; the sweep is confined to the turns, where the camera has
/// to swing to stay behind the ship.
class _Track {
  const _Track({required this.straight, required this.radius});

  /// Length of each straight segment, in world units.
  final double straight;

  /// Radius of each semicircular turn, in world units.
  final double radius;

  double get _turnLength => math.pi * radius;

  /// Total length of one lap.
  double get length => 2 * straight + 2 * _turnLength;

  /// Point [distance] units along the track, wrapping around.
  Offset pointAt(double distance) {
    final turnLength = _turnLength;
    var d = distance % length;
    if (d < 0) d += length;
    if (d < straight) {
      return Offset(-straight / 2 + d, -radius);
    }
    d -= straight;
    if (d < turnLength) {
      final angle = -math.pi / 2 + d / radius;
      return Offset(
        straight / 2 + radius * math.cos(angle),
        radius * math.sin(angle),
      );
    }
    d -= turnLength;
    if (d < straight) {
      return Offset(straight / 2 - d, radius);
    }
    d -= straight;
    final angle = math.pi / 2 + d / radius;
    return Offset(
      -straight / 2 + radius * math.cos(angle),
      radius * math.sin(angle),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, Listenable repaint) : super(repaint: repaint);

  final SpriteStackScene scene;

  @override
  void paint(Canvas canvas, Size size) => scene.paint(canvas, size);

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) =>
      oldDelegate.scene != scene;
}
