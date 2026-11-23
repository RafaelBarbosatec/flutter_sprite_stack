import 'package:bonfire/bonfire.dart';
import 'package:bonfire/map/base/layer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'f1_car.dart';
import 'race_state.dart';
import 'scenery.dart';
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
  bool _ready = false;
  Object? _error;

  bool get _isTouch =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  void _onLoadError(Object error) {
    if (mounted) setState(() => _error = error);
  }

  void _onCarLoaded() {
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _race.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = _game ??= _buildGame();

    return Scaffold(
      backgroundColor: const Color(0xFF3F8A41),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: game),
          if (_error != null)
            Center(child: Text('Failed to load assets: $_error')),
          if (_error == null && !_ready)
            Container(
              color: const Color(0xFF3F8A41),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildGame() {
    final car = F1Car(
      center: _track.startPosition,
      track: _track,
      race: _race,
      touch: _input,
      onError: _onLoadError,
      onLoaded: _onCarLoaded,
    );

    return BonfireWidget(
      map: WorldMap([Layer(id: 0, tiles: _track.buildTiles())]),
      player: car,
      components: [
        TrackRenderer(_track),
        Scenery(track: _track, onError: _onLoadError),
      ],
      playerControllers: [
        Keyboard(
          config: KeyboardConfig(
            directionalKeys: [
              KeyboardDirectionalKeys.arrows(),
              KeyboardDirectionalKeys.wasd(),
            ],
          ),
        ),
      ],
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
