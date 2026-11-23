import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';

/// Animated sprite stack demo: a torch whose flame flickers across 8 frames.
///
/// The atlas (`sprites/torch/frames.png`) stores the frames vertically, each one
/// a normal horizontal slice strip. `SpriteStackAnimation` only decides which
/// frame is visible; the painter draws it like any other stack.
class TorchScreen extends StatefulWidget {
  const TorchScreen({super.key});

  @override
  State<TorchScreen> createState() => _TorchScreenState();
}

class _TorchScreenState extends State<TorchScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  SpriteStackAnimation? _animation;
  Object? _error;

  Duration _last = Duration.zero;
  double _yaw = 0.5;
  double _speed = 1;
  static const int _sliceCount = 32;
  static const double _scale = 8;
  bool _spinning = true;

  @override
  void initState() {
    super.initState();
    SpriteStackAnimation.load(
      'sprites/torch/frames.png',
      sliceCount: _sliceCount,
      frameCount: 8,
      frameDuration: 0.08,
    ).then((animation) {
      if (!mounted) {
        animation.stack.dispose();
        return;
      }
      setState(() => _animation = animation);
    }, onError: (Object error) {
      if (mounted) setState(() => _error = error);
    });
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final delta = (elapsed - _last).inMicroseconds / 1000000;
    _last = elapsed;
    final animation = _animation;
    if (animation == null) return;

    animation.update(delta * _speed);
    setState(() {
      if (_spinning) _yaw += delta * 1.1;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _animation?.stack.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animation = _animation;
    return Scaffold(
      backgroundColor: const Color(0xFF0F1220),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1220),
        foregroundColor: Colors.white,
        title: const Text('Animated sprite stack'),
        actions: [
          IconButton(
            tooltip: _spinning ? 'Stop spinning' : 'Spin',
            isSelected: _spinning,
            icon: const Icon(Icons.threesixty),
            selectedIcon: const Icon(Icons.pause_circle_outline),
            onPressed: () => setState(() => _spinning = !_spinning),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text('Failed to load the torch: $_error'))
          : animation == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: CustomPaint(
                          size: const Size(420, 420),
                          painter: _FirelightPainter(
                            stack: animation.stack,
                            time: animation.elapsed,
                            scale: _scale,
                          ),
                          foregroundPainter: SpriteStackPainter(
                            stack: animation.stack,
                            frame: animation.frame,
                            yaw: _yaw,
                            scale: _scale,
                            shadowColor: const Color(0xFF05060C),
                            outlineColor: const Color(0xFF0A0B14),
                          ),
                        ),
                      ),
                    ),
                    _Controls(
                      animation: animation,
                      speed: _speed,
                      onSpeed: (value) => setState(() => _speed = value),
                      onChanged: () => setState(() {}),
                    ),
                  ],
                ),
    );
  }
}

/// Flickering light cast by the flame: a soft halo in the air and a warm pool
/// on the ground. Drawn behind the stack, so it never touches the pixel art.
class _FirelightPainter extends CustomPainter {
  _FirelightPainter({
    required this.stack,
    required this.time,
    required this.scale,
  });

  final SpriteStack stack;
  final double time;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    // Same anchor as SpriteStackPainter: ground slice centre, bottom-centre.
    final squash = SpriteStack.squashFor(SpriteStack.defaultPitch);
    final groundY = size.height - stack.sliceHeight * squash * scale / 2;
    final centerX = size.width / 2;

    // Layered sines keep the flicker irregular without a random source.
    final flicker = 0.86 +
        0.07 * math.sin(time * 11.0) +
        0.05 * math.sin(time * 17.3 + 1.2) +
        0.03 * math.sin(time * 5.1 + 2.0);

    final flameY = groundY - 24 * scale;
    final haloRadius = 190 * flicker;
    canvas.drawCircle(
      Offset(centerX, flameY),
      haloRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFF9A3C).withValues(alpha: 0.42 * flicker),
            const Color(0xFFE2501E).withValues(alpha: 0.16 * flicker),
            const Color(0x00E2501E),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(
          Rect.fromCircle(center: Offset(centerX, flameY), radius: haloRadius),
        ),
    );

    final poolWidth = 150 * flicker;
    final pool = Rect.fromCenter(
      center: Offset(centerX, groundY + 4),
      width: poolWidth * 2,
      height: poolWidth * 2 * squash,
    );
    canvas.drawOval(
      pool,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFB04A).withValues(alpha: 0.30 * flicker),
            const Color(0x00FFB04A),
          ],
        ).createShader(pool),
    );
  }

  @override
  bool shouldRepaint(covariant _FirelightPainter oldDelegate) =>
      oldDelegate.time != time ||
      oldDelegate.stack != stack ||
      oldDelegate.scale != scale;
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.animation,
    required this.speed,
    required this.onSpeed,
    required this.onChanged,
  });

  final SpriteStackAnimation animation;
  final double speed;
  final ValueChanged<double> onSpeed;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme.apply(
          bodyColor: Colors.white70,
          displayColor: Colors.white70,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            children: [
              FilledButton.icon(
                icon:
                    Icon(animation.isPlaying ? Icons.pause : Icons.play_arrow),
                label: Text(animation.isPlaying ? 'Pause' : 'Play'),
                onPressed: () {
                  if (animation.isPlaying) {
                    animation.stop();
                  } else {
                    animation.play();
                  }
                  onChanged();
                },
              ),
              Text(
                'frame ${animation.frame + 1}/${animation.frameCount}',
                style: textTheme.titleMedium,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('loop'),
                  Switch(
                    value: animation.loop,
                    onChanged: (value) {
                      animation.loop = value;
                      onChanged();
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('speed'),
              Expanded(
                child: Slider(
                  value: speed,
                  min: 0.25,
                  max: 3,
                  divisions: 11,
                  label: '${speed.toStringAsFixed(2)}x',
                  onChanged: onSpeed,
                ),
              ),
              SizedBox(
                width: 56,
                child: Text('${speed.toStringAsFixed(2)}x'),
              ),
            ],
          ),
          Text(
            'A 32-slice strip repeated 8 times vertically. The engine draws the '
            'same number of slices every frame — only the atlas row changes.',
            style: textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
