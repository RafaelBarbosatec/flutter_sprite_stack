import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';

/// Animated sprite stack demo: a torch whose flame flickers across 5 frames.
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
  final double _scale = 9;
  bool _spinning = true;

  @override
  void initState() {
    super.initState();
    SpriteStackAnimation.load(
      'sprites/torch/frames.png',
      sliceCount: 14,
      frameCount: 5,
      frameDuration: 0.13,
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
      backgroundColor: const Color(0xFFF1F4F8),
      appBar: AppBar(
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
                          painter: SpriteStackPainter(
                            stack: animation.stack,
                            frame: animation.frame,
                            yaw: _yaw,
                            scale: _scale,
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
    final textTheme = Theme.of(context).textTheme;
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
            'A 14-slice strip repeated 5 times vertically. The engine draws the '
            'same number of slices every frame — only the atlas row changes.',
            style: textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
