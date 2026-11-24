import 'dart:typed_data';

/// A voxel volume reconstructed from a sprite stack's cross-sections.
///
/// A sprite stack asset is a strip of horizontal cross-sections, ground slice
/// first. Stacking those slices rebuilds the object's volume, which is what a
/// 3D scene needs to know how much space a prop occupies and where its surface
/// is. The volume does **not** carry colour: the sprite stack stays the only
/// thing the renderer draws, and the volume is the geometry that delimits it.
///
/// Coordinates follow the asset, not the screen:
///
/// * `x` — slice column, left to right;
/// * `y` — slice row, top to bottom (depth in the top-down view);
/// * `z` — slice index, bottom to top.
///
/// A voxel is either solid or empty. The buffer is `width * depth * height`
/// bytes, indexed as `(z * depth + y) * width + x`, with `1` for solid and `0`
/// for empty.
class SpriteStackVolume {
  SpriteStackVolume._(this.width, this.depth, this.height, this._voxels)
      : voxelCount = width * depth * height,
        _metrics = _measure(_voxels, width, depth, height);

  /// Builds a volume from an occupancy buffer.
  ///
  /// [voxels] must hold exactly `width * depth * height` bytes, laid out as
  /// `(z * depth + y) * width + x`; any non-zero byte is solid.
  ///
  /// Throws [ArgumentError] for non-positive dimensions or a buffer with the
  /// wrong length.
  factory SpriteStackVolume.fromVoxels(
    Uint8List voxels, {
    required int width,
    required int depth,
    required int height,
  }) {
    if (width <= 0) {
      throw ArgumentError.value(width, 'width', 'must be greater than 0');
    }
    if (depth <= 0) {
      throw ArgumentError.value(depth, 'depth', 'must be greater than 0');
    }
    if (height <= 0) {
      throw ArgumentError.value(height, 'height', 'must be greater than 0');
    }
    final expected = width * depth * height;
    if (voxels.length != expected) {
      throw ArgumentError.value(
        voxels.length,
        'voxels.length',
        'must be width * depth * height ($expected)',
      );
    }
    return SpriteStackVolume._(width, depth, height, voxels);
  }

  /// Reconstructs a volume from the raw RGBA pixels of a sprite stack atlas.
  ///
  /// The atlas is `(sliceCount * sliceWidth) x (frameCount * sliceHeight)`,
  /// exactly what [SpriteStack.load] and [SpriteStack.decode] produce. One
  /// frame is read at a time, so an animated stack only pays for the frame it
  /// needs.
  ///
  /// A pixel is solid when its alpha is **greater than or equal to**
  /// [alphaThreshold]. The default `128` drops the soft edge of
  /// anti-aliased slices while keeping every opaque pixel.
  ///
  /// [frame] is clamped to the available frames, matching what
  /// `SpriteStack.render` draws. Throws [ArgumentError] for non-positive
  /// dimensions, a threshold outside `1..255`, or a buffer too small for the
  /// declared atlas.
  factory SpriteStackVolume.fromPixels(
    Uint8List pixels, {
    required int sliceWidth,
    required int sliceHeight,
    required int sliceCount,
    int frameCount = 1,
    int frame = 0,
    int alphaThreshold = 128,
  }) {
    if (sliceWidth <= 0) {
      throw ArgumentError.value(
          sliceWidth, 'sliceWidth', 'must be greater than 0');
    }
    if (sliceHeight <= 0) {
      throw ArgumentError.value(
          sliceHeight, 'sliceHeight', 'must be greater than 0');
    }
    if (sliceCount <= 0) {
      throw ArgumentError.value(
          sliceCount, 'sliceCount', 'must be greater than 0');
    }
    if (frameCount <= 0) {
      throw ArgumentError.value(
          frameCount, 'frameCount', 'must be greater than 0');
    }
    if (alphaThreshold < 1 || alphaThreshold > 255) {
      throw ArgumentError.value(
        alphaThreshold,
        'alphaThreshold',
        'must be in 1..255',
      );
    }

    final stripWidth = sliceCount * sliceWidth;
    final expected = stripWidth * frameCount * sliceHeight * 4;
    if (pixels.length < expected) {
      throw ArgumentError.value(
        pixels.length,
        'pixels.length',
        'must hold at least $expected RGBA bytes',
      );
    }

    final frameIndex = frame.clamp(0, frameCount - 1);
    final firstRow = frameIndex * sliceHeight;
    final voxels = Uint8List(sliceWidth * sliceHeight * sliceCount);
    var out = 0;
    for (var z = 0; z < sliceCount; z++) {
      final sliceX = z * sliceWidth;
      for (var y = 0; y < sliceHeight; y++) {
        var offset = ((firstRow + y) * stripWidth + sliceX) * 4 + 3;
        for (var x = 0; x < sliceWidth; x++) {
          if (pixels[offset] >= alphaThreshold) {
            voxels[out] = 1;
          }
          offset += 4;
          out++;
        }
      }
    }
    return SpriteStackVolume._(sliceWidth, sliceHeight, sliceCount, voxels);
  }

  /// Number of columns (slice width).
  final int width;

  /// Number of rows per slice (depth).
  final int depth;

  /// Number of slices stacked along the vertical axis.
  final int height;

  /// Total number of cells, solid or empty: `width * depth * height`.
  final int voxelCount;

  final Uint8List _voxels;
  final _VolumeMetrics _metrics;

  /// The occupancy buffer, laid out as `(z * depth + y) * width + x`.
  ///
  /// Treat it as read-only: mutating it after the volume is built leaves
  /// [solidVoxelCount] and [bounds] stale.
  Uint8List get voxels => _voxels;

  /// How many cells are solid.
  int get solidVoxelCount => _metrics.solid;

  /// Tight bounds of the solid cells, or `null` when the volume is empty.
  ///
  /// The grid includes the transparent padding around the prop; these bounds
  /// are the actual occupied box, which is what a scene should use to place
  /// and scale it.
  SpriteStackVolumeBounds? get bounds => _metrics.bounds;

  /// Whether the cell at ([x], [y], [z]) is solid.
  ///
  /// Coordinates outside the grid are empty, which keeps meshing and
  /// neighbour lookups free of bounds checks.
  bool isSolid(int x, int y, int z) {
    if (x < 0 || y < 0 || z < 0 || x >= width || y >= depth || z >= height) {
      return false;
    }
    return _voxels[(z * depth + y) * width + x] != 0;
  }

  @override
  String toString() => 'SpriteStackVolume(${width}x${depth}x$height, '
      'solid: $solidVoxelCount, bounds: $bounds)';
}

/// Axis-aligned, integer bounds of a [SpriteStackVolume]'s solid cells.
///
/// [minX]/[maxX] are inclusive on the `x` axis (slice column), [minY]/[maxY]
/// on `y` (slice row / depth) and [minZ]/[maxZ] on `z` (slice index / height).
class SpriteStackVolumeBounds {
  const SpriteStackVolumeBounds({
    required this.minX,
    required this.minY,
    required this.minZ,
    required this.maxX,
    required this.maxY,
    required this.maxZ,
  });

  final int minX;
  final int minY;
  final int minZ;
  final int maxX;
  final int maxY;
  final int maxZ;

  /// Occupied columns, in art pixels.
  int get width => maxX - minX + 1;

  /// Occupied rows (depth), in art pixels.
  int get depth => maxY - minY + 1;

  /// Occupied slices, in art pixels.
  int get height => maxZ - minZ + 1;

  /// Whether ([x], [y], [z]) lies inside these bounds.
  bool contains(int x, int y, int z) =>
      x >= minX &&
      x <= maxX &&
      y >= minY &&
      y <= maxY &&
      z >= minZ &&
      z <= maxZ;

  @override
  String toString() => 'SpriteStackVolumeBounds('
      'x: $minX..$maxX, y: $minY..$maxY, z: $minZ..$maxZ)';

  @override
  bool operator ==(Object other) =>
      other is SpriteStackVolumeBounds &&
      other.minX == minX &&
      other.minY == minY &&
      other.minZ == minZ &&
      other.maxX == maxX &&
      other.maxY == maxY &&
      other.maxZ == maxZ;

  @override
  int get hashCode => Object.hash(minX, minY, minZ, maxX, maxY, maxZ);
}

class _VolumeMetrics {
  const _VolumeMetrics(this.solid, this.bounds);

  final int solid;
  final SpriteStackVolumeBounds? bounds;
}

_VolumeMetrics _measure(
  Uint8List voxels,
  int width,
  int depth,
  int height,
) {
  var solid = 0;
  var minX = width;
  var minY = depth;
  var minZ = height;
  var maxX = -1;
  var maxY = -1;
  var maxZ = -1;
  var index = 0;
  for (var z = 0; z < height; z++) {
    for (var y = 0; y < depth; y++) {
      for (var x = 0; x < width; x++, index++) {
        if (voxels[index] == 0) continue;
        solid++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        if (z < minZ) minZ = z;
        if (z > maxZ) maxZ = z;
      }
    }
  }
  if (solid == 0) return const _VolumeMetrics(0, null);
  return _VolumeMetrics(
    solid,
    SpriteStackVolumeBounds(
      minX: minX,
      minY: minY,
      minZ: minZ,
      maxX: maxX,
      maxY: maxY,
      maxZ: maxZ,
    ),
  );
}
