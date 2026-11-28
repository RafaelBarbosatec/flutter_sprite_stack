import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;
import 'dart:ui' as ui;

import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SpriteStackCollisionBody', () {
    const box = SpriteStackCollisionBody(
      center: Offset.zero,
      halfWidth: 10,
      halfDepth: 10,
    );

    test('a point inside overlaps, a point outside does not', () {
      expect(box.overlaps(Offset.zero, 0), isTrue);
      expect(box.overlaps(const Offset(15, 0), 2), isFalse);
      expect(box.overlaps(const Offset(11, 0), 2), isTrue);
    });

    test('touching the surface is not an overlap', () {
      expect(box.overlaps(const Offset(12, 0), 2), isFalse);
      expect(box.resolve(const Offset(12, 0), 2), isNull);
    });

    test('a circle on a face is pushed out along the normal', () {
      expect(box.resolve(const Offset(11, 0), 2), const Offset(12, 0));
      expect(box.resolve(const Offset(-11, 0), 2), const Offset(-12, 0));
      expect(box.resolve(const Offset(0, 11), 2), const Offset(0, 12));
    });

    test('a circle on a corner is pushed along the diagonal', () {
      final resolved = box.resolve(const Offset(11, 11), 2);

      expect(resolved, isNotNull);
      expect((resolved! - const Offset(10, 10)).distance, closeTo(2, 1e-9));
      expect(resolved.dx, closeTo(resolved.dy, 1e-9));
    });

    test('a centre inside the box leaves through the nearest face', () {
      expect(box.resolve(const Offset(9, 1), 2), const Offset(12, 1));
    });

    test('a rotated body pushes along its rotated normal', () {
      const rotated = SpriteStackCollisionBody(
        center: Offset.zero,
        halfWidth: 10,
        halfDepth: 4,
        yaw: math.pi / 2,
      );

      // Local +x is world +y after a quarter turn.
      expect(rotated.overlaps(const Offset(0, 11.5), 2), isTrue);
      final resolved = rotated.resolve(const Offset(0, 11.5), 2)!;
      expect(resolved.dx, closeTo(0, 1e-9));
      expect(resolved.dy, closeTo(12, 1e-9));
    });

    test('bounds are the world AABB of the rotated box', () {
      const rotated = SpriteStackCollisionBody(
        center: Offset(5, 5),
        halfWidth: 10,
        halfDepth: 4,
        yaw: math.pi / 4,
      );

      final extent = (10 + 4) * 0.7071067811865476;
      expect(rotated.bounds.left, closeTo(5 - extent, 1e-9));
      expect(rotated.bounds.right, closeTo(5 + extent, 1e-9));
      expect(rotated.bounds.top, closeTo(5 - extent, 1e-9));
      expect(rotated.bounds.bottom, closeTo(5 + extent, 1e-9));
    });

    test('a degenerate body never blocks', () {
      const flat = SpriteStackCollisionBody(
        center: Offset.zero,
        halfWidth: 0,
        halfDepth: 10,
      );

      expect(flat.isDegenerate, isTrue);
      expect(flat.overlaps(Offset.zero, 5), isFalse);
      expect(flat.resolve(Offset.zero, 5), isNull);
    });
  });

  group('SpriteStackScene.collisionBodyOf', () {
    test('derives the footprint from the volume bounds', () async {
      final stack = await _stackFromSlices(
        [_solidMask(width: 4, depth: 4)],
        width: 4,
        depth: 4,
      );
      final object = SpriteStackSceneObject(
        stack: stack,
        position: const SpriteStackPoint(100, 200, 0),
        scale: 2,
        collider: const SpriteStackCollider(),
      );
      final scene = SpriteStackScene(objects: [object]);

      final body = scene.collisionBodyOf(object)!;

      // The footprint is centred on the prop: half of the 4 px depth, scaled
      // by 2, on each side. The renderer pivots the sprite on the same point.
      expect(body.center, const Offset(100, 200));
      expect(body.halfWidth, 4);
      expect(body.halfDepth, 4);
      expect(body.yaw, closeTo(0, 1e-9));
      expect(body.height, 2); // one slice x spacing 1 x scale 2.

      stack.dispose();
    });

    test('centres the footprint on the prop when the art is off-centre',
        () async {
      // Solid only on the right half of the slice.
      final stack = await _stackFromSlices(
        [_solidMask(width: 6, depth: 4, minX: 4, maxX: 5)],
        width: 6,
        depth: 4,
      );
      final object = SpriteStackSceneObject(
        stack: stack,
        position: const SpriteStackPoint(100, 200, 0),
        scale: 2,
        collider: const SpriteStackCollider(),
      );
      final scene = SpriteStackScene(objects: [object]);

      final body = scene.collisionBodyOf(object)!;

      // The prop stands on its footprint centre: the renderer shifts the art so
      // that centre lands on `position`, and the proxy is centred there too, so
      // solid pixels sitting to one side of the strip do not drag it away.
      expect(body.center, const Offset(100, 200));
      expect(body.halfWidth, 2); // two solid columns x scale 2 / 2.
      expect(body.halfDepth, 4);

      stack.dispose();
    });

    test('takes height from the top solid slice', () async {
      final stack = await _stackFromSlices(
        [
          _solidMask(width: 2, depth: 2),
          _solidMask(width: 2, depth: 2),
          _solidMask(width: 2, depth: 2),
        ],
        width: 2,
        depth: 2,
      );
      final object = SpriteStackSceneObject(
        stack: stack,
        position: SpriteStackPoint.zero,
        collider: const SpriteStackCollider(),
      );
      final scene = SpriteStackScene(objects: [object]);

      expect(scene.collisionBodyOf(object)!.height, 3);
      object.spacing = 2;
      expect(scene.collisionBodyOf(object)!.height, 6);

      stack.dispose();
    });

    test('honours an explicit size without reading pixels', () async {
      final image = await _decodeImage(
        Uint8List.fromList([255, 255, 255, 255]),
        1,
        1,
      );
      final stack = SpriteStack.fromImage(image, sliceCount: 1);
      final object = SpriteStackSceneObject(
        stack: stack,
        position: const SpriteStackPoint(10, 20, 0),
        scale: 3,
        collider: const SpriteStackCollider(
          size: Size(10, 6),
          height: 4,
        ),
      );
      final scene = SpriteStackScene(objects: [object]);

      final body = scene.collisionBodyOf(object)!;

      expect(body.halfWidth, 15);
      expect(body.halfDepth, 9);
      expect(body.height, 12);
      expect(body.center, const Offset(10, 20)); // centred on the prop.
      expect(body.yaw, closeTo(0, 1e-9));

      stack.dispose();
    });

    test('explicit size + offset shifts the proxy', () async {
      final image = await _decodeImage(
        Uint8List.fromList([255, 255, 255, 255]),
        1,
        1,
      );
      final stack = SpriteStack.fromImage(image, sliceCount: 1);
      final object = SpriteStackSceneObject(
        stack: stack,
        position: SpriteStackPoint.zero,
        collider: const SpriteStackCollider(
          size: Size(10, 6),
          offset: Offset(2, 1),
        ),
      );
      final scene = SpriteStackScene(objects: [object]);

      final body = scene.collisionBodyOf(object)!;

      expect(body.center, const Offset(2, 1));

      stack.dispose();
    });

    test('a prop without a collider is walk-through', () async {
      final stack = await _stackFromSlices(
        [_solidMask(width: 2, depth: 2)],
        width: 2,
        depth: 2,
      );
      final object = SpriteStackSceneObject(stack: stack);
      final scene = SpriteStackScene(objects: [object]);

      expect(scene.collisionBodyOf(object), isNull);
      expect(scene.collisionBodies(), isEmpty);

      stack.dispose();
    });

    test('an empty volume has no body', () async {
      final stack = await _stackFromSlices(
        [List<int>.filled(4, 0)],
        width: 2,
        depth: 2,
      );
      final object = SpriteStackSceneObject(
        stack: stack,
        collider: const SpriteStackCollider(),
      );
      final scene = SpriteStackScene(objects: [object]);

      expect(scene.collisionBodyOf(object), isNull);

      stack.dispose();
    });

    test('a stack without raw pixels needs an explicit size', () async {
      final image = await _decodeImage(
        Uint8List.fromList([255, 255, 255, 255]),
        1,
        1,
      );
      final stack = SpriteStack.fromImage(image, sliceCount: 1);
      final object = SpriteStackSceneObject(
        stack: stack,
        collider: const SpriteStackCollider(),
      );
      final scene = SpriteStackScene(objects: [object]);

      expect(() => scene.collisionBodyOf(object), throwsStateError);

      stack.dispose();
    });

    test('the proxy lands where the ground slice is drawn', () async {
      // A small solid block, off-centre in both axes, so a wrong mirror or a
      // wrong yaw shows up as a large offset instead of hiding in the
      // symmetry. One pixel is too thin: nearest-neighbour sampling can miss
      // it entirely at a quarter turn.
      for (final yaw in <double>[0, math.pi / 2]) {
        final stack = await _stackFromSlices(
          [
            _rectMask(
              width: 8,
              depth: 8,
              minX: 1,
              minY: 1,
              maxX: 3,
              maxY: 3,
            ),
          ],
          width: 8,
          depth: 8,
        );
        const size = Size(400, 300);
        final object = SpriteStackSceneObject(
          stack: stack,
          yaw: yaw,
          scale: 10,
          shadow: false,
          outline: false,
          pixelSnap: false,
          collider: const SpriteStackCollider(),
        );
        final scene = SpriteStackScene(
          camera: SpriteStackCamera.orbit(yaw: 0, pitch: 0.55, distance: 900),
          zoom: 2.4,
          objects: [object],
        );

        final body = scene.collisionBodyOf(object)!;
        final projection = scene.projectObject(object, size)!;
        final expected = _projectGroundOffset(scene, object, body.center, size);
        final pixels = await _render(scene, size);
        final centroid = _opaqueCentroid(pixels, size);

        // The rasterizer samples the top-left corner of each art pixel, so a
        // nearest-neighbour upscale can land up to one art pixel off. This
        // test is about the mirror and the rotation of the footprint, not
        // sub-pixel sampling: a wrong mirror or a rotation around the ground
        // anchor is off by many art pixels.
        final slack = projection.scale * 1.1;

        expect(centroid, isNotNull, reason: 'yaw $yaw drew nothing');
        expect(
          centroid!.dx,
          closeTo(expected.dx, slack),
          reason: 'yaw $yaw misses in x',
        );
        expect(
          centroid.dy,
          closeTo(expected.dy, slack),
          reason: 'yaw $yaw misses in y',
        );

        stack.dispose();
      }
    });
  });

  group('SpriteStackScene.move', () {
    late SpriteStack stack;

    setUp(() async {
      stack = await _stackFromSlices(
        [_solidMask(width: 2, depth: 2)],
        width: 2,
        depth: 2,
      );
    });

    tearDown(() => stack.dispose());

    // Footprint 20 x 20 centred on the prop, so with the prop at (0, 30) it
    // spans y 20..40.
    SpriteStackScene sceneWithWall({double height = 10}) {
      final wall = SpriteStackSceneObject(
        stack: stack,
        position: const SpriteStackPoint(0, 30, 0),
        collider: SpriteStackCollider(
          size: const Size(20, 20),
          height: height,
        ),
      );
      return SpriteStackScene(objects: [wall]);
    }

    test('an empty scene applies the whole delta', () {
      final scene = SpriteStackScene();
      final result = scene.move(
        const SpriteStackPoint(1, 2, 0),
        delta: const Offset(3, 4),
        radius: 2,
      );

      expect(result.position, const SpriteStackPoint(4, 6, 0));
      expect(result.applied, const Offset(3, 4));
      expect(result.collided, isFalse);
    });

    test('a move into a prop stops at its face', () {
      final scene = sceneWithWall();
      final result = scene.move(
        SpriteStackPoint.zero,
        delta: const Offset(0, 60),
        radius: 2,
      );

      expect(result.position.y, closeTo(18, 1e-9));
      expect(result.position.x, closeTo(0, 1e-9));
      expect(result.collided, isTrue);
      expect(result.hits, hasLength(1));
      expect(result.applied.dy, closeTo(18, 1e-9));
    });

    test('a diagonal move slides along the face', () {
      final scene = sceneWithWall();
      final result = scene.move(
        SpriteStackPoint.zero,
        // Stop short of the prop's right edge (x = 10) so this checks sliding
        // along the face, not rounding its corner.
        delta: const Offset(6, 60),
        radius: 2,
      );

      // The normal component is removed, the tangent survives.
      expect(result.position.x, closeTo(6, 1e-9));
      expect(result.position.y, closeTo(18, 1e-9));
    });

    test('a fast move does not tunnel through the prop', () {
      final scene = sceneWithWall();
      final result = scene.move(
        SpriteStackPoint.zero,
        delta: const Offset(0, 600),
        radius: 2,
      );

      expect(result.position.y, closeTo(18, 1e-9));
      expect(result.collided, isTrue);
    });

    test('open-space movement skips the body entirely', () {
      final scene = sceneWithWall();
      final result = scene.move(
        const SpriteStackPoint(-500, -500, 0),
        delta: const Offset(10, 0),
        radius: 2,
      );

      expect(result.position, const SpriteStackPoint(-490, -500, 0));
      expect(result.collided, isFalse);
    });

    test('stepHeight walks over a low prop', () {
      final scene = sceneWithWall(height: 5);
      final result = scene.move(
        SpriteStackPoint.zero,
        delta: const Offset(0, 60),
        radius: 2,
        stepHeight: 10,
      );

      expect(result.position.y, closeTo(60, 1e-9));
      expect(result.collided, isFalse);
    });

    test('ignore skips the object being moved', () {
      final player = SpriteStackSceneObject(
        stack: stack,
        collider: const SpriteStackCollider(size: Size(4, 4)),
      );
      final scene = SpriteStackScene(objects: [player]);

      expect(scene.collisionBodies(ignore: player), isEmpty);

      final result = scene.move(
        SpriteStackPoint.zero,
        delta: const Offset(0, 30),
        radius: 2,
        ignore: player,
      );
      expect(result.position.y, closeTo(30, 1e-9));
      expect(result.collided, isFalse);
    });

    test('blocks reports the same bodies move uses', () {
      final scene = sceneWithWall();

      expect(scene.blocks(const SpriteStackPoint(0, 30, 0), radius: 1), isTrue);
      expect(
        scene.blocks(const SpriteStackPoint(0, 10, 0), radius: 1),
        isFalse,
      );
    });

    test('the result keeps the requested z', () {
      final scene = sceneWithWall();
      final result = scene.move(
        const SpriteStackPoint(0, 0, 12),
        delta: const Offset(0, 60),
        radius: 2,
      );

      expect(result.position.z, 12);
    });
  });
}

/// Mask with an opaque rectangle spanning [minX]..[maxX] × [minY]..[maxY]
/// (inclusive).
List<int> _rectMask({
  required int width,
  required int depth,
  required int minX,
  required int minY,
  required int maxX,
  required int maxY,
}) {
  final mask = List<int>.filled(width * depth, 0);
  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      mask[y * width + x] = 255;
    }
  }
  return mask;
}

/// Projection of [worldPoint] on the ground plane, using the same
/// object-depth scale the renderer draws the prop with.
Offset _projectGroundOffset(
  SpriteStackScene scene,
  SpriteStackSceneObject object,
  Offset worldPoint,
  Size size,
) {
  final projection = scene.projectObject(object, size)!;
  final basis = scene.camera.basis;
  final dx = worldPoint.dx - object.position.x;
  final dy = worldPoint.dy - object.position.y;
  final pixelsPerUnit = projection.scale / object.scale;
  return projection.position +
      Offset(
        (dx * basis.right.x + dy * basis.right.y) * pixelsPerUnit,
        -(dx * basis.up.x + dy * basis.up.y) * pixelsPerUnit,
      );
}

/// Alpha-weighted centre of everything the scene drew on a transparent canvas.
Offset? _opaqueCentroid(Uint8List pixels, Size size) {
  final width = size.width.toInt();
  final height = size.height.toInt();
  var sumX = 0.0;
  var sumY = 0.0;
  var count = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (pixels[(y * width + x) * 4 + 3] == 0) continue;
      sumX += x + 0.5;
      sumY += y + 0.5;
      count++;
    }
  }
  if (count == 0) return null;
  return Offset(sumX / count, sumY / count);
}

Future<Uint8List> _render(SpriteStackScene scene, Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  scene.paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
  final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return rgba!.buffer.asUint8List();
}

/// All-opaque mask of [width] x [depth], optionally limited to a column range.
List<int> _solidMask({
  required int width,
  required int depth,
  int? minX,
  int? maxX,
}) {
  final mask = List<int>.filled(width * depth, 0);
  final from = minX ?? 0;
  final to = maxX ?? width - 1;
  for (var y = 0; y < depth; y++) {
    for (var x = from; x <= to; x++) {
      mask[y * width + x] = 255;
    }
  }
  return mask;
}

/// RGBA atlas with one frame and the given alpha per slice.
Uint8List _atlas({
  required int sliceWidth,
  required int sliceHeight,
  required List<List<int>> slices,
}) {
  final stripWidth = sliceWidth * slices.length;
  final pixels = Uint8List(stripWidth * sliceHeight * 4);
  for (var slice = 0; slice < slices.length; slice++) {
    for (var y = 0; y < sliceHeight; y++) {
      for (var x = 0; x < sliceWidth; x++) {
        final offset = (y * stripWidth + slice * sliceWidth + x) * 4;
        final alpha = slices[slice][y * sliceWidth + x];
        pixels[offset] = 255;
        pixels[offset + 1] = 255;
        pixels[offset + 2] = 255;
        pixels[offset + 3] = alpha;
      }
    }
  }
  return pixels;
}

Future<SpriteStack> _stackFromSlices(
  List<List<int>> slices, {
  required int width,
  required int depth,
}) async {
  final pixels = _atlas(
    sliceWidth: width,
    sliceHeight: depth,
    slices: slices,
  );
  final image = await _decodeImage(
    pixels,
    width * slices.length,
    depth,
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final stack = await SpriteStack.decode(
    png!.buffer.asUint8List(),
    sliceCount: slices.length,
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
