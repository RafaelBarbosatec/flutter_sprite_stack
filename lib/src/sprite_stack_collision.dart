import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'sprite_stack_point.dart';

/// Collision proxy authored on a `SpriteStackSceneObject`.
///
/// A prop with a collider blocks movement; a prop without one is walk-through.
/// The proxy is a box on the ground plane (`z = 0`), sized from the stack's
/// `SpriteStackVolume` by default — the volume is the geometry, never the
/// sprite pixels. That keeps collision independent from the yaw the renderer
/// happens to pick and from the pixel art's transparency.
///
/// Every length is in **art pixels**, the same unit as the asset, and is
/// scaled by `SpriteStackSceneObject.scale`. The scene rotates the box by the
/// object's yaw, so it follows the prop as it turns.
///
/// ```dart
/// // Footprint from the volume: tight bounds of the solid voxels.
/// SpriteStackSceneObject(stack: house, collider: const SpriteStackCollider())
///
/// // Hand-authored footprint, for stacks built with SpriteStack.fromImage()
/// // (no raw pixels, so no volume).
/// SpriteStackSceneObject(
///   stack: house,
///   collider: const SpriteStackCollider(size: Size(40, 30), height: 29),
/// )
/// ```
class SpriteStackCollider {
  const SpriteStackCollider({
    this.padding = 0,
    this.size,
    this.offset = Offset.zero,
    this.height,
    this.alphaThreshold = 128,
  });

  /// Extra margin around the footprint, in art pixels.
  ///
  /// Useful for foliage or gaps in the art that should still feel solid.
  final double padding;

  /// Explicit footprint in art pixels: `width` spans the slice `x` axis and
  /// `height` spans the slice `y` (depth) axis.
  ///
  /// When `null`, the footprint is the tight bounds of the stack volume's
  /// solid voxels. Setting it lets a stack built with `SpriteStack.fromImage`
  /// — which cannot be read back — still collide.
  final Size? size;

  /// Offset of the footprint centre from its natural position, in art pixels,
  /// in the prop's local frame.
  ///
  /// `+y` points the way the footprint extends from the ground anchor (the
  /// prop's front, following the asset convention), `+x` is the prop's local
  /// right, and the offset rotates with the prop. With an explicit [size] the
  /// footprint is centred `size.height / 2` forward of the ground point, so
  /// `Offset.zero` keeps it flush with the anchor. Use it to shift the proxy
  /// for art with a wide transparent margin.
  ///
  /// Ignored when [size] is `null`: a volume-derived footprint is already
  /// centred on its own bounds.
  final Offset offset;

  /// Height of the proxy above the ground, in art pixels (one unit per
  /// slice). `null` derives it from the volume, or leaves it unlimited when
  /// [size] is set.
  ///
  /// Used only by `SpriteStackScene.move(stepHeight:)`: a proxy no taller than
  /// the step height can be walked over.
  final double? height;

  /// Alpha at or above which a voxel counts as solid when deriving the
  /// footprint from the volume.
  final int alphaThreshold;

  /// Whether this collider can be resolved without a volume.
  bool get hasExplicitFootprint => size != null;
}

/// A resolved collision proxy in world space.
///
/// This is a box standing on the ground plane: a rectangle of half extents
/// [halfWidth] × [halfDepth] rotated by [yaw] around the vertical axis, from
/// `z = 0` up to [height]. The scene builds one per blocking prop per query
/// (the expensive part, the volume, is cached on the object).
///
/// Only the horizontal footprint is used for movement; [height] feeds the
/// step-height check. There are no slopes, ramps or per-pixel tests.
class SpriteStackCollisionBody {
  const SpriteStackCollisionBody({
    required this.center,
    required this.halfWidth,
    required this.halfDepth,
    this.yaw = 0,
    this.height = double.infinity,
  });

  /// Centre of the footprint on the ground plane, in world units.
  final Offset center;

  /// Half extent along the body's local `x` axis.
  final double halfWidth;

  /// Half extent along the body's local `y` axis.
  final double halfDepth;

  /// Rotation around the vertical axis, in radians.
  ///
  /// The body's local `x` axis points at `(cos(yaw), sin(yaw))` and its local
  /// `y` axis at `(-sin(yaw), cos(yaw))`.
  final double yaw;

  /// Height above `z = 0`, in world units.
  final double height;

  /// Whether the box has no area and can never block anything.
  bool get isDegenerate => halfWidth <= 0 || halfDepth <= 0;

  /// World-space axis-aligned bounds of the footprint, for broad-phase checks
  /// and debug drawing.
  Rect get bounds {
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    final ex = (halfWidth * c).abs() + (halfDepth * s).abs();
    final ey = (halfWidth * s).abs() + (halfDepth * c).abs();
    return Rect.fromLTRB(
      center.dx - ex,
      center.dy - ey,
      center.dx + ex,
      center.dy + ey,
    );
  }

  /// [point] expressed in the body's local frame.
  Offset toLocal(Offset point) {
    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    return Offset(dx * c + dy * s, -dx * s + dy * c);
  }

  /// A local direction expressed in world space.
  Offset toWorldDirection(Offset local) {
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    return Offset(
      local.dx * c - local.dy * s,
      local.dx * s + local.dy * c,
    );
  }

  /// Whether a circle at [point] with [radius] touches this body.
  bool overlaps(Offset point, double radius) {
    if (isDegenerate) return false;
    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    final localX = dx * c + dy * s;
    final localY = -dx * s + dy * c;

    final outsideX = localX.abs() - halfWidth;
    final outsideY = localY.abs() - halfDepth;
    if (outsideX <= 0 && outsideY <= 0) return true;

    final closestX = localX.clamp(-halfWidth, halfWidth);
    final closestY = localY.clamp(-halfDepth, halfDepth);
    final gapX = localX - closestX;
    final gapY = localY - closestY;
    return gapX * gapX + gapY * gapY < radius * radius;
  }

  /// Moves a circle at [point] with [radius] out of this body.
  ///
  /// Returns the closest position outside the box, or `null` when there is no
  /// overlap. A circle exactly touching the surface is not overlapping.
  ///
  /// This is the resolution step of `SpriteStackScene.move`: because the
  /// correction runs along the contact normal, the tangential part of a
  /// movement survives, which is what makes a character slide along a wall
  /// instead of stopping dead.
  Offset? resolve(Offset point, double radius) {
    if (isDegenerate) return null;
    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    final localX = dx * c + dy * s;
    final localY = -dx * s + dy * c;

    final outsideX = localX.abs() - halfWidth;
    final outsideY = localY.abs() - halfDepth;

    final double normalX;
    final double normalY;
    final double depth;
    if (outsideX <= 0 && outsideY <= 0) {
      // Centre inside the box: leave through the nearest face.
      if (outsideX > outsideY) {
        normalX = localX >= 0 ? 1 : -1;
        normalY = 0;
        depth = radius - outsideX;
      } else {
        normalX = 0;
        normalY = localY >= 0 ? 1 : -1;
        depth = radius - outsideY;
      }
    } else {
      final closestX = localX.clamp(-halfWidth, halfWidth);
      final closestY = localY.clamp(-halfDepth, halfDepth);
      final gapX = localX - closestX;
      final gapY = localY - closestY;
      final distanceSquared = gapX * gapX + gapY * gapY;
      if (distanceSquared >= radius * radius) return null;
      final distance = math.sqrt(distanceSquared);
      if (distance < 1e-9) return null;
      normalX = gapX / distance;
      normalY = gapY / distance;
      depth = radius - distance;
    }

    final cw = math.cos(yaw);
    final sw = math.sin(yaw);
    if (depth <= 0) return null;
    return Offset(
      point.dx + (normalX * cw - normalY * sw) * depth,
      point.dy + (normalX * sw + normalY * cw) * depth,
    );
  }

  @override
  String toString() => 'SpriteStackCollisionBody('
      'center: $center, half: ${halfWidth}x$halfDepth, '
      'yaw: ${yaw.toStringAsFixed(2)}, height: $height)';
}

/// Result of a `SpriteStackScene.move`.
class SpriteStackMoveResult {
  const SpriteStackMoveResult({
    required this.position,
    required this.applied,
    this.hits = const <SpriteStackCollisionBody>[],
  });

  /// Final position. `z` is carried over from the requested position.
  final SpriteStackPoint position;

  /// Movement actually applied on the ground plane.
  ///
  /// Differs from the requested delta when a body blocked (or diverted) the
  /// move; `applied.distance == delta.distance` means nothing touched.
  final Offset applied;

  /// Distinct bodies touched during the move, in first-contact order.
  final List<SpriteStackCollisionBody> hits;

  /// Whether anything blocked the movement.
  bool get collided => hits.isNotEmpty;

  @override
  String toString() => 'SpriteStackMoveResult(position: $position, '
      'applied: $applied, hits: ${hits.length})';
}
