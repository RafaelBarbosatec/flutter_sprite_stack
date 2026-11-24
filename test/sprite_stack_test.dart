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

      // Two 4x4 slices lifted 1 px: the top slice reaches row 15.
      expect(_pixelAt(pixels, 24, 12, 18), 0xFF3366FF);
      expect(_pixelAt(pixels, 24, 12, 15), 0xFF3366FF);
      expect(_pixelAt(pixels, 24, 12, 14), 0x00000000);

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
      expect(front.size.width, closeTo(2, 1e-9));
      expect(front.size.height, closeTo(5, 1e-9)); // 4 tall + 1 lift
      expect(front.ground.dx, closeTo(1, 1e-9));
      expect(front.ground.dy, closeTo(5, 1e-9));
      expect(front.rectAt(const ui.Offset(10, 20)),
          const ui.Rect.fromLTWH(9, 15, 2, 5));

      final side = stack.boundsFor(
        yaw: math.pi / 2,
        pitch: math.pi / 2,
        outline: false,
        shadow: false,
      );
      expect(side.size.width, closeTo(4, 1e-9)); // rotated footprint
      expect(side.size.height, closeTo(3, 1e-9)); // 2 tall + 1 lift
      expect(side.ground.dx, closeTo(2, 1e-9));
      expect(side.ground.dy, closeTo(3, 1e-9));

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
      expect(outline.size.width, closeTo(4, 1e-9)); // +1 px each side
      expect(outline.size.height, closeTo(7, 1e-9)); // +1 px below
      expect(outline.ground.dx, closeTo(2, 1e-9));
      expect(outline.ground.dy, closeTo(6, 1e-9));

      final withShadow = stack.boundsFor(
        pitch: math.pi / 2,
        outline: false,
        shadow: true,
      );
      // Shadow is dropped +3 px and extends half a slice below the feet.
      expect(withShadow.size.width, closeTo(2, 1e-9));
      expect(withShadow.size.height, closeTo(10, 1e-9));
      expect(withShadow.ground.dx, closeTo(1, 1e-9));
      expect(withShadow.ground.dy, closeTo(5, 1e-9));

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

  group('frames', () {
    test('decode() splits the atlas into vertical frames', () async {
      final image = await _twoFrameImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final stack = await SpriteStack.decode(
        png!.buffer.asUint8List(),
        sliceCount: 2,
        frameCount: 2,
      );

      expect(stack.frameCount, 2);
      expect(stack.sliceWidth, 4);
      expect(stack.sliceHeight, 4);

      final first = await _renderToPixels(
        stack,
        width: 24,
        height: 24,
        position: const ui.Offset(12, 20),
        pitch: math.pi / 2,
        frame: 0,
      );
      final second = await _renderToPixels(
        stack,
        width: 24,
        height: 24,
        position: const ui.Offset(12, 20),
        pitch: math.pi / 2,
        frame: 1,
      );

      expect(_pixelAt(first, 24, 12, 18), 0xFFFF0000);
      expect(_pixelAt(second, 24, 12, 18), 0xFF00FF00);

      image.dispose();
      stack.dispose();
    });

    test('frame is clamped to the atlas range', () async {
      final image = await _twoFrameImage();
      final stack = SpriteStack.fromImage(image, sliceCount: 2, frameCount: 2);

      final last = await _renderToPixels(
        stack,
        width: 24,
        height: 24,
        position: const ui.Offset(12, 20),
        pitch: math.pi / 2,
        frame: 99,
      );

      expect(_pixelAt(last, 24, 12, 18), 0xFF00FF00);

      stack.dispose();
    });

    test('rejects atlases that do not split into frames', () async {
      final image = await _solidImage(width: 8, height: 5, color: 0xFFFFFFFF);

      expect(
        () => SpriteStack.fromImage(image, sliceCount: 2, frameCount: 2),
        throwsArgumentError,
      );
      expect(
        () => SpriteStack.fromImage(image, sliceCount: 2, frameCount: 0),
        throwsArgumentError,
      );

      image.dispose();
    });
  });

  group('animation', () {
    test('advances one frame per frameDuration and loops', () async {
      final stack = await _fourFrameStack();
      final animation = SpriteStackAnimation(stack, frameDuration: 0.1);

      expect(animation.frame, 0);
      expect(animation.isPlaying, isTrue);

      animation.update(0.1);
      expect(animation.frame, 1);

      // 0.25s = two whole frames plus a 0.05 remainder.
      animation.update(0.25);
      expect(animation.frame, 3);

      animation.update(0.1); // wraps back to the first frame
      expect(animation.frame, 0);

      stack.dispose();
    });

    test('stops on the last frame and notifies once', () async {
      final stack = await _fourFrameStack();
      var completions = 0;
      final animation = SpriteStackAnimation(
        stack,
        frameDuration: 0.1,
        loop: false,
        onComplete: () => completions++,
      );

      animation.update(1);
      expect(animation.frame, 3);
      expect(animation.isFinished, isTrue);
      expect(animation.isPlaying, isFalse);
      expect(completions, 1);

      animation.update(1);
      expect(completions, 1);

      stack.dispose();
    });

    test('pingPong bounces between the ends', () async {
      final stack = await _fourFrameStack();
      final animation = SpriteStackAnimation(
        stack,
        frameDuration: 0.1,
        pingPong: true,
      );

      // Ticks: 0,1,2,3,2,1,0...
      final seen = <int>[];
      for (var i = 0; i < 7; i++) {
        seen.add(animation.frame);
        animation.update(0.1);
      }

      expect(seen, [0, 1, 2, 3, 2, 1, 0]);

      stack.dispose();
    });

    test('play, stop and reset control playback', () async {
      final stack = await _fourFrameStack();
      final animation = SpriteStackAnimation(stack, frameDuration: 0.1);

      animation.update(0.1);
      animation.stop();
      animation.update(0.5);
      expect(animation.frame, 1);

      animation.play();
      animation.update(0.1);
      expect(animation.frame, 2);

      animation.reset();
      expect(animation.frame, 0);
      expect(animation.isPlaying, isFalse);
      expect(animation.isFinished, isFalse);

      stack.dispose();
    });

    test('onFrame fires only when the visible frame changes', () async {
      final stack = await _fourFrameStack();
      final frames = <int>[];
      final animation = SpriteStackAnimation(
        stack,
        frameDuration: 0.1,
        onFrame: frames.add,
      );

      animation.update(0.05); // no change
      animation.update(0.05); // frame 1
      animation.update(0.2); // skips frame 2 and lands on 3

      expect(frames, [1, 3]);

      stack.dispose();
    });
  });

  group('motion', () {
    test('pins the ground slice and grows with the square of the height',
        () async {
      final stack = await _fiveSliceStack();
      const motion = StackMotion(lean: ui.Offset(4, 0));

      expect(motion.offsetAt(0, 5, 0), ui.Offset.zero);
      expect(motion.offsetAt(2, 5, 0).dx, closeTo(1, 1e-9)); // 0.5² × 4
      expect(motion.offsetAt(4, 5, 0).dx, closeTo(4, 1e-9)); // 1² × 4

      stack.dispose();
    });

    test('sway oscillates over time', () async {
      const motion =
          StackMotion(sway: 4, speed: 1, wave: 0, phase: math.pi / 2);

      expect(motion.offsetAt(1, 2, 0).dx, closeTo(4, 1e-9)); // sin(π/2)
      expect(motion.offsetAt(1, 2, math.pi / 2).dx, closeTo(0, 1e-9)); // sin(π)
      expect(motion.offsetAt(1, 2, math.pi).dx, closeTo(-4, 1e-9));
    });

    test('isEmpty ignores the ground slice', () async {
      expect(const StackMotion().isEmpty, isTrue);
      expect(const StackMotion(lean: ui.Offset(1, 0)).isEmpty, isFalse);

      final stack = await _fiveSliceStack();
      expect(const StackMotion().offsetAt(4, 5, 12), ui.Offset.zero);
      stack.dispose();
    });

    test('lean shifts the upper slices in the rasterizer', () async {
      final stack = await _twoSliceStack();

      final pixels = await _renderToPixels(
        stack,
        width: 32,
        height: 24,
        position: const ui.Offset(12, 20),
        pitch: math.pi / 2,
        motion: const StackMotion(lean: ui.Offset(4, 0)),
      );

      // Ground slice stays put (x 10..14), the top slice moves +4 (x 14..18).
      expect(_pixelAt(pixels, 32, 12, 18), 0xFFFF0000);
      expect(_pixelAt(pixels, 32, 16, 17), 0xFF00FF00);
      expect(_pixelAt(pixels, 32, 8, 17), 0x00000000);

      stack.dispose();
    });
  });

  group('slice cut', () {
    test('frontiers are continuous and clamped', () {
      const top = SliceCut(top: 2);
      expect(top.isActive, isTrue);
      expect(top.visibilityAt(0), 1);
      expect(top.visibilityAt(1), 1);
      expect(top.visibilityAt(2), 0);

      const half = SliceCut(top: 1.5);
      expect(half.visibilityAt(1), closeTo(0.5, 1e-9));
      expect(half.visibilityAt(2), 0);

      const bottom = SliceCut(bottom: 1.5);
      expect(bottom.visibilityAt(0), 0);
      expect(bottom.visibilityAt(1), closeTo(0.5, 1e-9));
      expect(bottom.visibilityAt(2), 1);

      expect(const SliceCut().isActive, isFalse);
      expect(const SliceCut().visibilityAt(3), 1);
    });

    test('the Bayer dither keeps half the pixels at 50%', () {
      final drawn = <bool>[];
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          drawn.add(bayerAllows(x, y, 0.5));
        }
      }
      expect(drawn.where((d) => d).length, 8);
      expect(bayerAllows(0, 0, 1), isTrue);
      expect(bayerAllows(0, 0, 0), isFalse);
    });

    test('hides every slice above the frontier', () async {
      final stack = await _fourSliceStack();

      final pixels = await _renderToPixels(
        stack,
        width: 24,
        height: 24,
        position: const ui.Offset(12, 20),
        pitch: math.pi / 2,
        spacing: 4,
        cut: const SliceCut(top: 2),
      );

      // 4x4 slices with spacing 4: red 16..20, green 12..16, then cut.
      expect(_pixelAt(pixels, 24, 12, 18), 0xFFFF0000);
      expect(_pixelAt(pixels, 24, 12, 14), 0xFF00FF00);
      expect(_pixelAt(pixels, 24, 12, 10), 0x00000000);
      expect(_pixelAt(pixels, 24, 12, 6), 0x00000000);

      stack.dispose();
    });

    test('hides slices below the frontier', () async {
      final stack = await _fourSliceStack();

      final pixels = await _renderToPixels(
        stack,
        width: 24,
        height: 24,
        position: const ui.Offset(12, 20),
        pitch: math.pi / 2,
        spacing: 4,
        cut: const SliceCut(bottom: 2),
      );

      expect(_pixelAt(pixels, 24, 12, 18), 0x00000000);
      expect(_pixelAt(pixels, 24, 12, 14), 0x00000000);
      expect(_pixelAt(pixels, 24, 12, 10), 0xFF0000FF);

      stack.dispose();
    });

    test('bounds shrink to the visible slices', () async {
      final stack = await _fourSliceStack();

      final full = stack.boundsFor(
        pitch: math.pi / 2,
        spacing: 4,
        outline: false,
        shadow: false,
      );
      final cut = stack.boundsFor(
        pitch: math.pi / 2,
        spacing: 4,
        cut: const SliceCut(top: 2),
        outline: false,
        shadow: false,
      );

      expect(full.size.height, closeTo(16, 1e-9));
      expect(cut.size.height, closeTo(8, 1e-9));

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

/// 8x8 atlas: two 4x4 slices per row, frame 0 red and frame 1 green.
Future<ui.Image> _twoFrameImage() async {
  const width = 8;
  const height = 8;
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    final color = y < height ~/ 2 ? 0xFFFF0000 : 0xFF00FF00;
    for (var x = 0; x < width; x++) {
      _writeColor(pixels, (y * width + x) * 4, color);
    }
  }
  return _decode(pixels, width, height);
}

/// 16x4 strip: four 4x4 slices, one colour per slice.
Future<SpriteStack> _fourSliceStack() async {
  const slice = 4;
  const count = 4;
  const width = slice * count;
  const height = slice;
  const colors = [0xFFFF0000, 0xFF00FF00, 0xFF0000FF, 0xFFFFFF00];

  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      _writeColor(pixels, (y * width + x) * 4, colors[x ~/ slice]);
    }
  }

  final image = await _decode(pixels, width, height);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final stack = await SpriteStack.decode(
    png!.buffer.asUint8List(),
    sliceCount: count,
  );
  image.dispose();
  return stack;
}

/// 8x4 strip: two 4x4 slices, red on the ground and green on top.
Future<SpriteStack> _twoSliceStack() async {
  const width = 8;
  const height = 4;
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final color = x < width ~/ 2 ? 0xFFFF0000 : 0xFF00FF00;
      _writeColor(pixels, (y * width + x) * 4, color);
    }
  }
  final image = await _decode(pixels, width, height);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final stack = await SpriteStack.decode(
    png!.buffer.asUint8List(),
    sliceCount: 2,
  );
  image.dispose();
  return stack;
}

/// Five slices of 1x1 source pixels, enough to check the motion falloff.
Future<SpriteStack> _fiveSliceStack() async {
  final image = await _solidImage(width: 5, height: 1, color: 0xFFFFFFFF);
  return SpriteStack.fromImage(image, sliceCount: 5);
}

/// Four stacked frames, enough to exercise playback without rendering.
Future<SpriteStack> _fourFrameStack() async {
  final image = await _solidImage(width: 4, height: 8, color: 0xFFFFFFFF);
  return SpriteStack.fromImage(image, sliceCount: 1, frameCount: 4);
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
  int frame = 0,
  StackMotion? motion,
  double time = 0,
  SliceCut? cut,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  stack.render(
    canvas,
    position: position,
    pitch: pitch,
    spacing: spacing,
    frame: frame,
    motion: motion,
    time: time,
    cut: cut,
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
