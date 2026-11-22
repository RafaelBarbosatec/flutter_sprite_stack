import 'dart:math' as math;
import 'dart:ui';

/// Per-slice deformation for a `SpriteStack`.
///
/// A stack is rigid by default: every slice is drawn above the previous one with
/// no lateral offset. [StackMotion] offsets each slice with a quadratic falloff
/// from the ground, so the base stays planted while the tip moves — the cheap
/// way to make trees, banners, kelp, grass and capes feel alive without
/// authoring a single extra frame.
///
/// ```dart
/// final motion = StackMotion(sway: 2.5, speed: 1.8, wave: 0.7);
///
/// // In a Flame component:
/// stack.render(canvas, position: ground, motion: motion, time: elapsed);
/// ```
///
/// [sway] oscillates over time; [lean] is a constant bend (wind blowing one
/// way, a banner hanging towards a corner). Both are expressed in **source
/// pixels** at the tip, so they scale with the prop.
///
/// The sway formula (`sin(t * speed - z * wave) * amplitude * (z / (n-1))²`)
/// follows the guidance in `danielwh2/sprite-stacking`'s engine notes: the
/// squared falloff is what keeps slice 0 pinned to the ground.
class StackMotion {
  const StackMotion({
    this.sway = 0,
    this.speed = 1.6,
    this.wave = 0.8,
    this.phase = 0,
    this.lean = Offset.zero,
  }) : assert(sway >= 0, 'sway must not be negative');

  /// Sideways amplitude at the tip, in source pixels.
  final double sway;

  /// Oscillation speed, in radians per second.
  final double speed;

  /// Phase lag between consecutive slices, in radians.
  ///
  /// A higher [wave] makes the motion travel up the prop like a wave instead of
  /// bending it like a rigid rod.
  final double wave;

  /// Initial phase, in radians, for props that should not move in sync.
  final double phase;

  /// Constant offset at the tip, in source pixels (`+y` is down).
  ///
  /// Use it for a steady bend: wind direction, a leaning plant, a banner that
  /// hangs to one side.
  final Offset lean;

  /// Whether this motion leaves every slice where it is.
  bool get isEmpty => sway == 0 && lean == Offset.zero;

  /// Offset applied to [slice] out of [sliceCount], at [time] seconds.
  ///
  /// Slice `0` (the ground) never moves; the offset grows with the square of
  /// the normalized height, so the tip moves by exactly [sway] / [lean].
  Offset offsetAt(int slice, int sliceCount, double time) {
    if (sliceCount <= 1) return Offset.zero;
    final height = slice / (sliceCount - 1);
    final falloff = height * height;

    var dx = lean.dx * falloff;
    var dy = lean.dy * falloff;
    if (sway != 0) {
      dx += math.sin(time * speed - slice * wave + phase) * sway * falloff;
    }
    return Offset(dx, dy);
  }

  @override
  String toString() =>
      'StackMotion(sway: $sway, speed: $speed, wave: $wave, phase: $phase, '
      'lean: $lean)';
}
