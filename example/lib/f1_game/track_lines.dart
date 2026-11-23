import 'dart:ui';

import 'package:bonfire/bonfire.dart';

import 'track.dart';

/// Draws the white track-limit lines along both asphalt edges.
///
/// The circuit is two rounded rectangles (the outer asphalt edge and the
/// infield edge), so the lines are just two stroked [RRect]s baked into one
/// [Picture]. No per-pixel tile art is needed for them, which keeps the map
/// tileset small even though the lines run around the whole circuit.
class TrackLines extends GameComponent {
  TrackLines(this.track) {
    size = track.mapSize;
    _picture = _build();
  }

  final Track track;
  late final Picture _picture;

  static const double lineWidth = 2;
  static const Color _white = Color(0xFFF2F4F8);

  Picture _build() {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()
      ..color = _white
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..isAntiAlias = false;

    final outer = track.outerBounds;
    final inner = track.innerBounds;

    // The asphalt is inside the outer rounded rectangle: pull the stroke in by
    // half its width so the whole line stays on the tarmac.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          outer.left * Track.tileSize,
          outer.top * Track.tileSize,
          outer.right * Track.tileSize,
          outer.bottom * Track.tileSize,
        ).deflate(lineWidth / 2),
        Radius.circular(outer.r * Track.tileSize - lineWidth / 2),
      ),
      paint,
    );

    // The asphalt is outside the infield rounded rectangle: push the stroke
    // out by half its width for the same reason.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          inner.left * Track.tileSize,
          inner.top * Track.tileSize,
          inner.right * Track.tileSize,
          inner.bottom * Track.tileSize,
        ).inflate(lineWidth / 2),
        Radius.circular(inner.r * Track.tileSize + lineWidth / 2),
      ),
      paint,
    );

    return recorder.endRecording();
  }

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
