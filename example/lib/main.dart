import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_sprite_stack/sprite_stack.dart';

import 'f1_game/f1_game_screen.dart';

enum _SpriteKind { car, house, tree, robot }

extension on _SpriteKind {
  String get label => switch (this) {
        _SpriteKind.car => 'Car',
        _SpriteKind.house => 'House',
        _SpriteKind.tree => 'Tree',
        _SpriteKind.robot => 'Robot',
      };

  String get asset => switch (this) {
        _SpriteKind.car => 'sprites/car/slices.png',
        _SpriteKind.house => 'sprites/house/slices.png',
        _SpriteKind.tree => 'sprites/tree/slices.png',
        _SpriteKind.robot => 'assets/robot_stack.png',
      };

  int get sliceCount => switch (this) {
        _SpriteKind.car => 16,
        _SpriteKind.house => 28,
        _SpriteKind.tree => 43,
        _SpriteKind.robot => 24,
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

  _SpriteKind _selected = _SpriteKind.car;
  SpriteStack? _carStack;
  SpriteStack? _houseStack;
  SpriteStack? _treeStack;
  SpriteStack? _robotStack;

  Duration _lastTick = Duration.zero;

  double _yaw = 0.6;
  double _pitch = SpriteStack.defaultPitch;
  double _scale = 6;
  double _spacing = 1;
  bool _spinning = true;
  bool _outline = true;
  bool _shadow = true;

  SpriteStack? get _stack => switch (_selected) {
        _SpriteKind.car => _carStack,
        _SpriteKind.house => _houseStack,
        _SpriteKind.tree => _treeStack,
        _SpriteKind.robot => _robotStack,
      };

  @override
  void initState() {
    super.initState();
    _load(_SpriteKind.car).then((stack) {
      if (mounted) setState(() => _carStack = stack);
    });
    _load(_SpriteKind.house).then((stack) {
      if (mounted) setState(() => _houseStack = stack);
    });
    _load(_SpriteKind.tree).then((stack) {
      if (mounted) setState(() => _treeStack = stack);
    });
    _load(_SpriteKind.robot).then((stack) {
      if (mounted) setState(() => _robotStack = stack);
    });
    _ticker = createTicker(_onTick)..start();
  }

  Future<SpriteStack> _load(_SpriteKind kind) {
    return SpriteStack.load(kind.asset, sliceCount: kind.sliceCount);
  }

  void _onTick(Duration elapsed) {
    final delta = (elapsed - _lastTick).inMicroseconds / 1000000;
    _lastTick = elapsed;
    if (!_spinning) return;
    setState(() => _yaw += delta * 1.4);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _carStack?.dispose();
    _houseStack?.dispose();
    _treeStack?.dispose();
    _robotStack?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stack = _stack;
    return Scaffold(
      appBar: AppBar(
        title: const Text('flutter_sprite_stack — turntable'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.sports_score),
            label: const Text('Play F1 game'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const F1GameScreen()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: ColoredBox(
              // Same light stage as the reference viewer, so the ink outline
              // and the projected shadow read like the HTML preview.
              color: const Color(0xFFF1F4F8),
              child: Center(
                child: stack == null
                    ? const SizedBox(
                        width: 460,
                        height: 460,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : CustomPaint(
                        size: const Size(460, 460),
                        painter: SpriteStackPainter(
                          stack: stack,
                          yaw: _yaw,
                          pitch: _pitch,
                          scale: _scale,
                          spacing: _spacing,
                          outline: _outline,
                          shadow: _shadow,
                        ),
                      ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SegmentedButton<_SpriteKind>(
                    segments: _SpriteKind.values
                        .map(
                          (kind) => ButtonSegment(
                            value: kind,
                            label: Text(kind.label),
                          ),
                        )
                        .toList(),
                    selected: {_selected},
                    onSelectionChanged: (selection) =>
                        setState(() => _selected = selection.first),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '${stack?.sliceCount ?? _selected.sliceCount} slices · '
                    '${stack?.sliceWidth ?? 0}x${stack?.sliceHeight ?? 0} px',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 24),
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
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _spinning,
                    title: const Text('Auto spin'),
                    onChanged: (value) => setState(() => _spinning = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _outline,
                    title: const Text('1 px outline'),
                    onChanged: (value) => setState(() => _outline = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _shadow,
                    title: const Text('Ground shadow'),
                    onChanged: (value) => setState(() => _shadow = value),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Formula 1 car, cottage and leafy green tree strips '
                    'carved from four orthographic views, plus the generated '
                    'robot stack. The stack is drawn bottom-to-top at 1x art '
                    'pixels, outlined once and scaled with nearest filtering.',
                    style: Theme.of(context).textTheme.bodySmall,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toStringAsFixed(2)}'),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
