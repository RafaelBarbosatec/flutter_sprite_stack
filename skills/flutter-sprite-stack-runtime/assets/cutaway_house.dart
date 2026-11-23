import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';

/// A hollow prop (cottage, crate, machine) that drops its upper slices when
/// someone walks inside.
///
/// ```dart
/// final cottage = CutawayRoof(
///   stack: await SpriteStack.load('assets/cottage.png', sliceCount: 48),
///   wallSlices: 30,
///   position: Vector2(320, 200),
///   stackScale: 4,
/// );
/// add(cottage);
/// add(player); // added after, so it draws over the remaining cross-sections
///
/// // When the player crosses the doorway:
/// cottage.isInside = true;
/// ```
///
/// The roof scrolls away one slice at a time; the slice sitting on the frontier
/// dissolves with the [SliceCut] dither, so the pixel grid stays intact.
///
/// **Draw order.** A single stack cannot draw a resident *between* the back and
/// front walls: everything in one stack is one component. With this component
/// the resident renders on top of the remaining cross-sections, which reads
/// correctly in a top-down or dollhouse camera. If the front wall must occlude
/// the resident, carve the prop as two stacks (back part and front part) and
/// draw `back → resident → front`.
class CutawayRoof extends SpriteStackComponent {
  CutawayRoof({
    required super.stack,
    required this.wallSlices,
    this.duration = 0.35,
    super.position,
    super.yaw,
    super.pitch,
    super.stackScale,
    super.spacing,
    super.priority,
  }) : super(cut: const SliceCut());

  /// How many slices survive the cut — the wall height, in slices.
  ///
  /// Anything at or above this index belongs to the roof. Slice `0` is the
  /// ground cross-section, so `wallSlices` is the wall height as a slice count.
  final double wallSlices;

  /// How long the roof takes to open or close, in seconds.
  final double duration;

  /// Whether a resident is inside right now.
  bool get isInside => _inside;
  set isInside(bool value) {
    if (value == _inside) return;
    _inside = value;
  }

  bool _inside = false;

  /// `0` = roof on, `1` = roof fully off.
  double _open = 0;
  double? _appliedTop;

  @override
  void update(double dt) {
    super.update(dt);

    final target = _inside ? 1.0 : 0.0;
    if (_open == target || duration <= 0) {
      _open = target;
    } else {
      final step = dt / duration;
      _open = _open < target
          ? math.min(target, _open + step)
          : math.max(target, _open - step);
    }

    final eased = Curves.easeOutCubic.transform(_open);
    final total = stack.sliceCount.toDouble();
    final top = wallSlices + (total - wallSlices) * (1 - eased);

    // Rebuilding SliceCut reshapes the bounds, so only do it while it moves.
    if (_appliedTop == null || (top - _appliedTop!).abs() > 0.01) {
      _appliedTop = top;
      cut = SliceCut(top: top);
    }
  }
}
