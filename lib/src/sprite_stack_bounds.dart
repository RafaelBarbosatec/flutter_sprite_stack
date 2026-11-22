import 'dart:ui';

/// Axis-aligned bounds of a rendered sprite stack.
///
/// Sprite stacks are anchored at their **ground contact point**, not at a
/// corner. [ground] tells where that point sits inside [size], so callers can
/// position the stack by its feet while still using [rect] for culling and hit
/// testing.
class SpriteStackBounds {
  const SpriteStackBounds({required this.size, required this.ground});

  /// Full projected size, in destination pixels.
  final Size size;

  /// Ground contact point, relative to the top-left corner of [size].
  final Offset ground;

  /// Bounds relative to the ground point (negative top-left).
  Rect get localRect =>
      Rect.fromLTWH(-ground.dx, -ground.dy, size.width, size.height);

  /// The bounds rect placed at [groundPosition].
  Rect rectAt(Offset groundPosition) => Rect.fromLTWH(
        groundPosition.dx - ground.dx,
        groundPosition.dy - ground.dy,
        size.width,
        size.height,
      );

  /// The bounds relative to their own top-left corner.
  Rect get rect => Offset.zero & size;

  @override
  String toString() => 'SpriteStackBounds(size: $size, ground: $ground)';

  @override
  bool operator ==(Object other) =>
      other is SpriteStackBounds &&
      other.size == size &&
      other.ground == ground;

  @override
  int get hashCode => Object.hash(size, ground);
}
