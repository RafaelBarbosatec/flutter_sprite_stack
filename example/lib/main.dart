import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';

import 'chase_camera_screen.dart';
import 'f1_game/f1_game_screen.dart';
import 'flight_screen.dart';
import 'helicopter_screen.dart';
import 'orbit_scene_screen.dart';
import 'stack_metrics.dart';

enum _SpriteKind { car, spaceship, helicopter, house, tree, palm, robot }

extension on _SpriteKind {
  String get label => switch (this) {
        _SpriteKind.car => 'Car',
        _SpriteKind.spaceship => 'X-Wing',
        _SpriteKind.helicopter => 'Helicopter',
        _SpriteKind.house => 'House',
        _SpriteKind.tree => 'Tree',
        _SpriteKind.palm => 'Palm',
        _SpriteKind.robot => 'Robot',
      };

  IconData get icon => switch (this) {
        _SpriteKind.car => Icons.directions_car,
        _SpriteKind.spaceship => Icons.rocket_launch,
        _SpriteKind.helicopter => Icons.airplanemode_active,
        _SpriteKind.house => Icons.home,
        _SpriteKind.tree => Icons.park,
        _SpriteKind.palm => Icons.forest,
        _SpriteKind.robot => Icons.smart_toy,
      };

  String get asset => switch (this) {
        _SpriteKind.car => 'sprites/car/slices.png',
        _SpriteKind.spaceship => 'sprites/spaceship/slices.png',
        _SpriteKind.helicopter => 'sprites/helicopter/slices.png',
        _SpriteKind.house => 'sprites/house/slices.png',
        _SpriteKind.tree => 'sprites/tree/slices.png',
        _SpriteKind.palm => 'sprites/palmeira/slices.png',
        _SpriteKind.robot => 'assets/robot_stack.png',
      };

  int get sliceCount => switch (this) {
        _SpriteKind.car => 15,
        _SpriteKind.spaceship => 21,
        _SpriteKind.helicopter => 24,
        _SpriteKind.house => 29,
        _SpriteKind.tree => 43,
        _SpriteKind.palm => 26,
        _SpriteKind.robot => 24,
      };

  double get defaultScale => switch (this) {
        _SpriteKind.car => 4.0,
        _SpriteKind.spaceship => 4.2,
        _SpriteKind.helicopter => 3.8,
        _SpriteKind.house => 4.2,
        _SpriteKind.tree => 4.6,
        _SpriteKind.palm => 5.0,
        _SpriteKind.robot => 4.6,
      };
}

void main() => runApp(const SpriteStackExampleApp());

class SpriteStackExampleApp extends StatelessWidget {
  const SpriteStackExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_sprite_stack',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF6FA0FF),
        useMaterial3: true,
      ),
      home: const DemoScreen(),
    );
  }
}

class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  _SpriteKind _selected = _SpriteKind.spaceship;
  SpriteStack? _carStack;
  SpriteStack? _spaceshipStack;
  SpriteStack? _helicopterStack;
  SpriteStack? _houseStack;
  SpriteStack? _treeStack;
  SpriteStack? _palmStack;
  SpriteStack? _robotStack;

  /// Measured pixel height of each stack (lift excluded), used to centre it.
  final Map<SpriteStack, double> _projectedHeights = {};

  Duration _lastTick = Duration.zero;

  double _yaw = 0.6;
  double _pitch = SpriteStack.defaultPitch;
  double _scale = 4.2;
  double _spacing = 1.0;
  bool _spinning = true;
  bool _outline = true;
  bool _shadow = true;
  bool _sway = false;
  double _time = 0;

  SpriteStack? get _stack => switch (_selected) {
        _SpriteKind.car => _carStack,
        _SpriteKind.spaceship => _spaceshipStack,
        _SpriteKind.helicopter => _helicopterStack,
        _SpriteKind.house => _houseStack,
        _SpriteKind.tree => _treeStack,
        _SpriteKind.palm => _palmStack,
        _SpriteKind.robot => _robotStack,
      };

  @override
  void initState() {
    super.initState();
    _load(_SpriteKind.car).then((stack) {
      if (mounted) setState(() => _carStack = stack);
    });
    _load(_SpriteKind.spaceship).then((stack) {
      if (mounted) setState(() => _spaceshipStack = stack);
    });
    _load(_SpriteKind.helicopter).then((stack) {
      if (mounted) setState(() => _helicopterStack = stack);
    });
    _load(_SpriteKind.house).then((stack) {
      if (mounted) setState(() => _houseStack = stack);
    });
    _load(_SpriteKind.tree).then((stack) {
      if (mounted) setState(() => _treeStack = stack);
    });
    _load(_SpriteKind.palm).then((stack) {
      if (mounted) setState(() => _palmStack = stack);
    });
    _load(_SpriteKind.robot).then((stack) {
      if (mounted) setState(() => _robotStack = stack);
    });
    _ticker = createTicker(_onTick)..start();
  }

  Future<SpriteStack> _load(_SpriteKind kind) async {
    final stack = await SpriteStack.load(
      kind.asset,
      sliceCount: kind.sliceCount,
    );
    _projectedHeights[stack] = await measureProjectedHeight(stack);
    return stack;
  }

  void _onTick(Duration elapsed) {
    final delta = (elapsed - _lastTick).inMicroseconds / 1000000;
    _lastTick = elapsed;
    if (!_spinning && !_sway) return;
    setState(() {
      _time += delta;
      if (_spinning) _yaw += delta * 1.4;
    });
  }

  void _selectKind(_SpriteKind kind) {
    setState(() {
      _selected = kind;
      _scale = kind.defaultScale;
      if (kind == _SpriteKind.tree) {
        _sway = true;
      } else {
        _sway = false;
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _carStack?.dispose();
    _spaceshipStack?.dispose();
    _helicopterStack?.dispose();
    _houseStack?.dispose();
    _treeStack?.dispose();
    _palmStack?.dispose();
    _robotStack?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stack = _stack;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sprite Stack'),
        actions: [
          IconButton(
            tooltip: 'Orbit scene (3D camera)',
            icon: const Icon(Icons.view_in_ar),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const OrbitSceneScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Chase camera (follow with lag)',
            icon: const Icon(Icons.navigation),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const ChaseCameraScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Banked flight (roll)',
            icon: const Icon(Icons.flight),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const FlightScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Helicopter demo (animated)',
            icon: const Icon(Icons.airplanemode_active),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const HelicopterScreen()),
            ),
          ),
          IconButton(
            tooltip: 'F1 Game',
            icon: const Icon(Icons.sports_score),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const F1GameScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 720;

            // The stage keeps a comfortable share of the screen on phones and
            // takes the full height next to the panel on wide layouts.
            final stageSize = isNarrow
                ? Size(
                    constraints.maxWidth,
                    math
                        .max(
                          150.0,
                          math.min(
                            constraints.maxHeight * 0.46,
                            constraints.maxHeight - 210,
                          ),
                        )
                        .toDouble(),
                  )
                : Size(
                    math.max(1.0, constraints.maxWidth * 0.6),
                    constraints.maxHeight,
                  );

            if (isNarrow) {
              return _buildNarrowLayout(
                context,
                stack,
                stageSize,
                panelWidth: constraints.maxWidth,
              );
            }
            return _buildWideLayout(context, stack, stageSize);
          },
        ),
      ),
    );
  }

  /// Lifts the stack so its body sits in the middle of [canvas].
  ///
  /// [SpriteStackPainter] puts the bottom of the stack at the bottom of the
  /// canvas, so the body must be lifted by half of its height. The height comes
  /// from [measureProjectedHeight] and ignores [yaw], which keeps the prop from
  /// bobbing while it spins.
  Offset _centerOffset(SpriteStack stack, Size canvas) {
    return stackCenterOffset(
      stack,
      canvas: canvas,
      scale: _scale,
      pitch: _pitch,
      spacing: _spacing,
      projectedHeight: _projectedHeights[stack],
    );
  }

  Widget _buildCanvas(SpriteStack? stack, Size stageSize) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) {
        setState(() {
          _spinning = false;
          _yaw += details.delta.dx * 0.015;
          _pitch = (_pitch - details.delta.dy * 0.01).clamp(0.05, math.pi / 2);
        });
      },
      child: ColoredBox(
        color: const Color(0xFFF1F4F8),
        child: SizedBox(
          width: stageSize.width,
          height: stageSize.height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (stack == null)
                const Center(child: CircularProgressIndicator())
              else
                CustomPaint(
                  size: stageSize,
                  painter: SpriteStackPainter(
                    stack: stack,
                    yaw: _yaw,
                    pitch: _pitch,
                    scale: _scale,
                    spacing: _spacing,
                    offset: _centerOffset(stack, stageSize),
                    motion: _sway
                        ? const StackMotion(sway: 1.6, speed: 1.9, wave: 0.65)
                        : null,
                    time: _time,
                    outline: _outline,
                    shadow: _shadow,
                  ),
                ),
              Positioned(
                top: 8,
                left: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _selected.icon,
                        size: 14,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${stack?.sliceCount ?? _selected.sliceCount} slices · '
                        '${stack?.sliceWidth ?? 0}×${stack?.sliceHeight ?? 0} px',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                right: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app, size: 12, color: Colors.white70),
                      SizedBox(width: 4),
                      Text(
                        'Drag to rotate',
                        style: TextStyle(fontSize: 10, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sprite selector (horizontal scrollable pills for perfect mobile fit)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _SpriteKind.values.map((kind) {
              final isSel = _selected == kind;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Icon(
                    kind.icon,
                    size: 18,
                    color: isSel
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.primary,
                  ),
                  label: Text(kind.label),
                  selected: isSel,
                  onSelected: (selected) {
                    if (selected) _selectKind(kind);
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        _Slider(
          label: 'Yaw',
          value: _yaw % (2 * math.pi),
          min: 0,
          max: 2 * math.pi,
          onChanged: (value) => setState(() => _yaw = value),
        ),
        _Slider(
          label: 'Pitch',
          value: _pitch,
          min: 0.05,
          max: math.pi / 2,
          onChanged: (value) => setState(() => _pitch = value),
        ),
        _Slider(
          label: 'Scale',
          value: _scale,
          min: 1,
          max: 8,
          onChanged: (value) => setState(() => _scale = value),
        ),
        _Slider(
          label: 'Slice spacing',
          value: _spacing,
          min: 0.5,
          max: 3,
          onChanged: (value) => setState(() => _spacing = value),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilterChip(
              label: const Text('Auto spin'),
              selected: _spinning,
              onSelected: (val) => setState(() => _spinning = val),
            ),
            FilterChip(
              label: const Text('Wind sway'),
              selected: _sway,
              onSelected: (val) => setState(() => _sway = val),
            ),
            FilterChip(
              label: const Text('Outline'),
              selected: _outline,
              onSelected: (val) => setState(() => _outline = val),
            ),
            FilterChip(
              label: const Text('Ground shadow'),
              selected: _shadow,
              onSelected: (val) => setState(() => _shadow = val),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          _selected == _SpriteKind.spaceship
              ? 'Starfighter inspirada em naves de Star Wars (T-65 X-Wing) '
                  'com asas S-foils em posição de ataque, 4 canhões laser, '
                  '4 turbinas de íons com exaustão azul brilhante e cúpula de astromech.'
              : 'Stack fatiado desenhado de baixo para cima com rotação 3D '
                  'e projeção isométrica com pixel art nítido.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white70,
              ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(
    BuildContext context,
    SpriteStack? stack,
    Size stageSize, {
    required double panelWidth,
  }) {
    return Column(
      children: [
        _buildCanvas(stack, stageSize),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: SizedBox(
              width: panelWidth,
              child: _buildControls(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWideLayout(
    BuildContext context,
    SpriteStack? stack,
    Size stageSize,
  ) {
    return Row(
      children: [
        SizedBox(
          width: stageSize.width,
          child: _buildCanvas(stack, stageSize),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _buildControls(context),
          ),
        ),
      ],
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value.toStringAsFixed(2),
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
