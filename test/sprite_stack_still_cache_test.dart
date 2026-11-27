import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color, Offset, Size;
import 'dart:ui' as ui;

import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';
import 'package:flutter_test/flutter_test.dart';

const Size _size = Size(320, 240);

/// The still-frame cache: the picture must be exactly the frame a direct paint
/// would have produced, and every field that affects the drawing must miss.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SpriteStack car;

  setUpAll(() async {
    final bytes = await File('example/sprites/car/slices.png').readAsBytes();
    car = await SpriteStack.decode(bytes, sliceCount: 15);
  });

  tearDownAll(() => car.dispose());

  SpriteStackScene build() {
    final scene = SpriteStackScene(
      camera: SpriteStackCamera.orbit(
        yaw: 0.6,
        pitch: 0.5,
        distance: 500,
        target: const SpriteStackPoint(0, 0, 10),
      ),
      zoom: 2,
      ground: const SpriteStackGround(
        extent: 400,
        step: 50,
        cellSize: 50,
        checker: [Color(0xFF142430), Color(0xFF1D303D)],
      ),
      objects: [
        SpriteStackSceneObject(
          stack: car,
          position: const SpriteStackPoint(0, 0, 0),
          yaw: 0.3,
          scale: 1.2,
        ),
      ],
    );
    scene.cacheStillFrames = true;
    return scene;
  }

  test('an unchanged scene replays the exact frame it painted', () async {
    final scene = build();

    await _paint(scene);
    await _paint(scene);
    expect(scene.stillFrameHits, 1, reason: 'second paint should record');

    final cached = await _paint(scene);
    expect(scene.stillFrameHits, 2, reason: 'third paint should replay');

    final fresh = build()..cacheStillFrames = false;
    final direct = await _paint(fresh);

    expect(cached, direct, reason: 'the replay differs from a direct paint');
    expect(scene.stats.drawn, fresh.stats.drawn);
    expect(scene.stats.culled, fresh.stats.culled);
  });

  test('a change misses; time alone does not if nothing reads it', () async {
    final scene = build();
    await _paint(scene);
    await _paint(scene);
    expect(scene.stillFrameHits, 1);

    // `time` with no motion does not affect a pixel.
    scene.objects.first.time = 3;
    await _paint(scene);
    expect(scene.stillFrameHits, 2);

    // A motion makes time matter again.
    scene.objects.first.motion = const StackMotion(sway: 2);
    await _paint(scene);
    final hits = scene.stillFrameHits;
    scene.objects.first.time = 4;
    await _paint(scene);
    expect(scene.stillFrameHits, hits, reason: 'motion time must miss');
  });

  test('every field the paint reads invalidates the cache', () async {
    final mutations = <String, void Function(SpriteStackScene)>{
      'camera yaw': (s) => s.camera.yaw += 0.1,
      'camera pitch': (s) => s.camera.pitch += 0.05,
      'camera distance': (s) => s.camera.distance += 10,
      'camera target': (s) =>
          s.camera.target = const SpriteStackPoint(1, 0, 10),
      'zoom': (s) => s.zoom *= 1.1,
      'background': (s) => s.background = const Color(0xFF112233),
      'sky': (s) => s.sky = const SpriteStackSky(top: Color(0xFF010101)),
      'ground': (s) =>
          s.ground = const SpriteStackGround(fill: Color(0xFF010101)),
      'object position': (s) =>
          s.objects.first.position = const SpriteStackPoint(10, 0, 0),
      'object yaw': (s) => s.objects.first.yaw += 0.1,
      'object billboard': (s) => s.objects.first.billboard = true,
      'object scale': (s) => s.objects.first.scale *= 1.2,
      'object spacing': (s) => s.objects.first.spacing = 2,
      'object frame': (s) => s.objects.first.frame = 1,
      'object outline': (s) => s.objects.first.outline = false,
      'object shadow': (s) => s.objects.first.shadow = false,
      'object pixelSnap': (s) => s.objects.first.pixelSnap = false,
      'object outline colour': (s) =>
          s.objects.first.outlineColor = const Color(0xFFFF0000),
      'object shadow colour': (s) =>
          s.objects.first.shadowColor = const Color(0xFF00FF00),
      'object roll': (s) => s.objects.first.roll = 0.2,
      'object roll pivot': (s) => s.objects.first.rollPivot = 0.5,
      'object cut': (s) => s.objects.first.cut = const SliceCut(top: 8),
      'object motion': (s) =>
          s.objects.first.motion = const StackMotion(lean: Offset(1, 0)),
      'cull size': (s) => s.minimumProjectedPixels = 3,
      'outline floor': (s) => s.outlineMinimumPixels = 30,
      'shadow floor': (s) => s.shadowMinimumPixels = 30,
      'draw outlines': (s) => s.drawOutlines = false,
      'draw shadows': (s) => s.drawShadows = false,
      'object count': (s) => s.objects.add(
            SpriteStackSceneObject(
              stack: car,
              position: const SpriteStackPoint(40, 0, 0),
            ),
          ),
    };

    for (final entry in mutations.entries) {
      final scene = build();
      await _paint(scene);
      await _paint(scene);
      final hits = scene.stillFrameHits;
      expect(hits, greaterThan(0), reason: '${entry.key}: cache never hit');

      entry.value(scene);
      await _paint(scene);

      expect(
        scene.stillFrameHits,
        hits,
        reason: '${entry.key} did not invalidate the still frame',
      );
    }
  });

  test('clearStillCache forces the next paint and keeps the picture', () async {
    final scene = build();
    await _paint(scene);
    final before = await _paint(scene);
    expect(scene.stillFrameHits, 1);

    scene.clearStillCache();
    expect(scene.stillFrameHits, 0);

    final after = await _paint(scene);
    expect(scene.stillFrameHits, 0, reason: 'the cache was cleared');
    expect(after, before);
  });

  test('a new canvas size misses', () async {
    final scene = build();
    await _paint(scene);
    await _paint(scene);
    final hits = scene.stillFrameHits;

    await _paint(scene, size: const Size(300, 200));

    expect(scene.stillFrameHits, hits);
  });

  test('detail tiers drop the outline and shadow of a small prop', () async {
    // A stack with small art, so its projection is small while the rasterizer
    // still draws at one art pixel per pixel (a huge stack shrunk to the same
    // size would be a scatter of sub-pixel points).
    final tiny = await _tinyStack();
    final scene = SpriteStackScene(
      camera: SpriteStackCamera.orbit(
        yaw: 0.6,
        pitch: 0.5,
        distance: 500,
      ),
      zoom: 1,
      objects: [
        SpriteStackSceneObject(
          stack: tiny,
          position: SpriteStackPoint.zero,
          yaw: 0.5,
        ),
      ],
    );

    final projection = scene.projectObject(scene.objects.first, _size)!;
    expect(
      projection.bounds.width,
      lessThan(20),
      reason: 'the test prop is not small enough',
    );

    final withDetail = await _paint(scene);
    scene
      ..outlineMinimumPixels = 20
      ..shadowMinimumPixels = 20;
    final withoutDetail = await _paint(scene);

    expect(
      withoutDetail,
      isNot(equals(withDetail)),
      reason: 'dropping the ink and shadow changed nothing',
    );
    // Both are still drawn: the tier only removes the passes.
    expect(scene.stats.drawn, 1);

    tiny.dispose();
  });
}

/// A small solid stack (8 x 8 x 3) that projects to about ten pixels.
Future<SpriteStack> _tinyStack() async {
  const width = 8;
  const height = 8;
  const slices = 3;
  final pixels = Uint8List(width * height * slices * 4);
  for (var i = 0; i < width * height * slices; i++) {
    pixels[i * 4] = 200;
    pixels[i * 4 + 1] = 60;
    pixels[i * 4 + 2] = 60;
    pixels[i * 4 + 3] = 255;
  }
  final image = await _decodeImage(pixels, width * slices, height);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final stack = await SpriteStack.decode(
    png!.buffer.asUint8List(),
    sliceCount: slices,
  );
  image.dispose();
  return stack;
}

Future<ui.Image> _decodeImage(Uint8List pixels, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

Future<Uint8List> _paint(
  SpriteStackScene scene, {
  Size size = _size,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  scene.paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}
