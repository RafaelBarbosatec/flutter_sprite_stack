import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';

/// Engine-free 3D diorama: an orbiting camera over sprite stacks placed on a
/// ground grid. Drag to orbit; the props use the default world-aligned
/// behaviour, so they stay aligned with the ground grid and the orbit reads as
/// a camera circling a fixed diorama.
class OrbitSceneScreen extends StatefulWidget {
  const OrbitSceneScreen({super.key});

  @override
  State<OrbitSceneScreen> createState() => _OrbitSceneScreenState();
}

class _OrbitSceneScreenState extends State<OrbitSceneScreen>
    with SingleTickerProviderStateMixin {
  final SpriteStackCache _cache = SpriteStackCache();
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  late final SpriteStackScene _scene;
  late final Ticker _ticker;
  late final SpriteStackQualityGovernor _governor;

  double _yaw = 0.85;
  double _pitch = 0.6;
  double _time = 0;
  Duration _lastElapsed = Duration.zero;
  bool _autoRotate = true;
  bool _dragging = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scene = SpriteStackScene(
      camera: SpriteStackCamera.orbit(
        yaw: _yaw,
        pitch: _pitch,
        distance: 900,
        target: const SpriteStackPoint(0, 0, 30),
      ),
      zoom: 2.4,
      sky: const SpriteStackSky(
        top: Color(0xFF070D16),
        horizon: Color(0xFF27435E),
        bottom: Color(0xFF16232F),
      ),
      ground: const SpriteStackGround(
        extent: 700,
        step: 70,
        color: Color(0x332E4050),
        axisColor: Color(0x664E6A84),
        cellSize: 70,
        checker: [Color(0xFF142430), Color(0xFF1D303D)],
        fadeColor: Color(0xFF16232F),
        fadeDistance: 2400,
      ),
    );
    _ticker = createTicker(_tick)..start();
    _governor = SpriteStackQualityGovernor();
    // A paused orbit paints the same frame over and over: replay it instead of
    // re-rasterising every prop.
    _scene.cacheStillFrames = true;
    _load();
  }

  Future<void> _load() async {
    try {
      final car = await _cache.load('sprites/car/slices.png', sliceCount: 15);
      final house =
          await _cache.load('sprites/house/slices.png', sliceCount: 29);
      final tree = await _cache.load('sprites/tree/slices.png', sliceCount: 43);
      final palm =
          await _cache.load('sprites/palmeira/slices.png', sliceCount: 26);
      if (!mounted) return;
      _scene.objects.addAll([
        SpriteStackSceneObject(
          stack: house,
          position: const SpriteStackPoint(-230, -40, 0),
          yaw: 0.5,
        ),
        SpriteStackSceneObject(
          stack: tree,
          position: const SpriteStackPoint(180, 130, 0),
          yaw: 0.2,
          scale: 1.1,
        ),
        SpriteStackSceneObject(
          stack: palm,
          position: const SpriteStackPoint(260, -140, 0),
          yaw: 1.2,
        ),
        SpriteStackSceneObject(
          stack: car,
          position: const SpriteStackPoint(-40, 150, 0),
          yaw: 2.4,
          scale: 0.9,
        ),
        SpriteStackSceneObject(
          stack: car,
          position: const SpriteStackPoint(-80, -170, 0),
          yaw: 0.6,
          scale: 0.9,
        ),
      ]);
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
    _time += dt;
    if (_autoRotate && !_dragging) _yaw += dt * 0.18;

    // The picture only changes while the camera does. A change of detail waits
    // for exactly that: it is invisible while the view moves.
    if (dt > 0) {
      final detail = _governor.frame(
        dt * 1000,
        moving: _dragging || _autoRotate,
      );
      if (detail != null) _scene.applyDetail(detail);
    }

    _scene.camera
      ..yaw = _yaw
      ..pitch = _pitch;
    for (final object in _scene.objects) {
      object.time = _time;
    }
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
      appBar: AppBar(title: const Text('Orbit scene')),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => _dragging = true,
        onPanUpdate: (details) {
          _yaw -= details.delta.dx * 0.008;
          _pitch = (_pitch - details.delta.dy * 0.006).clamp(0.02, 1.35);
        },
        onPanEnd: (_) => _dragging = false,
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _ScenePainter(_scene, _frame),
                ),
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
              bottom: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ValueListenableBuilder<int>(
                  valueListenable: _frame,
                  builder: (context, _, __) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.view_in_ar,
                        size: 13,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'q${_governor.level} · '
                        '${_scene.stats.slicesDrawn}/${_scene.stats.slicesTotal} '
                        'slices · ${_scene.stillFrameHits} cached',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _autoRotate = !_autoRotate),
        icon: Icon(_autoRotate ? Icons.pause : Icons.play_arrow),
        label: Text(_autoRotate ? 'Pause orbit' : 'Auto orbit'),
      ),
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
