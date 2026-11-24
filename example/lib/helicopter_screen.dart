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
///
/// The layout is phone-first: the stage auto-fits the projected bounds so the
/// helicopter never overflows, and the control sheet is compact and scrollable.
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
  final double _spacing = 1.0;
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

  /// Largest art-pixel scale that keeps the prop inside the stage.
  ///
  /// Uses the worst-case footprint over every yaw (the stack diagonal), so the
  /// size does not pulse while it spins. Height is estimated conservatively
  /// from the 45° projection plus the slice lift.
  double _fitScale(SpriteStack stack, Size stage) {
    final w = stack.sliceWidth.toDouble();
    final h = stack.sliceHeight.toDouble();
    final n = stack.sliceCount.toDouble();
    final squash = SpriteStack.squashFor(_pitch);
    final maxWidth = math.sqrt(w * w + h * h) + 8; // outline + shadow margin
    final maxHeight = ((w + h) / math.sqrt2) * squash + (n - 1) * _spacing + 36;
    final fit = math.min(
      (stage.width - 20) / maxWidth,
      (stage.height - 28) / maxHeight,
    );
    return fit.clamp(0.8, 10.0);
  }

  @override
  Widget build(BuildContext context) {
    final animation = _animation;
    final isPhone = MediaQuery.sizeOf(context).width < 420;

    return Scaffold(
      backgroundColor: const Color(0xFF10141A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF10141A),
        foregroundColor: Colors.white,
        title: Text(isPhone ? 'AH-64 Viper' : 'AH-64 Viper / Helicopter'),
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
                  child: LayoutBuilder(
                    builder: (context, body) {
                      // The sheet never takes more than 42% of the body, so the
                      // stage always keeps a usable share on short screens.
                      final reserve = math.min(
                        300.0,
                        math.max(150.0, body.maxHeight * 0.42),
                      );
                      final stage = Size(
                        body.maxWidth,
                        math.max(120.0, body.maxHeight - reserve),
                      );
                      final fit = _fitScale(animation.stack, stage);
                      final minScale = math.max(0.8, fit * 0.55);
                      final maxScale = math.max(minScale + 0.5, fit * 1.7);
                      final scale = _scale.clamp(minScale, maxScale);
                      // On short screens the pitch slider is dropped; dragging
                      // vertically already tilts the camera, and it keeps the
                      // sheet from scrolling.
                      final showPitch = body.maxHeight >= 620;

                      // Hover: bob and tilt, lifting off the pad.
                      final hoverLift = _hovering
                          ? -math.max(
                                  10.0, math.min(30.0, stage.height * 0.08)) +
                              math.sin(_time * 2.8) * 5
                          : 0.0;
                      final hoverTilt =
                          _hovering ? math.sin(_time * 2.1) * 0.04 : 0.0;

                      return Column(
                        children: [
                          Expanded(
                            child: _Stage(
                              animation: animation,
                              yaw: _yaw,
                              pitch: _pitch + hoverTilt,
                              scale: scale,
                              spacing: _spacing,
                              hoverLift: hoverLift,
                              hovering: _hovering,
                              outline: _outline,
                              shadow: _shadow,
                              onRotate: (dx, dy) {
                                setState(() {
                                  _spinning = false;
                                  _yaw += dx * 0.013;
                                  _pitch =
                                      (_pitch + dy * 0.005).clamp(0.2, 1.4);
                                });
                              },
                            ),
                          ),
                          Material(
                            color: const Color(0xFF161B22),
                            elevation: 8,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: reserve),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const _SheetHandle(),
                                  Flexible(
                                    child: SingleChildScrollView(
                                      padding: EdgeInsets.fromLTRB(
                                        body.maxWidth < 700 ? 14 : 22,
                                        0,
                                        body.maxWidth < 700 ? 14 : 22,
                                        12,
                                      ),
                                      child: _HelicopterControls(
                                        animation: animation,
                                        rpmSpeed: _rpmSpeed,
                                        scale: scale,
                                        minScale: minScale,
                                        maxScale: maxScale,
                                        pitch: _pitch,
                                        hovering: _hovering,
                                        spinning: _spinning,
                                        outline: _outline,
                                        shadow: _shadow,
                                        wide: body.maxWidth >= 700,
                                        showPitch: showPitch,
                                        onRpmChanged: (v) =>
                                            setState(() => _rpmSpeed = v),
                                        onScaleChanged: (v) =>
                                            setState(() => _scale = v),
                                        onPitchChanged: (v) =>
                                            setState(() => _pitch = v),
                                        onHoverToggle: () => setState(
                                            () => _hovering = !_hovering),
                                        onSpinToggle: () => setState(
                                            () => _spinning = !_spinning),
                                        onOutlineToggle: () => setState(
                                            () => _outline = !_outline),
                                        onShadowToggle: () =>
                                            setState(() => _shadow = !_shadow),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
    );
  }
}

/// Draws the animated helicopter over a helipad, sized by its parent.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.animation,
    required this.yaw,
    required this.pitch,
    required this.scale,
    required this.spacing,
    required this.hoverLift,
    required this.hovering,
    required this.outline,
    required this.shadow,
    required this.onRotate,
  });

  final SpriteStackAnimation animation;
  final double yaw;
  final double pitch;
  final double scale;
  final double spacing;
  final double hoverLift;
  final bool hovering;
  final bool outline;
  final bool shadow;
  final void Function(double dx, double dy) onRotate;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) => onRotate(details.delta.dx, details.delta.dy),
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Lift the ground line off the sheet so the prop is not glued to
            // the controls and the shadow has room to breathe.
            final groundInset = math.max(8.0, constraints.maxHeight * 0.06);

            return Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _HelipadPainter(
                    hovering: hovering,
                    groundInset: groundInset,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: groundInset,
                  child: Transform.translate(
                    offset: Offset(0, hoverLift),
                    child: RepaintBoundary(
                      child: CustomPaint(
                        foregroundPainter: SpriteStackPainter(
                          stack: animation.stack,
                          frame: animation.frame,
                          yaw: yaw,
                          pitch: pitch,
                          scale: scale,
                          spacing: spacing,
                          outline: outline,
                          shadow: shadow,
                          shadowColor: const Color(0x66000000),
                          outlineColor: const Color(0xFF0D1217),
                        ),
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: _HintPill(label: 'Drag to rotate'),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HintPill extends StatelessWidget {
  const _HintPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x66000000),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swipe, size: 14, color: Colors.white54),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small grab handle so the sheet reads as a bottom sheet on phones.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(2),
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
    required this.minScale,
    required this.maxScale,
    required this.pitch,
    required this.hovering,
    required this.spinning,
    required this.outline,
    required this.shadow,
    required this.wide,
    required this.showPitch,
    required this.onRpmChanged,
    required this.onScaleChanged,
    required this.onPitchChanged,
    required this.onHoverToggle,
    required this.onSpinToggle,
    required this.onOutlineToggle,
    required this.onShadowToggle,
  });

  final SpriteStackAnimation animation;
  final double rpmSpeed;
  final double scale;
  final double minScale;
  final double maxScale;
  final double pitch;
  final bool hovering;
  final bool spinning;
  final bool outline;
  final bool shadow;
  final bool wide;
  final bool showPitch;
  final ValueChanged<double> onRpmChanged;
  final ValueChanged<double> onScaleChanged;
  final ValueChanged<double> onPitchChanged;
  final VoidCallback onHoverToggle;
  final VoidCallback onSpinToggle;
  final VoidCallback onOutlineToggle;
  final VoidCallback onShadowToggle;

  @override
  Widget build(BuildContext context) {
    final rpm = _LabeledSlider(
      icon: Icons.sync,
      label: 'Rotor RPM',
      valueText: '${(rpmSpeed * 100).round()}%',
      value: rpmSpeed,
      min: 0,
      max: 3,
      divisions: 30,
      onChanged: onRpmChanged,
    );
    final zoom = _LabeledSlider(
      icon: Icons.zoom_in,
      label: 'Scale',
      valueText: '${scale.toStringAsFixed(1)}x',
      value: scale,
      min: minScale,
      max: maxScale,
      divisions: 24,
      onChanged: onScaleChanged,
    );
    final tilt = _LabeledSlider(
      icon: Icons.height,
      label: 'Pitch',
      valueText: pitch.toStringAsFixed(2),
      value: pitch,
      min: 0.3,
      max: 1.3,
      divisions: 20,
      onChanged: onPitchChanged,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: rpm),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [zoom, if (showPitch) tilt],
                ),
              ),
            ],
          )
        else ...[
          rpm,
          zoom,
          if (showPitch) tilt,
        ],
        const SizedBox(height: 2),
        Row(
          children: [
            const Spacer(),
            Text(
              'Frame ${animation.frame + 1}/${animation.frameCount}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Colors.white54,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            _ChipToggle(
              label: 'Hover',
              icon: hovering ? Icons.air : Icons.flight_land,
              selected: hovering,
              onTap: onHoverToggle,
            ),
            _ChipToggle(
              label: 'Auto spin',
              icon: spinning ? Icons.autorenew : Icons.touch_app,
              selected: spinning,
              onTap: onSpinToggle,
            ),
            _ChipToggle(
              label: 'Outline',
              icon: Icons.border_outer,
              selected: outline,
              onTap: onOutlineToggle,
            ),
            _ChipToggle(
              label: 'Shadow',
              icon: Icons.wb_sunny_outlined,
              selected: shadow,
              onTap: onShadowToggle,
            ),
          ],
        ),
      ],
    );
  }
}

/// Label + value header with a compact slider underneath, touch sized.
class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.icon,
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                valueText,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 34,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
              showValueIndicator: ShowValueIndicator.onlyForDiscrete,
              valueIndicatorTextStyle: const TextStyle(fontSize: 11),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: valueText,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChipToggle extends StatelessWidget {
  const _ChipToggle({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      avatar: Icon(icon, size: 16),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      onSelected: (_) => onTap(),
    );
  }
}

/// Draws an atmospheric military landing pad below the helicopter.
///
/// Everything is relative to the canvas, so it works on any phone or tablet.
class _HelipadPainter extends CustomPainter {
  const _HelipadPainter({required this.hovering, required this.groundInset});

  final bool hovering;

  /// Distance from the bottom edge to the ground contact line.
  final double groundInset;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final groundY = h - groundInset;

    final padWidth = math.min(w * 0.8, 360.0);
    final padHeight = math.min(padWidth * 0.5, groundY * 0.5);
    if (padWidth <= 0 || padHeight <= 0) return;
    final center = Offset(w / 2, groundY - padHeight * 0.32);

    // Tarmac ground ellipse.
    canvas.drawOval(
      Rect.fromCenter(center: center, width: padWidth, height: padHeight),
      Paint()..color = const Color(0xFF1A1F27),
    );

    // Yellow helipad ring.
    final ringWidth = padWidth * 0.84;
    final ringHeight = padHeight * 0.78;
    canvas.drawOval(
      Rect.fromCenter(center: center, width: ringWidth, height: ringHeight),
      Paint()
        ..color = const Color(0x77E2B024)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, ringWidth / 80),
    );

    // Yellow "H".
    final hPaint = Paint()
      ..color = const Color(0x66E2B024)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(3.0, ringWidth / 48)
      ..strokeCap = StrokeCap.square;
    final hx = ringWidth * 0.07;
    final hy = ringHeight * 0.16;
    canvas.drawLine(
      Offset(center.dx - hx, center.dy - hy),
      Offset(center.dx - hx, center.dy + hy),
      hPaint,
    );
    canvas.drawLine(
      Offset(center.dx + hx, center.dy - hy),
      Offset(center.dx + hx, center.dy + hy),
      hPaint,
    );
    canvas.drawLine(
      Offset(center.dx - hx, center.dy),
      Offset(center.dx + hx, center.dy),
      hPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _HelipadPainter oldDelegate) =>
      oldDelegate.hovering != hovering ||
      oldDelegate.groundInset != groundInset;
}
