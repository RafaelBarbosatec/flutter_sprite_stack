import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';

/// Third-person chase camera: a car laps a stadium-shaped track (two
/// straights, two turns) and the camera follows it with an exponential delay.
///
/// The straights are the point: the camera's yaw stays constant while the car
/// drives one, so the ground grid and every prop glide past in a predictable
/// straight line instead of sweeping around like they would on a track that
/// never stops curving. The delay is the other feature: because the camera
/// yaw lags behind the car yaw in the turns, the car's relative yaw is
/// non-zero there, so the body rotates on screen instead of the whole world
/// spinning around a locked sprite. Drag the slider to trade responsiveness
/// for that read.
class ChaseCameraScreen extends StatefulWidget {
  const ChaseCameraScreen({super.key});

  @override
  State<ChaseCameraScreen> createState() => _ChaseCameraScreenState();
}

class _ChaseCameraScreenState extends State<ChaseCameraScreen>
    with SingleTickerProviderStateMixin {
  static const double _speed = 190; // world units per second
  static const int _propCount = 14;

  final SpriteStackCache _cache = SpriteStackCache();
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  final _Track _track = const _Track(straight: 450, radius: 200);

  late final SpriteStackScene _scene;
  late final SpriteStackSceneObject _car;
  late final SpriteStackFollowCamera _follow;
  late final Ticker _ticker;

  double _distance = 120;
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
        pitch: 0.55,
        distance: 900,
        target: const SpriteStackPoint(0, 0, 30),
      ),
      zoom: 2.0,
      sky: const SpriteStackSky(
        top: Color(0xFF070D16),
        horizon: Color(0xFF27435E),
        bottom: Color(0xFF16232F),
      ),
      ground: const SpriteStackGround(
        extent: 900,
        step: 90,
        color: Color(0x332E4050),
        axisColor: Color(0x664E6A84),
        cellSize: 90,
        checker: [Color(0xFF142430), Color(0xFF1D303D)],
        fadeColor: Color(0xFF16232F),
        fadeDistance: 2400,
      ),
    );
    _follow = SpriteStackFollowCamera(
      // Chase behind the car; a long distance keeps the scenery in front of
      // the camera with a gentle perspective, like the OrbitScene example.
      positionRate: 6,
      yawRate: 3,
      lookAhead: 55,
      height: 30,
    );
    _ticker = createTicker(_tick)..start();
    _load();
  }

  Future<void> _load() async {
    try {
      final car = await _cache.load('sprites/car/slices.png', sliceCount: 15);
      final tree = await _cache.load('sprites/tree/slices.png', sliceCount: 43);
      final palm =
          await _cache.load('sprites/palmeira/slices.png', sliceCount: 26);
      final house =
          await _cache.load('sprites/house/slices.png', sliceCount: 29);
      if (!mounted) return;

      _car = SpriteStackSceneObject(
        stack: car,
        position: const SpriteStackPoint(0, 0, 0),
        scale: 1,
        // World-aligned (the default) so the body turns with the heading;
        // the scenery around it is world-aligned too, so it stays fixed on
        // the map while the camera drives past.
        billboard: false,
      );
      _scene.objects.add(_car);

      final random = math.Random(7);
      final props = <SpriteStack>[tree, palm, house];
      for (var i = 0; i < _propCount; i++) {
        // Spread evenly along the lap, offset to either side of the track so
        // the car passes near them without driving through them.
        final distance =
            (i + random.nextDouble() * 0.7) * _track.length / _propCount;
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
        final offset = (140 + random.nextDouble() * 220) * side;
        _scene.objects.add(
          SpriteStackSceneObject(
            stack: props[i % props.length],
            position: SpriteStackPoint(
              point.dx + normalX * offset,
              point.dy + normalY * offset,
              0,
            ),
            // yaw: random.nextDouble() * math.pi * 2,
            scale: 1.5 + random.nextDouble() * 0.5,
          ),
        );
      }

      // Start the camera already behind the car, not swooping in from origin.
      final start = _poseAt(0);
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
    return _Pose(
      position: SpriteStackPoint(point.dx, point.dy, 0),
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

    // The ticker runs while the sprites load; nothing to drive until then.
    if (_loading || dt <= 0) {
      _frame.value++;
      return;
    }

    if (!_paused) _distance += dt * _speed;

    final pose = _poseAt(_distance);
    _car
      ..position = pose.position
      ..yaw = pose.yaw;

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
      appBar: AppBar(title: const Text('Chase camera')),
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
                  final stats = _scene.stats;
                  return Text(
                    '${stats.drawn} drawn · ${stats.culled} culled · '
                    '${stats.behindCamera} behind · '
                    '${stats.tooSmall} tiny',
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
              child: Row(
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
            ),
          ),
        ],
      ),
    );
  }
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
/// the chase camera stop rotating to stay behind the car, so the background
/// sweeps past for the *entire* lap — every static prop reads as if it were
/// drifting, because the camera's viewing angle never settles. On the
/// straights of a stadium track the camera only translates (its yaw is
/// constant), so the ground grid and every prop glide past in a straight,
/// predictable line, the way driving past roadside scenery actually looks;
/// the sweep is confined to the turns, where the camera has to swing to stay
/// behind the car — exactly like a racing game's chase cam.
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
