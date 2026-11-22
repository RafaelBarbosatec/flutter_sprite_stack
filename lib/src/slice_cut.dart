import 'dart:math' as math;

/// Which slices of a stack are visible.
///
/// Hiding the upper slices turns a prop into a **cutaway**: a hollow house that
/// drops its roof when the player walks in, a crate that opens, a machine whose
/// casing disappears to show the inside. What remains are the cross-sections
/// below the cut, so you look straight at the floor plan.
///
/// [top] and [bottom] are measured in **slices**, not pixels, and may be
/// fractional. Animating [top] from `sliceCount` down to the wall height hides
/// the roof one slice at a time; the slice sitting exactly at the cut is
/// dissolved with a 4×4 Bayer dither, which keeps the pixel grid intact instead
/// of blending the whole stack.
///
/// ```dart
/// // Roof gone, walls kept: show slices 0..18.
/// const cut = SliceCut(top: 19);
///
/// // Animate the roof off over 0.4 s:
/// final cut = SliceCut(top: sliceCount * (1 - roofProgress));
/// ```
class SliceCut {
  const SliceCut({this.top = double.infinity, this.bottom = 0})
      : assert(bottom >= 0, 'bottom must not be negative');

  /// Continuous frontier above which slices are hidden.
  ///
  /// `double.infinity` (the default) keeps every slice. `19` keeps slices
  /// `0..18`; `18.5` keeps `0..17` plus half of slice `18`.
  final double top;

  /// Continuous frontier below which slices are hidden.
  ///
  /// Use it for props that should not show their base, or to skip a part a
  /// separate sprite already draws.
  final double bottom;

  /// Whether this cut hides anything.
  bool get isActive => top.isFinite || bottom > 0;

  /// Whether [slice] is drawn at all.
  bool isVisible(int slice) => visibilityAt(slice) > 0;

  /// How much of [slice] is drawn, from `0` (hidden) to `1` (opaque).
  double visibilityAt(int slice) {
    if (slice + 1 <= bottom) return 0;
    if (slice >= top) return 0;

    var visible = 1.0;
    if (slice < bottom) visible = slice + 1 - bottom;
    if (slice + 1 > top) visible = math.min(visible, top - slice);

    return visible.clamp(0.0, 1.0);
  }

  /// How many slices survive this cut, used to shrink the projected bounds.
  double visibleSliceCount(int sliceCount) {
    final count = sliceCount.toDouble();
    final low = bottom.clamp(0.0, count).toDouble();
    final high = top.clamp(0.0, count).toDouble();
    return math.max(0.0, high - low);
  }

  @override
  String toString() => 'SliceCut(top: $top, bottom: $bottom)';
}

/// 4×4 Bayer threshold matrix, values `0..15`.
const List<List<int>> bayer4x4 = [
  [0, 8, 2, 10],
  [12, 4, 14, 6],
  [3, 11, 1, 9],
  [15, 7, 13, 5],
];

/// Whether a pixel should be drawn for a slice at [visibility].
///
/// The dither is only consulted for partially visible slices, so fully visible
/// artwork is never touched.
bool bayerAllows(int x, int y, double visibility) {
  if (visibility >= 1) return true;
  if (visibility <= 0) return false;
  final threshold = (bayer4x4[y & 3][x & 3] + 0.5) / 16;
  return visibility > threshold;
}
