import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';

/// Interactive military attack helicopter demo showcasing animated sprite stacking.
///
/// The helicopter atlas (`sprites/helicopter/frames.png`) contains 8 frames,
/// each with 24 horizontal slices. It features:
/// - 4-blade long main rotor spinning overhead with high-vis yellow tips.
/// - 4-blade tail rotor spinning vertically on the starboard vertical fin.
/// - Controls for RPM / Rotor Speed (Idle to Full Combat RPM).
/// - Flight altitude / Hover mode (simulating landing vs flying with ground shadow offset).
/// - Interactive Yaw and Pitch controls (manual drag or auto 360° spin).
class HelicopterScreen extends StatefulWidget {
  const HelicopterScreen({super.key});

  @override
  State<HelicopterScreen> createState() => _HelicopterScreenState();
}

class _HelicopterScreenState extends State<HelicopterScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  SpriteStackAnimation? _animation;
  Object? _error;

  Duration _last = Duration.zero;
  double _yaw = 0.65;
  double _pitch = SpriteStack.defaultPitch;
  double _scale = 4.2;
  double _spacing = 1.0;
  bool _spinning = true;
  bool _hovering = true;
  bool _outline = true;
  bool _shadow = true;
  double _rpmSpeed = 1.2; // Speed multiplier for the rotor frames
  double _time = 0;

  static const int _sliceCount = 24;
  static const int _frameCount = 8;
  static const double _baseFrameDuration = 0.055; // Fast base rotor cycle

  @override
  void initState() {
    super.initState();
    SpriteStackAnimation.load(
      'sprites/helicopter/frames.png',
      sliceCount: _sliceCount,
      frameCount: _frameCount,
      frameDuration: _baseFrameDuration,
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

    _time += delta;
    if (_rpmSpeed > 0) {
      animation.update(delta * _rpmSpeed);
    }

    setState(() {
      if (_spinning) {
        _yaw += delta * 0.9;
      }
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

    // Hover effect: helicopter bobs gently up and down and tilts slightly in flight
    final hoverLift = _hovering ? math.sin(_time * 2.8) * 8.0 - 24.0 : 0.0;
    final hoverTilt = _hovering ? math.sin(_time * 2.1) * 0.04 : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF10141A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF10141A),
        foregroundColor: Colors.white,
        title: const Text('AH-64 Viper / Animated Helicopter'),
        actions: [
          IconButton(
            tooltip: _spinning ? 'Stop spinning' : 'Auto spin',
            icon:
                Icon(_spinning ? Icons.pause_circle_outline : Icons.threesixty),
            onPressed: () => setState(() => _spinning = !_spinning),
          ),
          IconButton(
            tooltip: _hovering ? 'Land helicopter' : 'Take off & Hover',
            icon: Icon(_hovering ? Icons.flight_land : Icons.flight_takeoff),
            onPressed: () => setState(() => _hovering = !_hovering),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load helicopter: $_error',
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : animation == null
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  child: Column(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              _spinning = false;
                              _yaw += details.delta.dx * 0.015;
                              _pitch = (_pitch + details.delta.dy * 0.005)
                                  .clamp(0.2, 1.4);
                            });
                          },
                          child: Center(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Helipad markings on the ground
                                Transform.translate(
                                  offset: Offset(0, 100),
                                  child: CustomPaint(
                                    size: const Size(360, 360),
                                    painter: _HelipadPainter(
                                      scale: _scale,
                                      hovering: _hovering,
                                    ),
                                  ),
                                ),
                                // The animated sprite stack
                                Transform.translate(
                                  offset: Offset(0, hoverLift),
                                  child: CustomPaint(
                                    size: const Size(440, 440),
                                    foregroundPainter: SpriteStackPainter(
                                      stack: animation.stack,
                                      frame: animation.frame,
                                      yaw: _yaw,
                                      pitch: _pitch + hoverTilt,
                                      scale: _scale,
                                      spacing: _spacing,
                                      outline: _outline,
                                      shadow: _shadow,
                                      shadowColor: const Color(0x66000000),
                                      outlineColor: const Color(0xFF0D1217),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _HelicopterControls(
                        animation: animation,
                        rpmSpeed: _rpmSpeed,
                        scale: _scale,
                        spacing: _spacing,
                        pitch: _pitch,
                        hovering: _hovering,
                        spinning: _spinning,
                        outline: _outline,
                        shadow: _shadow,
                        onRpmChanged: (v) => setState(() => _rpmSpeed = v),
                        onScaleChanged: (v) => setState(() => _scale = v),
                        onSpacingChanged: (v) => setState(() => _spacing = v),
                        onPitchChanged: (v) => setState(() => _pitch = v),
                        onHoverToggle: () =>
                            setState(() => _hovering = !_hovering),
                        onSpinToggle: () =>
                            setState(() => _spinning = !_spinning),
                        onOutlineToggle: () =>
                            setState(() => _outline = !_outline),
                        onShadowToggle: () =>
                            setState(() => _shadow = !_shadow),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _HelicopterControls extends StatelessWidget {
  const _HelicopterControls({
    required this.animation,
    required this.rpmSpeed,
    required this.scale,
    required this.spacing,
    required this.pitch,
    required this.hovering,
    required this.spinning,
    required this.outline,
    required this.shadow,
    required this.onRpmChanged,
    required this.onScaleChanged,
    required this.onSpacingChanged,
    required this.onPitchChanged,
    required this.onHoverToggle,
    required this.onSpinToggle,
    required this.onOutlineToggle,
    required this.onShadowToggle,
  });

  final SpriteStackAnimation animation;
  final double rpmSpeed;
  final double scale;
  final double spacing;
  final double pitch;
  final bool hovering;
  final bool spinning;
  final bool outline;
  final bool shadow;
  final ValueChanged<double> onRpmChanged;
  final ValueChanged<double> onScaleChanged;
  final ValueChanged<double> onSpacingChanged;
  final ValueChanged<double> onPitchChanged;
  final VoidCallback onHoverToggle;
  final VoidCallback onSpinToggle;
  final VoidCallback onOutlineToggle;
  final VoidCallback onShadowToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Rotor RPM Slider
          Row(
            children: [
              const Icon(Icons.sync, size: 20, color: Color(0xFF6FA0FF)),
              const SizedBox(width: 8),
              Text(
                'Rotor RPM (${(rpmSpeed * 100).round()}%)',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Expanded(
                child: Slider(
                  value: rpmSpeed,
                  min: 0.0,
                  max: 3.0,
                  divisions: 30,
                  label: '${(rpmSpeed * 100).round()}%',
                  onChanged: onRpmChanged,
                ),
              ),
              Text(
                'Frame ${animation.frame + 1}/${animation.frameCount}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          // Scale Slider
          Row(
            children: [
              const Icon(Icons.zoom_in, size: 20, color: Color(0xFF6FA0FF)),
              const SizedBox(width: 8),
              Text('Scale: ${scale.toStringAsFixed(1)}x'),
              Expanded(
                child: Slider(
                  value: scale,
                  min: 2.0,
                  max: 6.0,
                  divisions: 20,
                  onChanged: onScaleChanged,
                ),
              ),
              const SizedBox(width: 12),
              // Camera Pitch Slider
              const Icon(Icons.height, size: 20, color: Color(0xFF6FA0FF)),
              const SizedBox(width: 6),
              Text('Pitch: ${pitch.toStringAsFixed(2)}'),
              Expanded(
                child: Slider(
                  value: pitch,
                  min: 0.3,
                  max: 1.3,
                  divisions: 20,
                  onChanged: onPitchChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Action Buttons / Toggles
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilterChip(
                label: const Text('Hover / Flight'),
                selected: hovering,
                avatar: Icon(
                  hovering ? Icons.air : Icons.flight_land,
                  size: 18,
                ),
                onSelected: (_) => onHoverToggle(),
              ),
              FilterChip(
                label: const Text('Auto Spin'),
                selected: spinning,
                avatar: Icon(
                  spinning ? Icons.autorenew : Icons.touch_app,
                  size: 18,
                ),
                onSelected: (_) => onSpinToggle(),
              ),
              FilterChip(
                label: const Text('Outline'),
                selected: outline,
                avatar: const Icon(Icons.border_outer, size: 18),
                onSelected: (_) => onOutlineToggle(),
              ),
              FilterChip(
                label: const Text('Shadow'),
                selected: shadow,
                avatar: const Icon(Icons.wb_sunny_outlined, size: 18),
                onSelected: (_) => onShadowToggle(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Draws an atmospheric military landing pad below the helicopter.
class _HelipadPainter extends CustomPainter {
  const _HelipadPainter({required this.scale, required this.hovering});

  final double scale;
  final bool hovering;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 15);

    // Tarmac ground circle
    final tarmacPaint = Paint()
      ..color = const Color(0xFF1A1F27)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 280, height: 160),
      tarmacPaint,
    );

    // Helipad yellow circle outline
    final linePaint = Paint()
      ..color = const Color(0x77E2B024)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 240, height: 130),
      linePaint,
    );

    // Yellow letter "H" on helipad
    final hPaint = Paint()
      ..color = const Color(0x66E2B024)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.square;

    const hx = 22.0;
    const hy = 16.0;
    // Left vertical bar of H
    canvas.drawLine(
      Offset(center.dx - hx, center.dy - hy),
      Offset(center.dx - hx, center.dy + hy),
      hPaint,
    );
    // Right vertical bar of H
    canvas.drawLine(
      Offset(center.dx + hx, center.dy - hy),
      Offset(center.dx + hx, center.dy + hy),
      hPaint,
    );
    // Crossbar of H
    canvas.drawLine(
      Offset(center.dx - hx, center.dy),
      Offset(center.dx + hx, center.dy),
      hPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _HelipadPainter oldDelegate) =>
      oldDelegate.hovering != hovering;
}
