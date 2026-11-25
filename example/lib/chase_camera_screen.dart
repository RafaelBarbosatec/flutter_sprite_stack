import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';

/// Third-person chase camera: a car laps a closed loop and the camera follows
/// it with an exponential delay.
///
/// The delay is the feature. Because the camera yaw lags behind the car yaw,
/// the car's relative yaw is non-zero in the turns, so the body rotates on
/// screen instead of the whole world spinning around a locked sprite. Drag the
/// slider to trade responsiveness for that read.
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
  final _Loop _loop = _Loop();

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
        final angle = i * 2 * math.pi / _propCount + random.nextDouble() * 0.3;
        final radius = 430 + random.nextDouble() * 190;
        _scene.objects.add(
          SpriteStackSceneObject(
            stack: props[i % props.length],
            position: SpriteStackPoint(
              math.cos(angle) * radius,
              math.sin(angle) * radius,
              0,
            ),
            yaw: random.nextDouble() * math.pi * 2,
            scale: 0.9 + random.nextDouble() * 0.5,
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
    final point = _loop.pointAt(distance);
    final ahead = _loop.pointAt(distance + 4);
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

/// A closed superellipse loop, sampled by arc length.
class _Loop {
  _Loop({int samples = 720})
      : _points = List<Offset>.filled(samples, Offset.zero),
        _turns = List<double>.filled(samples + 1, 0) {
    const a = 330.0;
    const b = 300.0;
    const exponent = 0.72;
    for (var i = 0; i < samples; i++) {
      final t = 2 * math.pi * i / samples;
      final c = math.cos(t);
      final s = math.sin(t);
      _points[i] = Offset(
        a * c.sign * math.pow(c.abs(), exponent).toDouble(),
        b * s.sign * math.pow(s.abs(), exponent).toDouble(),
      );
    }
    for (var i = 0; i < samples; i++) {
      final next = (i + 1) % samples;
      _turns[i + 1] = _turns[i] + (_points[next] - _points[i]).distance;
    }
    length = _turns[samples];
  }

  final List<Offset> _points;

  /// Cumulative arc length at each sample; the last entry is [length].
  final List<double> _turns;

  late final double length;

  /// Point [distance] units along the loop, wrapping around.
  Offset pointAt(double distance) {
    var d = distance % length;
    if (d < 0) d += length;
    var low = 0;
    var high = _points.length;
    while (low + 1 < high) {
      final mid = (low + high) >> 1;
      if (_turns[mid] <= d) {
        low = mid;
      } else {
        high = mid;
      }
    }
    final span = _turns[low + 1] - _turns[low];
    final t = span <= 0 ? 0.0 : (d - _turns[low]) / span;
    final next = (low + 1) % _points.length;
    return Offset.lerp(_points[low], _points[next], t)!;
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
