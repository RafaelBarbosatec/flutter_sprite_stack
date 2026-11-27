import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';
import 'package:flutter_test/flutter_test.dart';

const ui.Size _size = ui.Size(400, 300);
const int _green = 0xFF00FF00;
const int _orange = 0xFFFFB020;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('projectPoint', () {
    test('maps the orbit target to the canvas centre', () {
      final scene = _scene();

      final point = scene.projectPoint(SpriteStackPoint.zero, _size);

      expect(point, isNotNull);
      expect(point!.dx, closeTo(_size.width / 2, 1e-6));
      expect(point.dy, closeTo(_size.height / 2, 1e-6));
    });

    test('returns null behind the camera', () {
      final scene = _scene();
      final forward = scene.camera.basis.forward;

      // A thousand units opposite the view direction, from the target.
      final behind = SpriteStackPoint(
        scene.camera.target.x - 1000 * forward.x,
        scene.camera.target.y - 1000 * forward.y,
        scene.camera.target.z - 1000 * forward.z,
      );

      expect(scene.projectPoint(behind, _size), isNull);
    });
  });

  group('paintCollisionDebug', () {
    test('draws one quad per collider and leaves its middle empty', () async {
      final object = await _boxedObject();
      final scene = _scene(objects: [object]);

      final rgba = await _paint(
        scene,
        strokeWidth: 3,
        color: const ui.Color(_green),
        fillColor: const ui.Color(0x00000000),
      );

      expect(_count(rgba, _green), greaterThan(100));
      // Only the outline is stroked; the middle of the footprint stays clear.
      final body = scene.collisionBodyOf(object)!;
      final centre = scene.projectPoint(
        SpriteStackPoint(body.center.dx, body.center.dy, 0),
        _size,
      )!;
      expect(_alphaAt(rgba, centre.dx.round(), centre.dy.round()), 0);
    });

    test('ignores the requested object', () async {
      final object = await _boxedObject();
      final scene = _scene(objects: [object]);

      final rgba = await _paint(
        scene,
        strokeWidth: 3,
        color: const ui.Color(_green),
        ignore: object,
      );

      expect(_count(rgba, _green), 0);
    });

    test('paints bodies under stepHeight as walked over', () async {
      final object = await _boxedObject(height: 12);
      final scene = _scene(objects: [object]);

      final rgba = await _paint(
        scene,
        strokeWidth: 3,
        color: const ui.Color(_green),
        steppedOverColor: const ui.Color(_orange),
        stepHeight: 30,
      );

      expect(_count(rgba, _green), 0);
      expect(_count(rgba, _orange), greaterThan(100));
    });

    test('height posts add lines above the corners', () async {
      final object = await _boxedObject();
      final scene = _scene(objects: [object]);

      final withPosts = await _paint(
        scene,
        strokeWidth: 3,
        color: const ui.Color(_green),
        heightPosts: true,
      );
      final withoutPosts = await _paint(
        scene,
        strokeWidth: 3,
        color: const ui.Color(_green),
      );

      expect(
        _count(withPosts, _green),
        greaterThan(_count(withoutPosts, _green)),
      );
    });

    test('draws the character circle', () async {
      final object = await _boxedObject();
      final scene = _scene(objects: [object]);

      final withCircle = await _paint(
        scene,
        strokeWidth: 3,
        color: const ui.Color(_green),
        ignore: object,
        circle: SpriteStackPoint.zero,
        circleRadius: 30,
      );
      final withoutCircle = await _paint(
        scene,
        strokeWidth: 3,
        color: const ui.Color(_green),
        ignore: object,
      );

      expect(_count(withoutCircle, _green), 0);
      expect(_count(withCircle, _green), greaterThan(100));
    });

    test('draws nothing for props without a collider', () async {
      final object = SpriteStackSceneObject(
        stack: await _solidStack(),
        position: SpriteStackPoint.zero,
      );
      final scene = _scene(objects: [object]);

      final rgba = await _paint(
        scene,
        strokeWidth: 3,
        color: const ui.Color(_green),
      );

      expect(_count(rgba, _green), 0);
    });
  });
}

SpriteStackScene _scene({List<SpriteStackSceneObject> objects = const []}) {
  final scene = SpriteStackScene(
    camera: SpriteStackCamera.orbit(
      yaw: 0.4,
      pitch: 0.6,
      distance: 400,
      target: SpriteStackPoint.zero,
    ),
    zoom: 1.5,
    objects: List.of(objects),
  );
  // The overlay only projects; the stack never has to draw.
  scene.minimumProjectedPixels = 0;
  return scene;
}

Future<SpriteStackSceneObject> _boxedObject({double height = 30}) async =>
    SpriteStackSceneObject(
      stack: await _solidStack(),
      position: SpriteStackPoint.zero,
      yaw: 0.3,
      collider:
          SpriteStackCollider(size: const ui.Size(40, 20), height: height),
    );

/// 8x8 opaque stack, enough for the scene to resolve a prop.
Future<SpriteStack> _solidStack() async {
  final pixels = Uint8List(8 * 8 * 4);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = 200;
    pixels[i + 1] = 120;
    pixels[i + 2] = 60;
    pixels[i + 3] = 255;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    8,
    8,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  final image = await completer.future;
  return SpriteStack.fromImage(image, sliceCount: 1);
}

Future<Uint8List> _paint(
  SpriteStackScene scene, {
  required double strokeWidth,
  required ui.Color color,
  ui.Color? fillColor,
  ui.Color? steppedOverColor,
  SpriteStackSceneObject? ignore,
  double stepHeight = 0,
  SpriteStackPoint? circle,
  double circleRadius = 0,
  bool heightPosts = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  scene.paintCollisionDebug(
    canvas,
    _size,
    color: color,
    fillColor: fillColor ?? const ui.Color(0x00000000),
    steppedOverColor: steppedOverColor ?? const ui.Color(_orange),
    strokeWidth: strokeWidth,
    ignore: ignore,
    stepHeight: stepHeight,
    circle: circle,
    circleRadius: circleRadius,
    heightPosts: heightPosts,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    _size.width.toInt(),
    _size.height.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

int _count(Uint8List rgba, int argb) {
  final rgb = argb & 0xFFFFFF;
  var count = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i + 3] == 0) continue;
    if (((rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2]) == rgb) count++;
  }
  return count;
}

int _alphaAt(Uint8List rgba, int x, int y) =>
    rgba[(y * _size.width.toInt() + x) * 4 + 3];
