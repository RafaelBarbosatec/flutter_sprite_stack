import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sliceStep', () {
    test('draws every step-th slice and always the top one', () async {
      final stack = await _onePixelSlices(count: 6);

      final full = await _render(stack, sliceStep: 1);
      final half = await _render(stack, sliceStep: 2);
      final wide = await _render(stack, sliceStep: 4);

      expect(_opaqueColors(full), {0, 1, 2, 3, 4, 5});
      expect(_opaqueColors(half), {0, 2, 4, 5});
      expect(_opaqueColors(wide), {0, 4, 5});
    });

    test('a step of one keeps every slice', () async {
      final stack = await _onePixelSlices(count: 6);
      final full = await _render(stack, sliceStep: 1);
      final zero = await _render(stack, sliceStep: 0);

      expect(_opaqueColors(zero), _opaqueColors(full));
      expect(_opaqueCount(zero), _opaqueCount(full));
    });

    test('keeps the silhouette of a dense stack', () async {
      final stack = await _voxelSphere();
      final full = await _render(stack, sliceStep: 1);
      final fullBounds = _alphaBounds(full);
      final fullPixels = _opaqueCount(full);

      for (final step in [2, 3, 4, 6]) {
        final lod = await _render(stack, sliceStep: step);
        final changed = _alphaDiff(full, lod);
        // Adjacent cross-sections of a solid body overlap almost completely,
        // so dropping them moves the rim by about a pixel, not the shape.
        expect(
          changed / fullPixels,
          lessThan(0.03),
          reason: 'step $step changed $changed of $fullPixels pixels',
        );
        final lodBounds = _alphaBounds(lod);
        expect(lodBounds.top, closeTo(fullBounds.top, 1),
            reason: 'step $step moved the top edge');
        expect(lodBounds.bottom, closeTo(fullBounds.bottom, 1),
            reason: 'step $step moved the bottom edge');
        expect(lodBounds.left, closeTo(fullBounds.left, 2),
            reason: 'step $step narrowed the left edge');
        expect(lodBounds.right, closeTo(fullBounds.right, 2),
            reason: 'step $step narrowed the right edge');
      }
    });
  });

  group('scene slice LOD', () {
    test('keeps every slice when the prop is drawn at 1:1 or larger', () async {
      final scene = await _scene(zoom: 2);
      _paint(scene);

      expect(scene.stats.drawn, 1);
      expect(scene.stats.slicesDrawn, scene.stats.slicesTotal);
      expect(scene.stats.sliceLodSaving, 0);
    });

    test('drops hidden cross-sections when the prop is scaled down', () async {
      final scene = await _scene(zoom: 0.25);
      _paint(scene);

      // spacing 1, scale 0.25 -> every slice would land a quarter pixel from
      // the one below it, so only every fourth one is worth rasterising.
      expect(scene.stats.slicesTotal, 8);
      expect(scene.stats.slicesDrawn, 3); // 0, 4, 7 (the top)
      expect(scene.stats.sliceLodSaving, closeTo(1 - 3 / 8, 1e-9));
    });

    test('sliceLod = false keeps the old full render', () async {
      final scene = await _scene(zoom: 0.25);
      scene.sliceLod = false;
      _paint(scene);

      expect(scene.stats.slicesDrawn, scene.stats.slicesTotal);
    });

    test('sliceLodPixels raises the threshold', () async {
      final scene = await _scene(zoom: 1);
      scene.sliceLodPixels = 2;
      _paint(scene);

      // gap = 1 px, budget 2 px -> every second slice.
      expect(scene.stats.slicesDrawn, 5); // 0, 2, 4, 6, 7
      expect(scene.stats.slicesTotal, 8);
    });

    test('an object sliceStep overrides the automatic choice', () async {
      final scene = await _scene(zoom: 2);
      scene.objects.single.sliceStep = 3;
      _paint(scene);

      expect(scene.stats.slicesDrawn, 4); // 0, 3, 6, 7
      expect(scene.stats.slicesTotal, 8);
    });

    test('turning sliceLod off invalidates a cached still frame', () async {
      final scene = await _scene(zoom: 0.25);
      scene.cacheStillFrames = true;
      _paint(scene);
      _paint(scene);
      expect(scene.stillFrameHits, 1);

      scene.sliceLod = false;
      _paint(scene);
      expect(scene.stillFrameHits, 1, reason: 'replayed a stale frame');
    });
  });
}

/// A stack of [count] 1x1 slices, one distinct colour per slice, so the test
/// can tell exactly which cross-sections reached the buffer.
Future<SpriteStack> _onePixelSlices({required int count}) async {
  final pixels = Uint8List(count * 4);
  for (var slice = 0; slice < count; slice++) {
    final at = slice * 4;
    pixels[at] = 20 + slice * 30;
    pixels[at + 1] = 180;
    pixels[at + 2] = 60;
    pixels[at + 3] = 255;
  }
  return _decodeStack(pixels, count, 1, count);
}

/// A solid, ellipsoid-ish body: [count] 32x32 slices of shrinking discs, which
/// overlap heavily the way a real sprite stack does.
Future<SpriteStack> _voxelSphere() async {
  const slice = 32;
  const count = 24;
  const radius = 14.0;
  final width = slice * count;
  final pixels = Uint8List(width * slice * 4);
  final center = (count - 1) / 2;

  for (var z = 0; z < count; z++) {
    final dz = z - center;
    final r = math.sqrt(math.max(0, radius * radius - dz * dz));
    for (var y = 0; y < slice; y++) {
      for (var x = 0; x < slice; x++) {
        final dx = x - slice / 2 + 0.5;
        final dy = y - slice / 2 + 0.5;
        if (dx * dx + dy * dy > r * r) continue;
        final at = (y * width + z * slice + x) * 4;
        pixels[at] = 180;
        pixels[at + 1] = 160;
        pixels[at + 2] = 120;
        pixels[at + 3] = 255;
      }
    }
  }
  return _decodeStack(pixels, width, slice, count);
}

Future<SpriteStack> _decodeStack(
  Uint8List pixels,
  int width,
  int height,
  int sliceCount,
) async {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  final image = await completer.future;
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final stack = await SpriteStack.decode(
    png!.buffer.asUint8List(),
    sliceCount: sliceCount,
  );
  image.dispose();
  return stack;
}

const int _canvasWidth = 160;
const int _canvasHeight = 160;

/// Renders face-on (`pitch = pi / 2`), so every slice lands on its own row and
/// the pixel checks below are exact.
Future<Uint8List> _render(SpriteStack stack, {required int sliceStep}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  stack.render(
    canvas,
    position: const ui.Offset(80, 140),
    yaw: 0,
    pitch: math.pi / 2,
    scale: 1,
    sliceStep: sliceStep,
    outline: false,
    shadow: false,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(_canvasWidth, _canvasHeight);
  final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return rgba!.buffer.asUint8List();
}

/// Slice indices whose pixels reached the buffer, decoded from the colour the
/// [_onePixelSlices] helper wrote (`r = 20 + slice * 30`).
Set<int> _opaqueColors(Uint8List rgba) {
  final slices = <int>{};
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i + 3] == 0) continue;
    slices.add((rgba[i] - 20) ~/ 30);
  }
  return slices;
}

int _opaqueCount(Uint8List rgba) {
  var count = 0;
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] != 0) count++;
  }
  return count;
}

int _alphaDiff(Uint8List a, Uint8List b) {
  var diff = 0;
  for (var i = 3; i < a.length; i += 4) {
    if ((a[i] == 0) != (b[i] == 0)) diff++;
  }
  return diff;
}

ui.Rect _alphaBounds(Uint8List rgba) {
  var minX = _canvasWidth;
  var minY = _canvasHeight;
  var maxX = -1;
  var maxY = -1;
  for (var y = 0; y < _canvasHeight; y++) {
    for (var x = 0; x < _canvasWidth; x++) {
      if (rgba[(y * _canvasWidth + x) * 4 + 3] == 0) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  return ui.Rect.fromLTRB(
    minX.toDouble(),
    minY.toDouble(),
    maxX.toDouble(),
    maxY.toDouble(),
  );
}

/// A one-prop scene. At the orbit target the projection scale is `zoom`, so the
/// test sets the distance it wants by setting `zoom`.
Future<SpriteStackScene> _scene({required double zoom}) async {
  final stack = await _solidStack();
  final scene = SpriteStackScene(
    camera: SpriteStackCamera.orbit(
      yaw: 0,
      pitch: 0.6,
      distance: 400,
      target: SpriteStackPoint.zero,
    ),
    zoom: zoom,
    objects: [
      SpriteStackSceneObject(stack: stack, position: SpriteStackPoint.zero),
    ],
  );
  // Keep the test about slices only.
  scene
    ..drawOutlines = false
    ..drawShadows = false
    ..minimumProjectedPixels = 0;
  return scene;
}

/// Eight 8x8 slices, all opaque.
Future<SpriteStack> _solidStack() async {
  const slice = 8;
  const count = 8;
  final pixels = Uint8List(slice * count * slice * 4);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = 200;
    pixels[i + 1] = 120;
    pixels[i + 2] = 60;
    pixels[i + 3] = 255;
  }
  return _decodeStack(pixels, slice * count, slice, count);
}

void _paint(SpriteStackScene scene) {
  const size = ui.Size(240, 200);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  scene.paint(canvas, size);
  recorder.endRecording().dispose();
}
