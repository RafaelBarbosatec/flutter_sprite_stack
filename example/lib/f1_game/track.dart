import 'dart:math' as math;

import 'package:bonfire/bonfire.dart';

enum TrackCell { asphalt, kerb, grass, wall, scenery }

/// Procedural oval circuit built from a rounded-rectangle ring.
///
/// From the asphalt outwards: 1 tile of kerb, 2 tiles of slow grass and a
/// solid barrier wall. Everything past the wall is scenery.
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

  late final List<List<TrackCell>> _cells;

  Vector2 get mapSize => Vector2(cols * tileSize, rows * tileSize);

  double get startLineX => startColumn * tileSize;

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

  TrackCell _classify(double x, double y) {
    bool outer(double grow) => _inRRect(_outer, x, y, grow: grow);
    bool inner(double grow) => _inRRect(_inner, x, y, grow: grow);

    if (outer(0) && !inner(0)) return TrackCell.asphalt;

    if (inner(0)) {
      // Infield: grow < 0 shrinks the infield, i.e. moves away from asphalt.
      if (!inner(-2)) return TrackCell.kerb;
      if (!inner(-6)) return TrackCell.grass;
      if (!inner(-8)) return TrackCell.wall;
      return TrackCell.scenery;
    }

    if (outer(2)) return TrackCell.kerb;
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
