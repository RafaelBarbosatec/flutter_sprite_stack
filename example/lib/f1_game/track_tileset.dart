import 'package:bonfire/bonfire.dart';

import 'track.dart';

/// Builds the visible (and collidable) F1 circuit map with [PixelTileset].
///
/// Every tile is drawn from code-generated [PixelArt] strings and packed into
/// a runtime atlas, so the whole track needs no image asset. Two variants of
/// the asphalt/grass/scenery tiles keep the original alternating-cell look,
/// while kerbs, walls and the animated start/finish line use checkered art.
class TrackTileset {
  TrackTileset(this.track) {
    _tileset = _createTileset();
  }

  final Track track;
  late final PixelTileset _tileset;

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

  /// Generates a ready-to-use single-layer [WorldMap] for the track.
  WorldMap buildWorldMap() {
    final legend = <String, String>{
      'A': 'asphalt0',
      'B': 'asphalt1',
      'G': 'grass0',
      'H': 'grass1',
      'E': 'scenery0',
      'F': 'scenery1',
      'K': 'kerb',
      'W': 'wall',
      'S': 'startline',
    };
    final asciiRows = <String>[
      for (var r = 0; r < Track.rows; r++)
        [
          for (var c = 0; c < Track.cols; c++)
            _asciiFor(track.cellAtCell(c, r), c, r),
        ].join(),
    ];
    return _tileset.worldMapFromAscii(legend: legend, rows: asciiRows);
  }

  String _asciiFor(TrackCell cell, int c, int r) {
    switch (cell) {
      case TrackCell.asphalt:
        if (c == Track.startColumn) return 'S';
        return (c + r).isOdd ? 'B' : 'A';
      case TrackCell.kerb:
        return 'K';
      case TrackCell.grass:
        return (c + r).isOdd ? 'H' : 'G';
      case TrackCell.wall:
        return 'W';
      case TrackCell.scenery:
        return (c + r).isOdd ? 'F' : 'E';
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
          PixelArt.rows(_checker('r', 'w', block: 16)),
        ),
        'wall': PixelTile.single(
          PixelArt.rows(_checker('W', 'D', block: 16)),
          collision: true,
        ),
        'startline': PixelTile.animated(
          [
            PixelArt.rows(_checker('k', 'w', block: 8)),
            PixelArt.rows(_checker('w', 'k', block: 8)),
          ],
          stepTime: 0.6,
        ),
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
