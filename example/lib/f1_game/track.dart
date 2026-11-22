import 'dart:math' as math;
import 'dart:ui';

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

  static const _asphaltA = Color(0xFF3A3F4B);
  static const _asphaltB = Color(0xFF353A46);
  static const _grassA = Color(0xFF4C9A4A);
  static const _grassB = Color(0xFF479245);
  static const _sceneryA = Color(0xFF3F8A41);
  static const _sceneryB = Color(0xFF3B843D);
  static const _kerbRed = Color(0xFFD02028);
  static const _kerbWhite = Color(0xFFF2F4F8);
  static const _wallA = Color(0xFFB9C0CC);
  static const _wallB = Color(0xFF8892A4);

  Color _colorFor(TrackCell cell, int c, int r) {
    final odd = (c + r).isOdd;
    switch (cell) {
      case TrackCell.asphalt:
        if (c == startColumn) return odd ? _kerbWhite : const Color(0xFF14161C);
        return odd ? _asphaltA : _asphaltB;
      case TrackCell.kerb:
        return odd ? _kerbRed : _kerbWhite;
      case TrackCell.grass:
        return odd ? _grassA : _grassB;
      case TrackCell.wall:
        return odd ? _wallA : _wallB;
      case TrackCell.scenery:
        return odd ? _sceneryA : _sceneryB;
    }
  }

  /// Invisible tiles: only the barrier walls collide. Two corner tiles define
  /// the full map bounds for the camera.
  List<Tile> buildTiles() {
    Tile tile(int c, int r, {bool wall = false}) => Tile(
          x: c.toDouble(),
          y: r.toDouble(),
          width: tileSize,
          height: tileSize,
          collisions:
              wall ? [RectangleHitbox(size: Vector2.all(tileSize))] : null,
        );

    final tiles = <Tile>[tile(0, 0), tile(cols - 1, rows - 1)];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (_cells[r][c] == TrackCell.wall) tiles.add(tile(c, r, wall: true));
      }
    }
    return tiles;
  }

  /// Draws the whole circuit once; replaying a [Picture] is much cheaper than
  /// thousands of tile components.
  Picture buildPicture() {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = false;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final cell = _cells[r][c];
        if (cell == TrackCell.kerb || cell == TrackCell.wall) {
          // Finer 16 px checker so kerbs and barriers read as stripes.
          const half = tileSize / 2;
          for (var sr = 0; sr < 2; sr++) {
            for (var sc = 0; sc < 2; sc++) {
              paint.color = _colorFor(cell, c * 2 + sc, r * 2 + sr);
              canvas.drawRect(
                Rect.fromLTWH(c * tileSize + sc * half,
                    r * tileSize + sr * half, half, half),
                paint,
              );
            }
          }
          continue;
        }
        paint.color = _colorFor(cell, c, r);
        canvas.drawRect(
          Rect.fromLTWH(c * tileSize, r * tileSize, tileSize, tileSize),
          paint,
        );
      }
    }
    return recorder.endRecording();
  }
}

/// Renders the [Track] picture just above the (empty) Bonfire map layer and
/// below every other component.
class TrackRenderer extends GameComponent {
  TrackRenderer(this.track) {
    size = track.mapSize;
    _picture = track.buildPicture();
  }

  final Track track;
  late final Picture _picture;

  @override
  int get priority => LayerPriority.MAP + 1;

  @override
  void render(Canvas canvas) {
    canvas.drawPicture(_picture);
  }

  @override
  void onRemove() {
    _picture.dispose();
    super.onRemove();
  }
}
