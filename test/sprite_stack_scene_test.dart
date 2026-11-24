import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SpriteStackPoint', () {
    test('supports vector arithmetic', () {
      const a = SpriteStackPoint(1, 2, 3);
      const b = SpriteStackPoint(4, 5, 6);

      expect(a + b, const SpriteStackPoint(5, 7, 9));
      expect(b - a, const SpriteStackPoint(3, 3, 3));
      expect(a * 2, const SpriteStackPoint(2, 4, 6));
      expect(-a, const SpriteStackPoint(-1, -2, -3));
      expect(a.dot(b), 32);
      expect(a.cross(b), const SpriteStackPoint(-3, 6, -3));
      expect(const SpriteStackPoint(3, 4, 0).length, 5);
      final normalized = const SpriteStackPoint(3, 4, 0).normalized;
      expect(normalized.x, closeTo(0.6, 1e-12));
      expect(normalized.y, closeTo(0.8, 1e-12));
      expect(normalized.z, closeTo(0, 1e-12));
      expect(SpriteStackPoint.zero.normalized, SpriteStackPoint.zero);
    });
  });

  group('SpriteStackCamera', () {
    test('orbits the target on a sphere', () {
      final camera = SpriteStackCamera.orbit(
        yaw: 0,
        pitch: 0,
        distance: 100,
      );

      expect(camera.eye.x, closeTo(0, 1e-9));
      expect(camera.eye.y, closeTo(-100, 1e-9));
      expect(camera.eye.z, closeTo(0, 1e-9));
      expect(camera.basis.depthOf(SpriteStackPoint.zero), closeTo(100, 1e-9));

      camera.yaw = math.pi / 2;
      expect(camera.eye.x, closeTo(100, 1e-9));
      expect(camera.eye.y, closeTo(0, 1e-9));
      expect(camera.basis.depthOf(SpriteStackPoint.zero), closeTo(100, 1e-9));
    });

    test('builds an orthonormal basis pointing at the target', () {
      final camera = SpriteStackCamera.orbit(yaw: 0, pitch: 0, distance: 100);
      final basis = camera.basis;

      expect(basis.forward.x, closeTo(0, 1e-12));
      expect(basis.forward.y, closeTo(1, 1e-12));
      expect(basis.forward.z, closeTo(0, 1e-12));
      expect(basis.right.x, closeTo(1, 1e-12));
      expect(basis.right.y, closeTo(0, 1e-12));
      expect(basis.right.z, closeTo(0, 1e-12));
      expect(basis.up.x, closeTo(0, 1e-12));
      expect(basis.up.y, closeTo(0, 1e-12));
      expect(basis.up.z, closeTo(1, 1e-12));
      expect(basis.forward.dot(basis.right), closeTo(0, 1e-9));
      expect(basis.forward.dot(basis.up), closeTo(0, 1e-9));
      expect(basis.right.dot(basis.up), closeTo(0, 1e-9));

      expect(
          basis.depthOf(const SpriteStackPoint(0, -50, 0)), closeTo(50, 1e-9));
      expect(
          basis.depthOf(const SpriteStackPoint(0, 50, 0)), closeTo(150, 1e-9));
      expect(basis.depthOf(const SpriteStackPoint(0, -200, 0)),
          closeTo(-100, 1e-9));
      expect(basis.horizontalOf(const SpriteStackPoint(10, 0, 0)),
          closeTo(10, 1e-9));
      expect(basis.verticalOf(const SpriteStackPoint(0, 0, 10)),
          closeTo(10, 1e-9));
    });

    test('clamps the pitch just short of straight down', () {
      final camera = SpriteStackCamera.orbit(pitch: 10);

      expect(camera.pitch, SpriteStackCamera.maxPitch);
      expect(camera.pitch, lessThan(math.pi / 2));
      expect(camera.eye.z, greaterThan(99));

      camera.pitch = -1;
      expect(camera.pitch, 0);
    });

    test('keeps the distance when the target moves', () {
      final camera = SpriteStackCamera.orbit(
        yaw: 0,
        pitch: 0,
        distance: 10,
        target: const SpriteStackPoint(5, 5, 5),
      );

      expect(camera.eye, const SpriteStackPoint(5, -5, 5));
      expect(camera.basis.depthOf(camera.target), closeTo(10, 1e-9));
    });
  });

  group('SpriteStackScene projection', () {
    test('puts the target in the centre of the canvas', () async {
      final stack = await _solidStack(0xFFFF0000);
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0, pitch: 0, distance: 100),
      );
      final object = SpriteStackSceneObject(stack: stack);

      final projection = scene.projectObject(object, const ui.Size(200, 200))!;

      expect(projection.position.dx, closeTo(100, 1e-9));
      expect(projection.position.dy, closeTo(100, 1e-9));
      expect(projection.depth, closeTo(100, 1e-9));
      expect(projection.scale, closeTo(1, 1e-9));
      expect(projection.yaw, 0);

      stack.dispose();
    });

    test('maps world x to screen right and world z to screen up', () async {
      final stack = await _solidStack(0xFFFF0000);
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0, pitch: 0, distance: 100),
        zoom: 2,
      );
      final object = SpriteStackSceneObject(stack: stack);
      const size = ui.Size(200, 200);

      object.position = const SpriteStackPoint(50, 0, 0);
      final right = scene.projectObject(object, size)!;
      expect(right.position.dx, closeTo(200, 1e-9));
      expect(right.position.dy, closeTo(100, 1e-9));

      object.position = const SpriteStackPoint(0, 0, 50);
      final up = scene.projectObject(object, size)!;
      expect(up.position.dx, closeTo(100, 1e-9));
      expect(up.position.dy, closeTo(0, 1e-9));

      stack.dispose();
    });

    test('scales with zoom, object scale and perspective depth', () async {
      final stack = await _solidStack(0xFFFF0000);
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0, pitch: 0, distance: 100),
        zoom: 2,
      );
      final object = SpriteStackSceneObject(stack: stack, scale: 1.5);
      const size = ui.Size(200, 200);

      expect(scene.projectObject(object, size)!.scale, closeTo(3, 1e-9));

      // Half the distance to the target doubles the projected scale.
      object.position = const SpriteStackPoint(0, -50, 0);
      expect(scene.projectObject(object, size)!.scale, closeTo(6, 1e-9));

      // Twice as far halves it.
      object.position = const SpriteStackPoint(0, 100, 0);
      expect(scene.projectObject(object, size)!.scale, closeTo(1.5, 1e-9));

      stack.dispose();
    });

    test('subtracts the camera yaw from the prop yaw', () async {
      final stack = await _solidStack(0xFFFF0000);
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0.1),
      );
      final object = SpriteStackSceneObject(stack: stack, yaw: 0.3);

      final projection = scene.projectObject(object, const ui.Size(200, 200))!;

      expect(projection.yaw, closeTo(0.2, 1e-9));

      stack.dispose();
    });

    test('returns null behind the camera', () async {
      final stack = await _solidStack(0xFFFF0000);
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0, pitch: 0, distance: 100),
      );
      final object = SpriteStackSceneObject(
        stack: stack,
        position: const SpriteStackPoint(0, -200, 0),
      );

      expect(scene.projectObject(object, const ui.Size(200, 200)), isNull);

      stack.dispose();
    });

    test('bounds follow the projected ground point and can cull', () async {
      final stack = await _solidStack(0xFFFF0000);
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0, pitch: 0, distance: 100),
        zoom: 4,
      );
      final object = SpriteStackSceneObject(stack: stack);
      const size = ui.Size(200, 200);

      final centered = scene.projectObject(object, size)!;
      expect(centered.bounds.contains(centered.position), isTrue);
      expect(centered.isVisibleIn(size), isTrue);

      object.position = const SpriteStackPoint(10000, 0, 0);
      final offscreen = scene.projectObject(object, size)!;
      expect(offscreen.isVisibleIn(size), isFalse);

      stack.dispose();
    });
  });

  group('SpriteStackGround painting', () {
    test('paints a solid floor', () async {
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0, pitch: 0.7, distance: 400),
        background: const ui.Color(0xFF000000),
        ground: const SpriteStackGround(
          extent: 400,
          step: 0,
          fill: ui.Color(0xFF203040),
        ),
      );

      final pixels = await _render(scene);

      // The target is on the plane, so the canvas centre is floor.
      expect(_pixelAt(pixels, 200, 100, 100), 0xFF203040);
      expect(_pixelAt(pixels, 200, 100, 150), 0xFF203040);
    });

    test('alternates checker cells', () async {
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0, pitch: 0.7, distance: 400),
        background: const ui.Color(0xFF000000),
        ground: const SpriteStackGround(
          extent: 400,
          step: 0,
          cellSize: 100,
          checker: [ui.Color(0xFFFF0000), ui.Color(0xFF0000FF)],
        ),
      );

      final pixels = await _render(scene);

      expect(_countColor(pixels, 0xFFFF0000), greaterThan(500));
      expect(_countColor(pixels, 0xFF0000FF), greaterThan(500));
    });

    test('gives colorAt the world position of each cell', () async {
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0, pitch: 0.7, distance: 400),
        background: const ui.Color(0xFF000000),
        ground: SpriteStackGround(
          extent: 400,
          step: 0,
          cellSize: 50,
          colorAt: (x, y) =>
              x < 0 ? const ui.Color(0xFFFF0000) : const ui.Color(0xFF0000FF),
        ),
      );

      final pixels = await _render(scene);

      expect(_countColor(pixels, 0xFFFF0000), greaterThan(500));
      expect(_countColor(pixels, 0xFF0000FF), greaterThan(500));
    });

    test('fades distant cells towards fadeColor', () async {
      SpriteStackScene scene({ui.Color? fadeColor, double fadeDistance = 0}) =>
          SpriteStackScene(
            camera: SpriteStackCamera.orbit(yaw: 0, pitch: 0.7, distance: 400),
            background: const ui.Color(0xFF000000),
            ground: SpriteStackGround(
              extent: 400,
              step: 0,
              fill: const ui.Color(0xFFFF0000),
              fadeColor: fadeColor,
              fadeDistance: fadeDistance,
            ),
          );

      final plain = await _render(scene());
      final faded = await _render(
        scene(fadeColor: const ui.Color(0xFF000000), fadeDistance: 300),
      );

      expect(_countColor(plain, 0xFFFF0000), greaterThan(500));
      // Every visible cell has depth > 0, so none stays exactly red.
      expect(_countColor(faded, 0xFFFF0000), 0);
    });

    test('paints no cells when cellSize is zero', () async {
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0, pitch: 0.7, distance: 400),
        background: const ui.Color(0xFF000000),
        ground: const SpriteStackGround(
          extent: 400,
          step: 0,
          cellSize: 0,
          fill: ui.Color(0xFFFF0000),
        ),
      );

      final pixels = await _render(scene);

      expect(_countColor(pixels, 0xFFFF0000), 0);
      expect(_pixelAt(pixels, 200, 100, 100), 0xFF000000);
    });

    test('clips cells when the camera sits on the plane', () async {
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0, pitch: 0, distance: 400),
        background: const ui.Color(0xFF000000),
        ground: const SpriteStackGround(
          extent: 400,
          step: 0,
          fill: ui.Color(0xFF203040),
        ),
      );

      // Edge-on plane: most cells clip away, but painting must not throw.
      final pixels = await _render(scene);

      expect(pixels.length, 200 * 200 * 4);
    });
  });

  group('SpriteStackScene paint', () {
    test('fills the background', () async {
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0, pitch: 0.6, distance: 300),
        background: const ui.Color(0xFF102030),
      );

      final pixels = await _render(scene);

      expect(_pixelAt(pixels, 200, 100, 100), 0xFF102030);
    });

    test('draws near objects over far ones regardless of list order', () async {
      final far = await _solidStack(0xFFFF0000, sliceCount: 4);
      final near = await _solidStack(0xFF00FF00, sliceCount: 4);

      final camera = SpriteStackCamera.orbit(yaw: 0, pitch: 0.6, distance: 300);
      final forward = camera.basis.forward;

      Future<int> paint(List<SpriteStackSceneObject> objects) async {
        final scene = SpriteStackScene(camera: camera, objects: objects);
        final pixels = await _render(scene);
        // Both props sit on the camera's view axis, so they project onto the
        // centre of the canvas and overlap; this pixel is inside both.
        return _pixelAt(pixels, 200, 100, 90);
      }

      final farObject = SpriteStackSceneObject(
        stack: far,
        position: forward * 60,
        scale: 4,
        outline: false,
        shadow: false,
      );
      final nearObject = SpriteStackSceneObject(
        stack: near,
        position: forward * -50,
        scale: 4,
        outline: false,
        shadow: false,
      );

      expect(await paint([farObject, nearObject]), 0xFF00FF00);
      expect(await paint([nearObject, farObject]), 0xFF00FF00);

      far.dispose();
      near.dispose();
    });

    test('skips objects behind the camera and outside the canvas', () async {
      final stack = await _solidStack(0xFFFF0000);
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0, pitch: 0, distance: 100),
        background: const ui.Color(0xFF000000),
      );

      scene.objects.add(
        SpriteStackSceneObject(
          stack: stack,
          position: const SpriteStackPoint(0, -200, 0),
          outline: false,
          shadow: false,
        ),
      );
      scene.objects.add(
        SpriteStackSceneObject(
          stack: stack,
          position: const SpriteStackPoint(10000, 0, 0),
          outline: false,
          shadow: false,
        ),
      );

      final pixels = await _render(scene);

      expect(_pixelAt(pixels, 200, 100, 100), 0xFF000000);

      stack.dispose();
    });

    test('paints the ground grid', () async {
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0.4, pitch: 0.7, distance: 400),
        background: const ui.Color(0xFF000000),
        ground: const SpriteStackGround(
          extent: 800,
          step: 100,
          color: ui.Color(0xFF203040),
          axisColor: ui.Color(0xFF203040),
        ),
      );

      final pixels = await _render(scene);

      var painted = 0;
      for (var i = 0; i < 200 * 200; i++) {
        if (_pixelAt(pixels, 200, i % 200, i ~/ 200) != 0xFF000000) {
          painted++;
        }
      }
      expect(painted, greaterThan(0));
    });

    test('paints with an empty scene', () async {
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(),
        background: const ui.Color(0xFF445566),
      );

      final pixels = await _render(scene);

      expect(_pixelAt(pixels, 200, 0, 0), 0xFF445566);
    });
  });
}

Future<SpriteStack> _solidStack(int argb, {int sliceCount = 1}) async {
  const sliceHeight = 4;
  const sliceWidth = 4;
  final width = sliceWidth * sliceCount;
  final pixels = Uint8List(width * sliceHeight * 4);
  for (var i = 0; i < width * sliceHeight; i++) {
    final offset = i * 4;
    pixels[offset] = (argb >> 16) & 0xFF;
    pixels[offset + 1] = (argb >> 8) & 0xFF;
    pixels[offset + 2] = argb & 0xFF;
    pixels[offset + 3] = (argb >> 24) & 0xFF;
  }
  final image = await _decodeImage(pixels, width, sliceHeight);
  return SpriteStack.fromImage(
    image,
    sliceCount: sliceCount,
  );
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

Future<Uint8List> _render(SpriteStackScene scene) async {
  const size = ui.Size(200, 200);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  scene.paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 200);
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

int _countColor(Uint8List pixels, int argb) {
  var count = 0;
  for (var offset = 0; offset < pixels.length; offset += 4) {
    final value = (pixels[offset + 3] << 24) |
        (pixels[offset] << 16) |
        (pixels[offset + 1] << 8) |
        pixels[offset + 2];
    if (value == argb) count++;
  }
  return count;
}
