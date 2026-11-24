import 'dart:math' as math;

/// A point (or vector) in world space.
///
/// The package uses one unit per art pixel in the horizontal plane and one unit
/// per slice along `z`, so a prop's volume can be placed in a scene without a
/// separate scale factor:
///
/// * `x` — slice column, left to right;
/// * `y` — slice row, depth in the top-down view;
/// * `z` — slice index, up.
class SpriteStackPoint {
  const SpriteStackPoint(this.x, this.y, this.z);

  /// The origin, `(0, 0, 0)`.
  static const SpriteStackPoint zero = SpriteStackPoint(0, 0, 0);

  final double x;
  final double y;
  final double z;

  SpriteStackPoint operator +(SpriteStackPoint other) =>
      SpriteStackPoint(x + other.x, y + other.y, z + other.z);

  SpriteStackPoint operator -(SpriteStackPoint other) =>
      SpriteStackPoint(x - other.x, y - other.y, z - other.z);

  SpriteStackPoint operator -() => SpriteStackPoint(-x, -y, -z);

  SpriteStackPoint operator *(double factor) =>
      SpriteStackPoint(x * factor, y * factor, z * factor);

  /// Dot product, useful for projecting a point onto a camera axis.
  double dot(SpriteStackPoint other) => x * other.x + y * other.y + z * other.z;

  /// Cross product.
  SpriteStackPoint cross(SpriteStackPoint other) => SpriteStackPoint(
        y * other.z - z * other.y,
        z * other.x - x * other.z,
        x * other.y - y * other.x,
      );

  /// Euclidean length.
  double get length => math.sqrt(x * x + y * y + z * z);

  /// Unit vector in the same direction, or [zero] when this point is zero.
  SpriteStackPoint get normalized {
    final magnitude = length;
    if (magnitude == 0) return zero;
    return this * (1 / magnitude);
  }

  @override
  String toString() => 'SpriteStackPoint($x, $y, $z)';

  @override
  bool operator ==(Object other) =>
      other is SpriteStackPoint && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);
}
