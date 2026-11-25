import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';

/// Walk around the diorama with a collision proxy on every prop.
///
/// Drag anywhere to push the robot: the drag is a virtual stick, mapped to the
/// camera's ground axes, so "up" always walks away from the camera. The props
/// block; the robot slides along faces instead of stopping dead. Toggle
/// collision off to walk through the same props and compare.
///
/// Every collider here is the zero-configuration kind: the footprint comes
/// from the stack volume, scaled and rotated with the object. No hand-authored
/// sizes, no art changes.
class CollisionScreen extends StatefulWidget {
  const CollisionScreen({super.key});

  @override
  State<CollisionScreen> createState() => _CollisionScreenState();
}

class _CollisionScreenState extends State<CollisionScreen>
    with SingleTickerProviderStateMixin {
  static const double _speed = 260; // world units per second
  static const double _radius = 14; // the robot's ground radius
  static const double _stickLimit = 48; // drag distance for full speed

  final SpriteStackCache _cache = SpriteStackCache();
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  late final SpriteStackScene _scene;
  late final SpriteStackSceneObject _player;
  late final SpriteStackFollowCamera _follow;
  late final Ticker _ticker;

  Offset _stick = Offset.zero;
  Offset _stickOrigin = Offset.zero;
  Duration _lastElapsed = Duration.zero;
  bool _collision = true;
  int _blocked = 0;
  bool _paused = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scene = SpriteStackScene(
      camera: SpriteStackCamera.orbit(
        yaw: 0,
        pitch: 0.5,
        distance: 720,
        target: const SpriteStackPoint(0, 0, 25),
      ),
      zoom: 2.2,
      sky: const SpriteStackSky(
        top: Color(0xFF070D16),
        horizon: Color(0xFF27435E),
        bottom: Color(0xFF16232F),
      ),
      ground: SpriteStackGround(
        extent: 700,
        step: 70,
        cellSize: 70,
        checker: const [Color(0xFF142430), Color(0xFF1D303D)],
        fadeColor: const Color(0xFF16232F),
        fadeDistance: 2200,
        colorAt: _groundColor,
      ),
    );
    _follow = SpriteStackFollowCamera(
      positionRate: 7,
      yawRate: 3.5,
      lookAhead: 45,
      height: 25,
    );
    _ticker = createTicker(_tick)..start();
    _load();
  }

  static Color _groundColor(double x, double y) {
    // A ring of slightly warmer ground around the origin, so movement reads
    // even where no prop is in frame.
    final distance = math.sqrt(x * x + y * y);
    return distance < 190 ? const Color(0xFF1B2D3A) : const Color(0xFF142430);
  }

  Future<void> _load() async {
    try {
      final robot = await _cache.load('assets/robot_stack.png', sliceCount: 24);
      final house =
          await _cache.load('sprites/house/slices.png', sliceCount: 29);
      final tree = await _cache.load('sprites/tree/slices.png', sliceCount: 43);
      final palm =
          await _cache.load('sprites/palmeira/slices.png', sliceCount: 26);
      final car = await _cache.load('sprites/car/slices.png', sliceCount: 15);
      if (!mounted) return;

      _player = SpriteStackSceneObject(
        stack: robot,
        position: SpriteStackPoint.zero,
        scale: 1.4,
      );
      _scene.objects.addAll([
        _player,
        SpriteStackSceneObject(
          stack: house,
          position: const SpriteStackPoint(-230, -40, 0),
          yaw: 0.5,
          scale: 1.1,
          collider: const SpriteStackCollider(padding: 2),
        ),
        SpriteStackSceneObject(
          stack: tree,
          position: const SpriteStackPoint(180, 130, 0),
          yaw: 0.2,
          scale: 1.2,
          collider: const SpriteStackCollider(padding: 2),
        ),
        SpriteStackSceneObject(
          stack: palm,
          position: const SpriteStackPoint(260, -140, 0),
          yaw: 1.2,
          scale: 1.1,
          collider: const SpriteStackCollider(padding: 2),
        ),
        SpriteStackSceneObject(
          stack: car,
          position: const SpriteStackPoint(-40, 150, 0),
          yaw: 2.4,
          collider: const SpriteStackCollider(),
        ),
      ]);

      _scene.camera
        ..target = const SpriteStackPoint(0, 40, 25)
        ..yaw = 0;

      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  void _tick(Duration elapsed) {
    final dt = _lastElapsed == Duration.zero
        ? 0.0
        : (elapsed - _lastElapsed).inMicroseconds / 1000000;
    _lastElapsed = elapsed;

    if (_loading || _error != null || dt <= 0) {
      _frame.value++;
      return;
    }

    final direction = _groundDirection();
    final velocity = direction * _speed;
    if (!_paused && direction != Offset.zero) {
      final delta = velocity * dt;
      if (_collision) {
        final result = _scene.move(
          _player.position,
          delta: delta,
          radius: _radius,
          ignore: _player,
        );
        _blocked = result.hits.length;
        _player.position = result.position;
      } else {
        _blocked = 0;
        _player.position = SpriteStackPoint(
          _player.position.x + delta.dx,
          _player.position.y + delta.dy,
          _player.position.z,
        );
      }
      // Asset convention: the front of the prop is +Y, so the yaw that points
      // the body along the velocity is `atan2(vy, vx) - pi / 2`.
      _player.yaw = math.atan2(velocity.dy, velocity.dx) - math.pi / 2;
    } else {
      _blocked = 0;
    }

    _follow.update(
      _scene.camera,
      subject: _player.position,
      yaw: _player.yaw,
      velocity: _paused ? null : SpriteStackPoint(velocity.dx, velocity.dy, 0),
      dt: _paused ? 0 : dt,
    );

    _frame.value++;
  }

  /// Maps the drag stick to the camera's ground axes: dragging up walks away
  /// from the camera, dragging right walks to screen right, whatever the orbit.
  Offset _groundDirection() {
    if (_stick == Offset.zero) return Offset.zero;
    final forward3 = _scene.camera.basis.forward;
    final length = math.sqrt(
      forward3.x * forward3.x + forward3.y * forward3.y,
    );
    if (length < 1e-6) return Offset.zero;
    final forward = Offset(forward3.x / length, forward3.y / length);
    final right = Offset(-forward.dy, forward.dx);

    final raw = right * (_stick.dx / _stickLimit) +
        forward * (-_stick.dy / _stickLimit);
    final magnitude = raw.distance;
    return magnitude <= 1 ? raw : raw / magnitude;
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
      appBar: AppBar(title: const Text('Walk with collision')),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          _stickOrigin = details.localPosition;
          setState(() => _stick = Offset.zero);
        },
        onPanUpdate: (details) {
          final offset = details.localPosition - _stickOrigin;
          setState(() {
            _stick = offset.distance > _stickLimit
                ? offset / offset.distance * _stickLimit
                : offset;
          });
        },
        onPanEnd: (_) => setState(() => _stick = Offset.zero),
        onPanCancel: () => setState(() => _stick = Offset.zero),
        child: Stack(
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
                  builder: (context, _, __) => Text(
                    '${_scene.stats.drawn} drawn · '
                    '${_collision ? 'collision on' : 'collision off'} · '
                    '$_blocked blocked',
                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                  ),
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
                      'collision',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    Switch(
                      value: _collision,
                      onChanged: (value) => setState(() => _collision = value),
                    ),
                    const Expanded(
                      child: Text(
                        'drag to walk',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 10, color: Colors.white54),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_stick != Offset.zero)
              Positioned(
                left: _stickOrigin.dx - 26,
                top: _stickOrigin.dy - 26,
                child: IgnorePointer(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Transform.translate(
                            offset: _stick * 0.5,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white24,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
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
