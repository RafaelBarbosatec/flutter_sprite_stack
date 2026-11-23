import 'dart:math' as math;

import 'package:bonfire/bonfire.dart';
import 'package:bonfire/map/base/layer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';

import 'cached_stack.dart';
import 'f1_car.dart';
import 'race_state.dart';
import 'stack_prop.dart';
import 'touch_controls.dart';
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
  final DriveInput _input = DriveInput();
  Widget? _game;

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
        sliceCount: 15,
      );
      final tree = await SpriteStack.load(
        'sprites/tree/slices.png',
        sliceCount: 43,
      );
      final house = await SpriteStack.load(
        'sprites/house/slices.png',
        sliceCount: 29,
      );
      _stacks.addAll([car, tree, house]);

      final carVisual = CachedStack(car, buckets: 90)..warmUp();
      final treeVisual = CachedStack(tree, scale: 2, buckets: 8);
      final houseVisual = CachedStack(house, scale: 2, buckets: 4);
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
    final placed = <(Vector2, double)>[]; // centre + clearance radius

    bool free(Vector2 p, double radius) => placed.every(
          (o) => o.$1.distanceTo(p) >= o.$2 + radius,
        );

    void house(Vector2 p, double yaw) {
      placed.add((p, 90));
      props.add(StackProp(center: p, visual: _house!, yaw: yaw));
    }

    void tree(Vector2 p, {bool solid = false}) {
      placed.add((p, 38));
      props.add(
        StackProp(
          center: p,
          visual: _tree!,
          yaw: rnd.nextDouble() * 2 * math.pi,
          trunkRadius: solid ? 9 : null,
        ),
      );
    }

    // Candidate points over the whole map, visited in random order.
    final candidates = <Vector2>[
      for (var y = 40.0; y < _track.mapSize.y; y += 48)
        for (var x = 40.0; x < _track.mapSize.x; x += 48)
          Vector2(x + rnd.nextDouble() * 24, y + rnd.nextDouble() * 24),
    ]..shuffle(rnd);

    // A house in the middle of the infield.
    house(Vector2(27 * 64, 20 * 64), 0);

    // Houses on the scenery just behind the barriers.
    var houses = 0;
    for (final p in candidates) {
      if (houses >= 7) break;
      if (!_track.areaIs(p, 56, 44, TrackCell.scenery)) continue;
      final d = _track.distanceToWall(p);
      if (d < 110 || d > 330 || !free(p, 90)) continue;
      house(p, rnd.nextInt(4) * math.pi / 2);
      houses++;
    }

    // Trees on the grass strip beside the track (solid trunks), spaced out so
    // the strip stays drivable.
    var solid = 0;
    for (final p in candidates) {
      if (solid >= 26) break;
      if (_track.cellAt(p) != TrackCell.grass) continue;
      if (_track.distanceToWall(p) > 48 || !free(p, 70)) continue;
      tree(p, solid: true);
      solid++;
    }

    // Trees on the scenery close to the barriers, both inside and outside.
    var scenery = 0;
    for (final p in candidates) {
      if (scenery >= 90) break;
      if (!_track.areaIs(p, 28, 20, TrackCell.scenery)) continue;
      final d = _track.distanceToWall(p);
      if (d > 260 || !free(p, 38)) continue;
      tree(p);
      scenery++;
    }

    return props;
  }

  @override
  Widget build(BuildContext context) {
    final body = _error != null
        ? Center(child: Text('Failed to load assets: $_error'))
        : _car == null
            ? const Center(child: CircularProgressIndicator())
            : (_game ??= _buildGame());

    return Scaffold(
      backgroundColor: const Color(0xFF3F8A41),
      body: body,
    );
  }

  Widget _buildGame() {
    final car = F1Car(
      center: _track.startPosition,
      visual: _car!,
      track: _track,
      race: _race,
      touch: _input,
    );

    return BonfireWidget(
      map: WorldMap([Layer(id: 0, tiles: _track.buildTiles())]),
      player: car,
      components: [TrackRenderer(_track), ..._buildProps()],
      cameraConfig: CameraConfig(
        zoom: 2,
        speed: 8,
        moveOnlyMapArea: true,
      ),
      backgroundColor: const Color(0xFF3F8A41),
      overlayBuilderMap: {
        'topbar': (context, game) => Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Back',
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: game.overlays.isActive('touch')
                            ? 'Hide touch controls'
                            : 'Show touch controls',
                        isSelected: game.overlays.isActive('touch'),
                        icon: const Icon(Icons.touch_app_outlined),
                        selectedIcon: const Icon(Icons.touch_app),
                        onPressed: () {
                          final show = !game.overlays.isActive('touch');
                          _input.reset();
                          game.overlays.setActive('touch', active: show);
                          game.overlays.setActive('controls', active: !show);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
        'hud': (context, game) => Positioned(
              top: 0,
              right: 0,
              child: SafeArea(child: _Hud(race: _race)),
            ),
        'touch': (context, game) => Positioned.fill(
              child: TouchControls(input: _input),
            ),
        'controls': (context, game) => const Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: IgnorePointer(child: _Controls()),
            ),
      },
      initialActiveOverlays: [
        'topbar',
        'hud',
        _isTouch ? 'touch' : 'controls',
      ],
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
