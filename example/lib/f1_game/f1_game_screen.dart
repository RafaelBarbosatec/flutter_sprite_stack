import 'dart:math' as math;

import 'package:bonfire/bonfire.dart';
import 'package:bonfire/map/base/layer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sprite_stack/sprite_stack.dart';

import 'cached_stack.dart';
import 'f1_car.dart';
import 'race_state.dart';
import 'stack_prop.dart';
import 'track.dart';

/// A small Bonfire game: drive the sprite-stacked F1 car around a circuit.
class F1GameScreen extends StatefulWidget {
  const F1GameScreen({super.key});

  @override
  State<F1GameScreen> createState() => _F1GameScreenState();
}

class _F1GameScreenState extends State<F1GameScreen> {
  final Track _track = Track();
  final RaceState _race = RaceState();

  final List<SpriteStack> _stacks = [];
  CachedStack? _car;
  CachedStack? _tree;
  CachedStack? _house;
  Object? _error;

  bool get _isTouch =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final car = await SpriteStack.load(
        'sprites/car/slices.png',
        sliceCount: 16,
      );
      final tree = await SpriteStack.load(
        'sprites/tree/slices.png',
        sliceCount: 43,
      );
      final house = await SpriteStack.load(
        'sprites/house/slices.png',
        sliceCount: 28,
      );
      _stacks.addAll([car, tree, house]);

      final carVisual = CachedStack(car, buckets: 90)..warmUp();
      final treeVisual = CachedStack(tree, scale: 2, buckets: 8);
      final houseVisual = CachedStack(house, scale: 3, buckets: 4);
      if (!mounted) return;
      setState(() {
        _car = carVisual;
        _tree = treeVisual;
        _house = houseVisual;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _car?.dispose();
    _tree?.dispose();
    _house?.dispose();
    for (final stack in _stacks) {
      stack.dispose();
    }
    _race.dispose();
    super.dispose();
  }

  List<GameComponent> _buildProps() {
    final rnd = math.Random(7);
    final props = <GameComponent>[];
    // Prop coordinates are expressed in 64 px units.
    const ts = 64.0;
    const cols = Track.cols / 2;
    const rows = Track.rows / 2;

    void tree(double col, double row) {
      props.add(
        StackProp(
          center: Vector2(col * ts, row * ts),
          visual: _tree!,
          yaw: rnd.nextDouble() * 2 * math.pi,
        ),
      );
    }

    void house(double col, double row, double yaw) {
      props.add(
        StackProp(
          center: Vector2(col * ts, row * ts),
          visual: _house!,
          yaw: yaw,
        ),
      );
    }

    // Infield.
    house(27, 20, 0);
    for (final p in const [
      (19.0, 18.0),
      (35.0, 18.5),
      (21.0, 22.0),
      (33.0, 22.0),
      (25.0, 17.0),
      (30.0, 17.5),
    ]) {
      tree(p.$1, p.$2);
    }

    // Outside the barriers.
    for (var c = 4.0; c < cols - 3; c += 4.5) {
      tree(c, 1.2 + rnd.nextDouble());
      tree(c + 2, rows - 1.2 - rnd.nextDouble());
    }
    for (var r = 5.0; r < rows - 3; r += 4.5) {
      tree(0.8 + rnd.nextDouble(), r);
      tree(cols - 0.8 - rnd.nextDouble(), r + 2);
    }
    house(10, 1.4, math.pi / 2);
    house(44, rows - 1.4, math.pi);

    return props;
  }

  @override
  Widget build(BuildContext context) {
    final body = _error != null
        ? Center(child: Text('Failed to load assets: $_error'))
        : _car == null
            ? const Center(child: CircularProgressIndicator())
            : _buildGame();

    return Scaffold(
      backgroundColor: const Color(0xFF3F8A41),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: body),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton.filledTonal(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(child: _Hud(race: _race)),
          ),
          if (!_isTouch)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: IgnorePointer(child: _Controls()),
            ),
        ],
      ),
    );
  }

  Widget _buildGame() {
    final car = F1Car(
      center: _track.startPosition,
      visual: _car!,
      track: _track,
      race: _race,
    );

    return BonfireWidget(
      map: WorldMap([Layer(id: 0, tiles: _track.buildTiles())]),
      player: car,
      components: [TrackRenderer(_track), ..._buildProps()],
      playerControllers: [
        if (_isTouch)
          Joystick(
            directional: JoystickDirectional(
              spriteBackgroundDirectional: null,
              size: 110,
              margin: const EdgeInsets.all(40),
              isFixed: false,
            ),
            observer: car,
          ),
      ],
      cameraConfig: CameraConfig(
        zoom: 2,
        speed: 8,
        moveOnlyMapArea: true,
      ),
      backgroundColor: const Color(0xFF3F8A41),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({required this.race});

  final RaceState race;

  static String _fmt(double? seconds) {
    if (seconds == null) return '--:--.---';
    final m = seconds ~/ 60;
    final s = seconds - m * 60;
    return '${m.toString().padLeft(2, '0')}:${s.toStringAsFixed(3).padLeft(6, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: Colors.white,
      fontFeatures: [FontFeature.tabularFigures()],
      fontSize: 14,
    );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ListenableBuilder(
            listenable: race,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${race.speedKmh.round()} km/h',
                  style: style.copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text('LAP ${race.lap == 0 ? '-' : race.lap}', style: style),
                Text('TIME ${_fmt(race.started ? race.currentLap : null)}',
                    style: style),
                Text('LAST ${_fmt(race.lastLap)}', style: style),
                Text('BEST ${_fmt(race.bestLap)}', style: style),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            'W/↑ accelerate · S/↓ brake & reverse · A D / ← → steer · '
            'Space handbrake',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ),
    );
  }
}
