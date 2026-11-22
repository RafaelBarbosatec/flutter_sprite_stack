import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SpriteStack.fromImage', () {
    test('splits a horizontal strip into slices', () async {
      final image = await _solidImage(width: 8, height: 2, color: 0xFF3366FF);
      final stack = SpriteStack.fromImage(image, sliceCount: 4);

      expect(stack.sliceCount, 4);
      expect(stack.sliceWidth, 2);
      expect(stack.sliceHeight, 2);
      expect(stack.sliceSize, const ui.Size(2, 2));

      stack.dispose();
    });

    test('rejects an invalid slice count', () async {
      final image = await _solidImage(width: 8, height: 2, color: 0xFFFFFFFF);

      expect(
        () => SpriteStack.fromImage(image, sliceCount: 0),
        throwsArgumentError,
      );
      expect(
        () => SpriteStack.fromImage(image, sliceCount: -3),
        throwsArgumentError,
      );

      image.dispose();
    });

    test('rejects an image width that is not divisible', () async {
      final image = await _solidImage(width: 7, height: 2, color: 0xFFFFFFFF);

      expect(
        () => SpriteStack.fromImage(image, sliceCount: 3),
        throwsArgumentError,
      );

      image.dispose();
    });
  });

  group('projection', () {
    test('squash is the sine of the pitch, clamped', () {
      expect(SpriteStack.squashFor(0), 0.08);
      expect(SpriteStack.squashFor(math.pi / 2), closeTo(1, 1e-9));
      expect(
        SpriteStack.squashFor(math.pi / 4),
        closeTo(math.sin(math.pi / 4), 1e-9),
      );
      expect(SpriteStack.squashFor(10), closeTo(1, 1e-9));
    });

    test('height adds the lifts to the squashed slice height', () async {
      final image = await _solidImage(width: 8, height: 4, color: 0xFF00FF00);
      final stack = SpriteStack.fromImage(image, sliceCount: 4);

      expect(stack.heightFor(pitch: math.pi / 2, spacing: 1), 7);
      expect(stack.heightFor(pitch: math.pi / 2, spacing: 2), 10);

      stack.dispose();
    });
  });

  group('render', () {
    test('places the bottom slice at the given position', () async {
      final image = await _solidImage(width: 4, height: 4, color: 0xFFFF0000);
      final stack = SpriteStack.fromImage(image, sliceCount: 1);

      final pixels = await _renderToPixels(
        stack,
        width: 24,
        height: 24,
        position: const ui.Offset(12, 20),
        pitch: math.pi / 2,
      );

      // Slice is 4x4, so it covers x 10..14 and y 16..20.
      expect(_pixelAt(pixels, 24, 12, 18), 0xFFFF0000);
      expect(_pixelAt(pixels, 24, 12, 15), 0x00000000);
      expect(_pixelAt(pixels, 24, 6, 18), 0x00000000);

      stack.dispose();
    });

    test('lifts every slice by spacing', () async {
      // Two slices: red on the ground, green on top.
      final image = await _twoToneImage();
      final stack = SpriteStack.fromImage(image, sliceCount: 2);

      final pixels = await _renderToPixels(
        stack,
        width: 24,
        height: 40,
        position: const ui.Offset(12, 36),
        pitch: math.pi / 2,
        spacing: 8,
      );

      // Ground slice center: y = 36 - 2 = 34. Top slice: y = 34 - 8 = 26.
      expect(_pixelAt(pixels, 24, 12, 34), 0xFFFF0000);
      expect(_pixelAt(pixels, 24, 12, 26), 0xFF00FF00);

      stack.dispose();
    });

    test('renders without throwing for a full stack', () async {
      final image =
          await _solidImage(width: 32 * 24, height: 32, color: 0xFF00FF00);
      final stack = SpriteStack.fromImage(image, sliceCount: 24);

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      stack.render(
        canvas,
        position: const ui.Offset(100, 200),
        yaw: 1.2,
        pitch: 0.6,
        scale: 4,
        outline: false,
        shadow: false,
      );
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(200, 260);

      expect(rendered.width, 200);
      expect(rendered.height, 260);

      rendered.dispose();
      picture.dispose();
      stack.dispose();
    });
  });

  group('outline and shadow', () {
    test('draws a 1 px outline around the finished stack', () async {
      final image = await _solidImage(width: 4, height: 4, color: 0xFFFF0000);
      final stack = SpriteStack.fromImage(image, sliceCount: 1);

      final pixels = await _renderToPixels(
        stack,
        width: 24,
        height: 24,
        position: const ui.Offset(12, 20),
        pitch: math.pi / 2,
        outline: true,
        shadow: false,
      );

      // Interior stays red; the four 4-connected neighbours become ink.
      expect(_pixelAt(pixels, 24, 12, 18), 0xFFFF0000);
      expect(_pixelAt(pixels, 24, 12, 15), 0xFF181C24);
      expect(_pixelAt(pixels, 24, 12, 20), 0xFF181C24);
      expect(_pixelAt(pixels, 24, 9, 18), 0xFF181C24);
      expect(_pixelAt(pixels, 24, 14, 18), 0xFF181C24);

      stack.dispose();
    });

    test('draws a projected ground shadow offset +2,+3', () async {
      final image = await _solidImage(width: 4, height: 4, color: 0xFFFF0000);
      final stack = SpriteStack.fromImage(image, sliceCount: 1);

      final pixels = await _renderToPixels(
        stack,
        width: 24,
        height: 24,
        position: const ui.Offset(12, 20),
        pitch: math.pi / 2,
        outline: false,
        shadow: true,
      );

      // Shadow is the slice dropped at (+2, +3), body is on top of it.
      expect(_pixelAt(pixels, 24, 12, 18), 0xFFFF0000);
      expect(_pixelAt(pixels, 24, 15, 22), 0xFFBAC6D4);

      stack.dispose();
    });
  });

  group('software rasterizer', () {
    test('decode() renders through the art-pixel buffer', () async {
      final image = await _solidImage(width: 8, height: 4, color: 0xFF3366FF);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final stack = await SpriteStack.decode(
        png!.buffer.asUint8List(),
        sliceCount: 2,
      );

      final pixels = await _renderToPixels(
        stack,
        width: 24,
        height: 24,
        position: const ui.Offset(12, 20),
        pitch: math.pi / 2,
        outline: false,
        shadow: false,
      );

      // Two 4x4 slices stacked with no lift: rows 16..20 are body.
      expect(_pixelAt(pixels, 24, 12, 18), 0xFF3366FF);
      expect(_pixelAt(pixels, 24, 12, 15), 0x00000000);

      image.dispose();
      stack.dispose();
    });
  });

  group('bounds', () {
    test('follows yaw and the projected slice shape', () async {
      // 2 slices of 2x4 source pixels.
      final image = await _solidImage(width: 4, height: 4, color: 0xFFFFFFFF);
      final stack = SpriteStack.fromImage(image, sliceCount: 2);

      final front = stack.boundsFor(
        pitch: math.pi / 2,
        outline: false,
        shadow: false,
      );
      expect(front.size, const ui.Size(2, 5)); // 4 tall + 1 lift
      expect(front.ground, const ui.Offset(1, 5));
      expect(front.rectAt(const ui.Offset(10, 20)),
          const ui.Rect.fromLTWH(9, 15, 2, 5));

      final side = stack.boundsFor(
        yaw: math.pi / 2,
        pitch: math.pi / 2,
        outline: false,
        shadow: false,
      );
      expect(side.size, const ui.Size(4, 3)); // rotated footprint, 2 tall + 1
      expect(side.ground, const ui.Offset(2, 3));

      stack.dispose();
    });

    test('adds the outline ring and the ground shadow', () async {
      final image = await _solidImage(width: 4, height: 4, color: 0xFFFFFFFF);
      final stack = SpriteStack.fromImage(image, sliceCount: 2);

      final outline = stack.boundsFor(
        pitch: math.pi / 2,
        outline: true,
        shadow: false,
      );
      expect(outline.size, const ui.Size(4, 7)); // +1 px each side, +1 below
      expect(outline.ground, const ui.Offset(2, 6));

      final withShadow = stack.boundsFor(
        pitch: math.pi / 2,
        outline: false,
        shadow: true,
      );
      // Shadow is dropped +3 px and extends half a slice below the feet.
      expect(withShadow.size, const ui.Size(2, 10));
      expect(withShadow.ground, const ui.Offset(1, 5));

      stack.dispose();
    });

    test('scales with the destination scale', () async {
      final image = await _solidImage(width: 4, height: 4, color: 0xFFFFFFFF);
      final stack = SpriteStack.fromImage(image, sliceCount: 2);

      final bounds = stack.boundsFor(
        pitch: math.pi / 2,
        scale: 4,
        outline: false,
        shadow: false,
      );
      expect(bounds.size, const ui.Size(8, 20));
      expect(bounds.ground, const ui.Offset(4, 20));

      stack.dispose();
    });
  });

  group('pixel snapping', () {
    test('rounds the ground anchor to whole pixels', () async {
      final image = await _solidImage(width: 4, height: 4, color: 0xFFFF0000);
      final stack = SpriteStack.fromImage(image, sliceCount: 1);

      final snapped = await _renderToPixels(
        stack,
        width: 24,
        height: 24,
        position: const ui.Offset(12, 21),
        pitch: math.pi / 2,
        pixelSnap: true,
      );
      final fractional = await _renderToPixels(
        stack,
        width: 24,
        height: 24,
        position: const ui.Offset(12.4, 20.6),
        pitch: math.pi / 2,
        pixelSnap: true,
      );

      expect(fractional, snapped);

      stack.dispose();
    });
  });

  group('bake', () {
    test('replays a frame with its ground point at the draw position',
        () async {
      final image = await _solidImage(width: 4, height: 4, color: 0xFFFF0000);
      final stack = SpriteStack.fromImage(image, sliceCount: 1);

      final baked = stack.bake(
        pitch: math.pi / 2,
        outline: false,
        shadow: false,
      );

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      baked.draw(canvas, const ui.Offset(12, 20));
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(24, 24);
      final data =
          await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
      final pixels = data!.buffer.asUint8List();

      // 4x4 slice, ground at y=20: rows 16..20, columns 10..14.
      expect(_pixelAt(pixels, 24, 12, 18), 0xFFFF0000);
      expect(_pixelAt(pixels, 24, 12, 15), 0x00000000);

      expect(
        baked.bounds.size,
        stack
            .boundsFor(
              pitch: math.pi / 2,
              outline: false,
              shadow: false,
            )
            .size,
      );

      rendered.dispose();
      picture.dispose();
      baked.dispose();
      expect(baked.isDisposed, isTrue);
      stack.dispose();
    });
  });

  group('turntable', () {
    test('bakes buckets lazily and reuses them', () async {
      final image = await _solidImage(width: 4, height: 4, color: 0xFF00FF00);
      final stack = SpriteStack.fromImage(image, sliceCount: 1);

      final turntable = SpriteStackTurntable(
        stack,
        buckets: 8,
        pitch: math.pi / 2,
        outline: false,
        shadow: false,
      );

      expect(turntable.bakedFrameCount, 0);

      final first = turntable.frameFor(0);
      final sameBucket = turntable.frameFor(0.01);
      expect(identical(first, sameBucket), isTrue);
      expect(turntable.bakedFrameCount, 1);

      final quarter = turntable.frameFor(math.pi / 4);
      expect(quarter.yaw, closeTo(math.pi / 4, 1e-9));
      expect(turntable.bakedFrameCount, 2);

      // Negative yaw and values past a full turn wrap around.
      expect(turntable.bucketFor(-math.pi / 4), 7);
      expect(turntable.bucketFor(math.pi / 4 + 2 * math.pi), 1);

      turntable.warmUp();
      expect(turntable.bakedFrameCount, 8);

      turntable.dispose();
      expect(turntable.bakedFrameCount, 0);
      stack.dispose();
    });
  });

  group('cache', () {
    test('loads each asset once and evicts it', () async {
      var loads = 0;
      final cache = SpriteStackCache(
        loader: (path, sliceCount) async {
          loads++;
          final image =
              await _solidImage(width: 4, height: 4, color: 0xFFFFFFFF);
          return SpriteStack.fromImage(image, sliceCount: 1);
        },
      );

      final first = await cache.load('a.png', sliceCount: 1);
      final second = await cache.load('a.png', sliceCount: 1);

      expect(identical(first, second), isTrue);
      expect(loads, 1);
      expect(cache.contains('a.png'), isTrue);
      expect(cache['a.png'], same(first));
      expect(cache.length, 1);

      cache.evict('a.png');
      expect(cache.contains('a.png'), isFalse);
      expect(cache.length, 0);
    });

    test('shares a single in-flight load', () async {
      var loads = 0;
      final cache = SpriteStackCache(
        loader: (path, sliceCount) async {
          loads++;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          final image =
              await _solidImage(width: 4, height: 4, color: 0xFFFFFFFF);
          return SpriteStack.fromImage(image, sliceCount: 1);
        },
      );

      await Future.wait([
        cache.load('b.png', sliceCount: 1),
        cache.load('b.png', sliceCount: 1),
      ]);

      expect(loads, 1);
      cache.clear();
      expect(cache.length, 0);
    });
  });

  group('component', () {
    test('size and ground follow the projected bounds', () async {
      final image = await _solidImage(width: 4, height: 4, color: 0xFFFFFFFF);
      final stack = SpriteStack.fromImage(image, sliceCount: 2);

      final component = SpriteStackComponent(
        stack: stack,
        yaw: math.pi / 2,
        pitch: math.pi / 2,
        outline: false,
        shadow: false,
      );

      expect(component.size.x, 4);
      expect(component.size.y, 3);
      expect(component.groundLocal, const ui.Offset(2, 3));

      component.yaw = 0;
      expect(component.size.x, 2);
      expect(component.size.y, 5);
      expect(component.groundLocal, const ui.Offset(1, 5));

      component.stackScale = 2;
      expect(component.size.x, 4);
      expect(component.size.y, 10);

      stack.dispose();
    });
  });
}

Future<ui.Image> _solidImage({
  required int width,
  required int height,
  required int color,
}) async {
  final pixels = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    _writeColor(pixels, i * 4, color);
  }
  return _decode(pixels, width, height);
}

/// 4x4 strip with two 2x4 slices: red (ground) then green.
Future<ui.Image> _twoToneImage() async {
  const width = 4;
  const height = 4;
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final color = x < width ~/ 2 ? 0xFFFF0000 : 0xFF00FF00;
      _writeColor(pixels, (y * width + x) * 4, color);
    }
  }
  return _decode(pixels, width, height);
}

void _writeColor(Uint8List pixels, int offset, int argb) {
  pixels[offset] = (argb >> 16) & 0xFF; // r
  pixels[offset + 1] = (argb >> 8) & 0xFF; // g
  pixels[offset + 2] = argb & 0xFF; // b
  pixels[offset + 3] = (argb >> 24) & 0xFF; // a
}

Future<ui.Image> _decode(Uint8List pixels, int width, int height) {
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

Future<Uint8List> _renderToPixels(
  SpriteStack stack, {
  required int width,
  required int height,
  required ui.Offset position,
  required double pitch,
  double spacing = 1,
  bool outline = false,
  bool shadow = false,
  bool pixelSnap = true,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  stack.render(
    canvas,
    position: position,
    pitch: pitch,
    spacing: spacing,
    outline: outline,
    shadow: shadow,
    pixelSnap: pixelSnap,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

  image.dispose();
  picture.dispose();

  return data!.buffer.asUint8List();
}

int _pixelAt(Uint8List pixels, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  final r = pixels[offset];
  final g = pixels[offset + 1];
  final b = pixels[offset + 2];
  final a = pixels[offset + 3];
  return (a << 24) | (r << 16) | (g << 8) | b;
}
