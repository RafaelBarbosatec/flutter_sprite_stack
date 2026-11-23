import 'package:bonfire/bonfire.dart';
import 'package:bonfire/map/base/layer.dart';

import 'track.dart';

/// Builds the visible (and collidable) F1 circuit map with [PixelTileset].
///
/// Every tile is drawn from code-generated [PixelArt] strings and packed into
/// a runtime atlas, so the whole track needs no image asset. Two variants of
/// the asphalt/grass/scenery tiles keep the original alternating-cell look,
/// while walls and the animated start/finish line use checkered art. The
/// white track-limit lines are drawn by `TrackLines`, not by tiles.
///
/// ## Rounded corner kerbs
///
/// A kerb is not one tile: it is a 48 px band (three 16 px checker blocks)
/// that sits on the infield side of the asphalt, at the inside of the four
/// corners. Painting every kerb cell as a full checkered square makes the
/// band's border a 32 px staircase, which is exactly what a large-radius
/// corner should not look like.
///
/// Cells crossed by the asphalt/kerb or kerb/grass boundary are therefore
/// rasterised pixel by pixel from [Track.cellAtPoint] instead of using a
/// single tile: each pixel asks the track which region it belongs to and gets
/// the asphalt, kerb or grass pattern for that region. The band's border then
/// follows the real curve at one-pixel precision, while the red/white checker
/// keeps the same 16 px block grid as before. Straights have no kerb at all,
/// so only the cells around the four corners need their own art; tiles with
/// identical pixels are deduplicated.
class TrackTileset {
  TrackTileset(this.track) {
    _customTiles = _buildCustomTiles();
    _tileset = _createTileset();
  }

  final Track track;
  late final PixelTileset _tileset;
  late final _CustomTiles _customTiles;

  static const _asphaltA = Color(0xFF3A3F4B);
  static const _asphaltB = Color(0xFF353A46);
  static const _asphaltDark = Color(0xFF2B303A);
  static const _asphaltLight = Color(0xFF4A5261);
  static const _grassA = Color(0xFF4C9A4A);
  static const _grassB = Color(0xFF479245);
  static const _grassDark = Color(0xFF3C7C3A);
  static const _grassLight = Color(0xFF5AA958);
  static const _sceneryA = Color(0xFF3F8A41);
  static const _sceneryB = Color(0xFF3B843D);
  static const _sceneryDark = Color(0xFF337536);
  static const _sceneryLight = Color(0xFF4B9C4D);
  static const _kerbRed = Color(0xFFD02028);
  static const _kerbWhite = Color(0xFFF2F4F8);
  static const _wallA = Color(0xFFB9C0CC);
  static const _wallB = Color(0xFF8892A4);
  static const _lineBlack = Color(0xFF14161C);

  static const int _tilePx = 32;
  static const int _checkerBlock = 16;

  /// Generates a ready-to-use single-layer [WorldMap] for the track.
  WorldMap buildWorldMap() {
    final tiles = <Tile>[
      for (var r = 0; r < Track.rows; r++)
        for (var c = 0; c < Track.cols; c++)
          _tileset.tile(
            x: c.toDouble(),
            y: r.toDouble(),
            name: _tileNameAt(c, r),
          ),
    ];
    return WorldMap([Layer(id: 0, name: 'track', tiles: tiles)]);
  }

  String _tileNameAt(int c, int r) {
    final custom = _customTiles.byCell[r * Track.cols + c];
    if (custom != null) return custom;

    final cell = track.cellAtCell(c, r);
    if (cell == TrackCell.asphalt && c == Track.startColumn) return 'startline';

    final phase = (c + r).isOdd ? 1 : 0;
    return switch (cell) {
      TrackCell.asphalt => 'asphalt$phase',
      TrackCell.kerb => 'kerb',
      TrackCell.grass => 'grass$phase',
      TrackCell.scenery => 'scenery$phase',
      TrackCell.wall => 'wall',
    };
  }

  /// Builds the per-cell rasterised tiles for the cells the kerb edge crosses.
  _CustomTiles _buildCustomTiles() {
    final byCell = <int, String>{};
    final tiles = <String, PixelTile>{};
    final nameByArt = <String, String>{};

    for (var r = 0; r < Track.rows; r++) {
      for (var c = 0; c < Track.cols; c++) {
        if (!_isKerbEdge(c, r)) continue;

        final rows = _kerbArt(c, r);
        final name = nameByArt.putIfAbsent(rows.join('\n'), () {
          final generated = 'kerb${tiles.length}';
          tiles[generated] = PixelTile.single(PixelArt.rows(rows));
          return generated;
        });
        byCell[r * Track.cols + c] = name;
      }
    }

    return _CustomTiles(byCell, tiles);
  }

  /// Whether the asphalt/kerb or kerb/grass boundary crosses cell ([c], [r]).
  bool _isKerbEdge(int c, int r) {
    // Sampling just inside the cell avoids classifying a point that sits
    // exactly on a cell edge, where the inclusive tests can go either way.
    const edge = 0.001;
    final samples = <TrackCell>{
      track.cellAtPoint(c + edge, r + edge),
      track.cellAtPoint(c + 1 - edge, r + edge),
      track.cellAtPoint(c + edge, r + 1 - edge),
      track.cellAtPoint(c + 1 - edge, r + 1 - edge),
    };
    if (samples.length == 1) return false;
    return samples.contains(TrackCell.kerb) &&
        (samples.contains(TrackCell.asphalt) ||
            samples.contains(TrackCell.grass));
  }

  /// Rasterises one 32x32 cell of the kerb band at sub-tile precision.
  List<String> _kerbArt(int c, int r) {
    final phase = (c + r).isOdd ? 1 : 0;
    final rows = <String>[];

    for (var py = 0; py < _tilePx; py++) {
      final row = StringBuffer();
      for (var px = 0; px < _tilePx; px++) {
        final cell = track.cellAtPoint(
          c + (px + 0.5) / _tilePx,
          r + (py + 0.5) / _tilePx,
        );
        row.write(_pixelCode(cell, px, py, phase));
      }
      rows.add(row.toString());
    }

    return rows;
  }

  /// Palette code for one pixel, matching the pattern of the neighbouring
  /// full-cell tiles so the seams disappear.
  static String _pixelCode(TrackCell cell, int px, int py, int phase) {
    switch (cell) {
      case TrackCell.asphalt:
        return _texturedPixel(
          a: 'a',
          b: 'b',
          dark: 'c',
          light: 's',
          x: px,
          y: py,
          phase: phase,
          darkEvery: 97,
          lightEvery: 61,
        );
      case TrackCell.grass:
        return _texturedPixel(
          a: 'g',
          b: 'h',
          dark: 'd',
          light: 'l',
          x: px,
          y: py,
          phase: phase,
          darkEvery: 83,
          lightEvery: 71,
        );
      case TrackCell.scenery:
        return _texturedPixel(
          a: 'e',
          b: 'f',
          dark: 'm',
          light: 'n',
          x: px,
          y: py,
          phase: phase,
          darkEvery: 89,
          lightEvery: 67,
        );
      case TrackCell.kerb:
        return ((px ~/ _checkerBlock) + (py ~/ _checkerBlock)) % 2 == 0
            ? 'r'
            : 'w';
      case TrackCell.wall:
        return ((px ~/ _checkerBlock) + (py ~/ _checkerBlock)) % 2 == 0
            ? 'W'
            : 'D';
    }
  }

  PixelTileset _createTileset() {
    return PixelTileset(
      tileSize: Track.tileSize,
      palette: {
        'a': _asphaltA,
        'b': _asphaltB,
        'c': _asphaltDark,
        's': _asphaltLight,
        'g': _grassA,
        'h': _grassB,
        'd': _grassDark,
        'l': _grassLight,
        'e': _sceneryA,
        'f': _sceneryB,
        'm': _sceneryDark,
        'n': _sceneryLight,
        'r': _kerbRed,
        'w': _kerbWhite,
        'W': _wallA,
        'D': _wallB,
        'k': _lineBlack,
      },
      tiles: {
        'asphalt0': PixelTile.single(
          PixelArt.rows(
            _textured('a', 'b', 'c', 's',
                phase: 0, darkEvery: 97, lightEvery: 61),
          ),
        ),
        'asphalt1': PixelTile.single(
          PixelArt.rows(
            _textured('a', 'b', 'c', 's',
                phase: 1, darkEvery: 97, lightEvery: 61),
          ),
        ),
        'grass0': PixelTile.single(
          PixelArt.rows(
            _textured('g', 'h', 'd', 'l',
                phase: 0, darkEvery: 83, lightEvery: 71),
          ),
        ),
        'grass1': PixelTile.single(
          PixelArt.rows(
            _textured('g', 'h', 'd', 'l',
                phase: 1, darkEvery: 83, lightEvery: 71),
          ),
        ),
        'scenery0': PixelTile.single(
          PixelArt.rows(
            _textured('e', 'f', 'm', 'n',
                phase: 0, darkEvery: 89, lightEvery: 67),
          ),
        ),
        'scenery1': PixelTile.single(
          PixelArt.rows(
            _textured('e', 'f', 'm', 'n',
                phase: 1, darkEvery: 89, lightEvery: 67),
          ),
        ),
        'kerb': PixelTile.single(
          PixelArt.rows(_checker('r', 'w', block: _checkerBlock)),
        ),
        'wall': PixelTile.single(
          PixelArt.rows(_checker('W', 'D', block: _checkerBlock)),
          collision: true,
        ),
        'startline': PixelTile.animated(
          [
            PixelArt.rows(_checker('k', 'w', block: 8)),
            PixelArt.rows(_checker('w', 'k', block: 8)),
          ],
          stepTime: 0.6,
        ),
        ..._customTiles.tiles,
      },
    );
  }

  static List<String> _checker(
    String a,
    String b, {
    int phase = 0,
    int block = 1,
  }) {
    return [
      for (var y = 0; y < _tilePx; y++)
        [
          for (var x = 0; x < _tilePx; x++)
            ((x ~/ block) + (y ~/ block) + phase) % 2 == 0 ? a : b,
        ].join(),
    ];
  }

  static List<String> _textured(
    String a,
    String b,
    String dark,
    String light, {
    required int phase,
    int darkEvery = 0,
    int lightEvery = 0,
  }) {
    return [
      for (var y = 0; y < _tilePx; y++)
        [
          for (var x = 0; x < _tilePx; x++)
            _texturedPixel(
              a: a,
              b: b,
              dark: dark,
              light: light,
              x: x,
              y: y,
              phase: phase,
              darkEvery: darkEvery,
              lightEvery: lightEvery,
            ),
        ].join(),
    ];
  }

  static String _texturedPixel({
    required String a,
    required String b,
    required String dark,
    required String light,
    required int x,
    required int y,
    required int phase,
    required int darkEvery,
    required int lightEvery,
  }) {
    final n = x * 7 + y * 13 + phase * 11;
    if (darkEvery > 0 && n % darkEvery == 0) return dark;
    if (lightEvery > 0 && n % lightEvery == 0) return light;
    return ((x + y + phase) % 2 == 0) ? a : b;
  }
}

/// Rasterised tiles for the cells the kerb boundary crosses.
class _CustomTiles {
  _CustomTiles(this.byCell, this.tiles);

  /// Tile name by `row * Track.cols + column`.
  final Map<int, String> byCell;

  /// Generated tiles, keyed by name, in first-seen order.
  final Map<String, PixelTile> tiles;
}
