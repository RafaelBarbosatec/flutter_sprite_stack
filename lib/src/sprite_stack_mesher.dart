import 'dart:typed_data';

import 'sprite_stack_point.dart';
import 'sprite_stack_volume.dart';

/// Builds a compact, **geometry-only** surface mesh from a [SpriteStackVolume].
///
/// The mesh is not what gets drawn: the sprite stack keeps that job, so the
/// slices still provide every pixel of colour. The mesh exists so a 3D scene
/// can delimit the prop in the world — size, culling, collision, depth sorting.
/// That is why a face has no colour and no UV: it is a rectangle in voxel
/// space, not a textured quad.
///
/// Only exposed faces are emitted (a face between two solid voxels is interior
/// and skipped). Coplanar exposed faces are merged with greedy meshing, so a
/// solid `4 x 4 x 4` block becomes 6 quads instead of 96.
class SpriteStackMesher {
  const SpriteStackMesher();

  /// Meshes [volume] into merged, axis-aligned quads.
  ///
  /// The output is deterministic: axes `0, 1, 2`, then direction `+1, -1`,
  /// then plane, then row, then column.
  SpriteStackMesh build(SpriteStackVolume volume) {
    final quads = <SpriteStackQuad>[];
    final voxels = volume.voxels;

    for (var axis = 0; axis < 3; axis++) {
      final uAxis = _uAxes[axis];
      final vAxis = _vAxes[axis];
      final planeCount = _dimension(volume, axis);
      final uCount = _dimension(volume, uAxis);
      final vCount = _dimension(volume, vAxis);

      for (var directionIndex = 0; directionIndex < 2; directionIndex++) {
        final direction = directionIndex == 0 ? 1 : -1;
        for (var plane = 0; plane < planeCount; plane++) {
          final mask = _buildMask(
            volume,
            voxels,
            axis: axis,
            direction: direction,
            plane: plane,
            uCount: uCount,
            vCount: vCount,
          );
          if (mask == null) continue;
          _mergeMask(
            quads,
            mask,
            axis: axis,
            direction: direction,
            plane: direction > 0 ? plane + 1 : plane,
            uCount: uCount,
            vCount: vCount,
          );
        }
      }
    }

    return SpriteStackMesh(volume: volume, quads: quads);
  }

  /// Returns the exposed-face mask for one plane, or `null` when the plane has
  /// no exposed face at all (the common case for the padding around a prop).
  Uint8List? _buildMask(
    SpriteStackVolume volume,
    Uint8List voxels, {
    required int axis,
    required int direction,
    required int plane,
    required int uCount,
    required int vCount,
  }) {
    final nextPlane = plane + direction;
    final planeCount = _dimension(volume, axis);
    final mask = Uint8List(uCount * vCount);
    var any = false;
    var m = 0;
    for (var v = 0; v < vCount; v++) {
      for (var u = 0; u < uCount; u++, m++) {
        if (voxels[_voxelIndex(volume, axis, u, v, plane)] == 0) continue;
        if (nextPlane >= 0 &&
            nextPlane < planeCount &&
            voxels[_voxelIndex(volume, axis, u, v, nextPlane)] != 0) {
          continue;
        }
        mask[m] = 1;
        any = true;
      }
    }
    return any ? mask : null;
  }

  /// Greedily turns runs of set bits into the largest rectangles it can.
  void _mergeMask(
    List<SpriteStackQuad> quads,
    Uint8List mask, {
    required int axis,
    required int direction,
    required int plane,
    required int uCount,
    required int vCount,
  }) {
    for (var v = 0; v < vCount; v++) {
      var u = 0;
      while (u < uCount) {
        if (mask[v * uCount + u] == 0) {
          u++;
          continue;
        }

        var width = 1;
        while (u + width < uCount && mask[v * uCount + u + width] != 0) {
          width++;
        }

        var height = 1;
        heightLoop:
        while (v + height < vCount) {
          final row = (v + height) * uCount + u;
          for (var i = 0; i < width; i++) {
            if (mask[row + i] == 0) break heightLoop;
          }
          height++;
        }

        for (var row = 0; row < height; row++) {
          final start = (v + row) * uCount + u;
          for (var i = 0; i < width; i++) {
            mask[start + i] = 0;
          }
        }

        quads.add(
          SpriteStackQuad(
            axis: axis,
            direction: direction,
            plane: plane,
            u0: u,
            v0: v,
            u1: u + width,
            v1: v + height,
          ),
        );
        u += width;
      }
    }
  }

  /// Axis used as `u` for each face axis. Chosen so `u x v` points along
  /// `axis`, which makes [SpriteStackQuad.corners] wind counter-clockwise seen
  /// from outside.
  static const List<int> _uAxes = [1, 2, 0];
  static const List<int> _vAxes = [2, 0, 1];

  static int _dimension(SpriteStackVolume volume, int axis) => switch (axis) {
        0 => volume.width,
        1 => volume.depth,
        _ => volume.height,
      };

  /// Index into `volume.voxels` for the cell at (`u`, `v`, `plane`).
  static int _voxelIndex(
    SpriteStackVolume volume,
    int axis,
    int u,
    int v,
    int plane,
  ) =>
      switch (axis) {
        0 => (v * volume.depth + u) * volume.width + plane,
        1 => (u * volume.depth + plane) * volume.width + v,
        _ => (plane * volume.depth + v) * volume.width + u,
      };
}

/// A mesh made of merged, axis-aligned quads.
///
/// See [SpriteStackMesher] for why the mesh carries no colour.
class SpriteStackMesh {
  const SpriteStackMesh({required this.volume, required this.quads});

  /// The volume this mesh was built from.
  final SpriteStackVolume volume;

  /// The merged quads, in deterministic order.
  final List<SpriteStackQuad> quads;

  /// Tight bounds of the solid volume, or `null` when it is empty.
  SpriteStackVolumeBounds? get bounds => volume.bounds;

  int get quadCount => quads.length;

  int get triangleCount => quads.length * 2;

  bool get isEmpty => quads.isEmpty;

  @override
  String toString() =>
      'SpriteStackMesh($quadCount quads, $triangleCount triangles)';
}

/// One merged, axis-aligned face of a [SpriteStackMesh].
///
/// [u0]/[v0] are inclusive and [u1]/[v1] exclusive, both measured in voxels
/// along [uAxis]/[vAxis]. [plane] is the face's coordinate along [axis]: with
/// [direction] `1` the solid voxel sits at `plane - 1` and the empty neighbour
/// at `plane`; with `-1` it is the other way round.
class SpriteStackQuad {
  const SpriteStackQuad({
    required this.axis,
    required this.direction,
    required this.plane,
    required this.u0,
    required this.v0,
    required this.u1,
    required this.v1,
  });

  /// Face axis: `0` = x, `1` = y (depth), `2` = z (height).
  final int axis;

  /// `1` when the face looks towards increasing [axis], `-1` otherwise.
  final int direction;

  /// Boundary coordinate of the face along [axis].
  final int plane;

  final int u0;
  final int v0;
  final int u1;
  final int v1;

  /// In-plane axis that [u0]/[u1] address.
  int get uAxis => SpriteStackMesher._uAxes[axis];

  /// In-plane axis that [v0]/[v1] address.
  int get vAxis => SpriteStackMesher._vAxes[axis];

  /// Face area, in square voxels.
  int get area => (u1 - u0) * (v1 - v0);

  /// Outward unit normal.
  SpriteStackPoint get normal => switch (axis) {
        0 => SpriteStackPoint(direction.toDouble(), 0, 0),
        1 => SpriteStackPoint(0, direction.toDouble(), 0),
        _ => SpriteStackPoint(0, 0, direction.toDouble()),
      };

  /// The four corners, in voxel units, wound counter-clockwise seen from
  /// outside (the direction [normal] points to).
  List<SpriteStackPoint> get corners {
    final points = <SpriteStackPoint>[
      _corner(u0, v0),
      _corner(u1, v0),
      _corner(u1, v1),
      _corner(u0, v1),
    ];
    if (direction < 0) {
      return <SpriteStackPoint>[points[0], points[3], points[2], points[1]];
    }
    return points;
  }

  SpriteStackPoint _corner(int u, int v) {
    final coordinates = <double>[0, 0, 0];
    coordinates[axis] = plane.toDouble();
    coordinates[uAxis] = u.toDouble();
    coordinates[vAxis] = v.toDouble();
    return SpriteStackPoint(
      coordinates[0],
      coordinates[1],
      coordinates[2],
    );
  }

  @override
  String toString() => 'SpriteStackQuad(axis: $axis, direction: $direction, '
      'plane: $plane, u: $u0..$u1, v: $v0..$v1)';

  @override
  bool operator ==(Object other) =>
      other is SpriteStackQuad &&
      other.axis == axis &&
      other.direction == direction &&
      other.plane == plane &&
      other.u0 == u0 &&
      other.v0 == v0 &&
      other.u1 == u1 &&
      other.v1 == v1;

  @override
  int get hashCode => Object.hash(axis, direction, plane, u0, v0, u1, v1);
}
