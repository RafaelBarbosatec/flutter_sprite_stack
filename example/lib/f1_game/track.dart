import 'dart:math' as math;

import 'package:bonfire/bonfire.dart';

enum TrackCell { asphalt, kerb, grass, wall, scenery }

/// Procedural oval circuit built from a rounded-rectangle ring.
///
/// From the asphalt outwards: 2 tiles of slow grass and a solid barrier wall;
/// everything past the wall is scenery. Kerbs are painted only on the infield
/// side of the four corners, where a real circuit has them, and the asphalt
/// edges are marked by white track-limit lines.
class Track {
  Track() {
    _cells = List.generate(
      rows,
      (r) => List.generate(cols, (c) => _classify(c + 0.5, r + 0.5)),
    );
  }

  static const double tileSize = 32;
  static const int cols = 108;
  static const int rows = 80;

  // Outer edge of the asphalt, in tiles (right/bottom exclusive).
  static const _outer =
      (left: 14.0, top: 14.0, right: 94.0, bottom: 66.0, r: 18.0);
  // Infield (non-asphalt area inside the ring).
  static const _inner =
      (left: 24.0, top: 24.0, right: 84.0, bottom: 56.0, r: 8.0);

  /// Column of the start/finish line.
  static const int startColumn = 54;

  /// Width of the kerb band, in tiles.
  ///
  /// The band sits on the infield side of the asphalt, at the inside of the
  /// four corners. 1.5 tiles = 48 px = three 16 px checker blocks, which reads
  /// as a kerb instead of the wide 64 px ribbon the circuit used to have.
  static const double kerbWidth = 1.5;

  late final List<List<TrackCell>> _cells;

  Vector2 get mapSize => Vector2(cols * tileSize, rows * tileSize);

  double get startLineX => startColumn * tileSize;

  /// Bounds of the outer asphalt edge, in tiles.
  static ({double left, double top, double right, double bottom, double r})
      get outerBounds => _outer;

  /// Bounds of the infield edge, in tiles.
  static ({double left, double top, double right, double bottom, double r})
      get innerBounds => _inner;

  /// Middle of the map, used to tell the two straights apart.
  double get midY => rows * tileSize / 2;

  Vector2 get startPosition => Vector2(45 * tileSize, 61 * tileSize);

  static bool _inRRect(
    ({double left, double top, double right, double bottom, double r}) s,
    double x,
    double y, {
    double grow = 0,
  }) {
    final left = s.left - grow;
    final top = s.top - grow;
    final right = s.right + grow;
    final bottom = s.bottom + grow;
    final r = math.max(0.0, s.r + grow);
    if (x < left || x >= right || y < top || y >= bottom) return false;
    final cx = x < left + r ? left + r : (x > right - r ? right - r : x);
    final cy = y < top + r ? top + r : (y > bottom - r ? bottom - r : y);
    final dx = x - cx;
    final dy = y - cy;
    return dx * dx + dy * dy <= r * r;
  }

  /// Centres of the four infield corner arcs, with the direction that points
  /// into each corner's quadrant.
  static const List<({double cx, double cy, double sx, double sy})>
      _kerbCorners = [
    (cx: 32.0, cy: 32.0, sx: -1.0, sy: -1.0), // top-left
    (cx: 76.0, cy: 32.0, sx: 1.0, sy: -1.0), // top-right
    (cx: 32.0, cy: 48.0, sx: -1.0, sy: 1.0), // bottom-left
    (cx: 76.0, cy: 48.0, sx: 1.0, sy: 1.0), // bottom-right
  ];

  /// Whether ([x], [y]) is inside the kerb band.
  ///
  /// A kerb is painted only at the inside of a corner, never along the
  /// straights: the point must be inside the infield, within [kerbWidth] of
  /// its edge, and inside one of the four corner quadrants.
  static bool _inKerbZone(double x, double y) {
    if (!_inRRect(_inner, x, y)) return false;
    if (_inRRect(_inner, x, y, grow: -kerbWidth)) return false;

    for (final corner in _kerbCorners) {
      final u = (x - corner.cx) * corner.sx;
      final v = (y - corner.cy) * corner.sy;
      if (u < 0 || v < 0) continue;
      // The band is already guaranteed by the two rounded-rect tests above;
      // the quadrant test removes the parts that run along the straights.
      if (u * u + v * v <= _inner.r * _inner.r) return true;
    }
    return false;
  }

  TrackCell _classify(double x, double y) {
    bool outer(double grow) => _inRRect(_outer, x, y, grow: grow);
    bool inner(double grow) => _inRRect(_inner, x, y, grow: grow);

    if (outer(0) && !inner(0)) return TrackCell.asphalt;

    if (inner(0)) {
      if (_inKerbZone(x, y)) return TrackCell.kerb;
      if (!inner(-6)) return TrackCell.grass;
      if (!inner(-8)) return TrackCell.wall;
      return TrackCell.scenery;
    }

    if (outer(6)) return TrackCell.grass;
    if (outer(8)) return TrackCell.wall;
    return TrackCell.scenery;
  }

  TrackCell cellAt(Vector2 p) {
    final c = (p.x / tileSize).floor().clamp(0, cols - 1);
    final r = (p.y / tileSize).floor().clamp(0, rows - 1);
    return _cells[r][c];
  }

  /// Direct cell lookup by column/row, used by [TrackTileset].
  TrackCell cellAtCell(int c, int r) => _cells[r][c];

  /// Classifies an arbitrary point, given in tiles, without snapping it to a
  /// cell centre.
  ///
  /// `TrackTileset` uses this to rasterise the kerb boundary at pixel
  /// precision, which is what rounds the corners instead of leaving a
  /// 32 px staircase.
  TrackCell cellAtPoint(double x, double y) => _classify(x, y);

  late final List<Vector2> _wallCenters = [
    for (var r = 0; r < rows; r++)
      for (var c = 0; c < cols; c++)
        if (_cells[r][c] == TrackCell.wall)
          Vector2((c + 0.5) * tileSize, (r + 0.5) * tileSize),
  ];

  /// Distance from [p] to the nearest barrier cell centre, in pixels.
  double distanceToWall(Vector2 p) {
    var best = double.infinity;
    for (final w in _wallCenters) {
      final d = w.distanceToSquared(p);
      if (d < best) best = d;
    }
    return math.sqrt(best);
  }

  /// Whether a [halfW] x [halfH] box centred on [p] only covers [cell]s.
  bool areaIs(Vector2 p, double halfW, double halfH, TrackCell cell) {
    for (final dx in const [-1.0, 0.0, 1.0]) {
      for (final dy in const [-1.0, 0.0, 1.0]) {
        if (cellAt(Vector2(p.x + dx * halfW, p.y + dy * halfH)) != cell) {
          return false;
        }
      }
    }
    return true;
  }
}
