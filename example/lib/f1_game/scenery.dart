import 'dart:math' as math;

import 'package:bonfire/bonfire.dart';
import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';

import 'cached_stack.dart';
import 'stack_prop.dart';
import 'track.dart';

/// Loads the shared tree/house sprite stacks once in [onLoad], then scatters
/// them around the circuit as [StackProp] components in [onGameMounted] (when
/// the game/camera are ready).
///
/// The props are added to the game (not as children of this component) so
/// Bonfire's Y-sort can interleave them with the car correctly.
class Scenery extends GameComponent {
  Scenery({required this.track, this.onError});

  final Track track;
  final void Function(Object error)? onError;

  final List<SpriteStack> _stacks = [];
  CachedStack? _tree;
  CachedStack? _house;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      final treeStack = await SpriteStack.load(
        'sprites/tree/slices.png',
        sliceCount: 43,
      );
      final houseStack = await SpriteStack.load(
        'sprites/house/slices.png',
        sliceCount: 29,
      );
      _stacks.addAll([treeStack, houseStack]);

      _tree = CachedStack(treeStack, scale: 2, buckets: 8);
      _house = CachedStack(houseStack, scale: 2, buckets: 4);
    } catch (e) {
      onError?.call(e);
    }
  }

  @override
  void onMount() {
    final tree = _tree;
    final house = _house;
    if (tree == null || house == null) return;

    for (final prop in _buildProps(tree: tree, house: house)) {
      gameRef.add(prop);
    }
    super.onMount();
  }

  @override
  void onRemove() {
    _tree?.dispose();
    _house?.dispose();
    for (final stack in _stacks) {
      stack.dispose();
    }
    super.onRemove();
  }

  List<StackProp> _buildProps({
    required CachedStack tree,
    required CachedStack house,
  }) {
    final rnd = math.Random(7);
    final props = <StackProp>[];
    final placed = <(Vector2, double)>[]; // centre + clearance radius

    bool free(Vector2 p, double radius) => placed.every(
          (o) => o.$1.distanceTo(p) >= o.$2 + radius,
        );

    void placeHouse(Vector2 p, double yaw) {
      placed.add((p, 90));
      props.add(StackProp(center: p, visual: house, yaw: yaw));
    }

    void placeTree(Vector2 p, {bool solid = false}) {
      placed.add((p, 38));
      props.add(
        StackProp(
          center: p,
          visual: tree,
          yaw: rnd.nextDouble() * 2 * math.pi,
          trunkRadius: solid ? 9 : null,
        ),
      );
    }

    // Candidate points over the whole map, visited in random order.
    final candidates = <Vector2>[
      for (var y = 40.0; y < track.mapSize.y; y += 48)
        for (var x = 40.0; x < track.mapSize.x; x += 48)
          Vector2(x + rnd.nextDouble() * 24, y + rnd.nextDouble() * 24),
    ]..shuffle(rnd);

    // A house in the middle of the infield.
    placeHouse(Vector2(27 * 64, 20 * 64), 0);

    // Houses on the scenery just behind the barriers.
    var houses = 0;
    for (final p in candidates) {
      if (houses >= 7) break;
      if (!track.areaIs(p, 56, 44, TrackCell.scenery)) continue;
      final d = track.distanceToWall(p);
      if (d < 110 || d > 330 || !free(p, 90)) continue;
      placeHouse(p, rnd.nextInt(4) * math.pi / 2);
      houses++;
    }

    // Trees on the grass strip beside the track (solid trunks), spaced out so
    // the strip stays drivable.
    var solid = 0;
    for (final p in candidates) {
      if (solid >= 26) break;
      if (track.cellAt(p) != TrackCell.grass) continue;
      if (track.distanceToWall(p) > 48 || !free(p, 70)) continue;
      placeTree(p, solid: true);
      solid++;
    }

    // Trees on the scenery close to the barriers, both inside and outside.
    var scenery = 0;
    for (final p in candidates) {
      if (scenery >= 90) break;
      if (!track.areaIs(p, 28, 20, TrackCell.scenery)) continue;
      final d = track.distanceToWall(p);
      if (d > 260 || !free(p, 38)) continue;
      placeTree(p);
      scenery++;
    }

    return props;
  }
}
