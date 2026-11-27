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
      final object = SpriteStackSceneObject(stack: stack, billboard: false);

      final projection = scene.projectObject(object, const ui.Size(200, 200))!;

      expect(projection.position.dx, closeTo(100, 1e-9));
      expect(projection.position.dy, closeTo(100, 1e-9));
      expect(projection.depth, closeTo(100, 1e-9));
      expect(projection.scale, closeTo(1, 1e-9));
      // A world-aligned prop with the camera behind it shows its back: ψ = π
      // (equivalent to -π after the atan2 wrap).
      expect(math.cos(projection.yaw), closeTo(-1, 1e-9));
      expect(math.sin(projection.yaw), closeTo(0, 1e-9));

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

    test('art scale never moves the ground point', () async {
      // object.scale changes how big a prop is drawn, not where it stands. If
      // it leaks into the projection (as it once did), a prop is drawn away
      // from the grid cell it occupies, and the error changes as the camera
      // moves — the prop looks like it slides across the map by itself.
      final stack = await _solidStack(0xFFFF0000);
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(
          yaw: 0.7,
          pitch: 0.5,
          distance: 900,
        ),
        zoom: 2.4,
      );
      const size = ui.Size(800, 600);
      const position = SpriteStackPoint(180, 130, 0);

      final scales = [0.6, 0.9, 1.0, 1.4, 2.5];
      ui.Offset? anchor;
      double? unitScale;
      for (final scale in scales) {
        final object = SpriteStackSceneObject(
          stack: stack,
          position: position,
          scale: scale,
        );
        final projection = scene.projectObject(object, size)!;
        if (anchor == null) {
          anchor = projection.position;
          unitScale = projection.scale / scale;
        } else {
          expect(
            projection.position.dx,
            closeTo(anchor.dx, 1e-9),
            reason: 'scale $scale moved the prop sideways',
          );
          expect(
            projection.position.dy,
            closeTo(anchor.dy, 1e-9),
            reason: 'scale $scale moved the prop vertically',
          );
        }
        // ...but it must still change the drawn size.
        expect(projection.scale, closeTo(unitScale! * scale, 1e-9));
      }

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

    test('derives the sprite yaw from the camera basis and the prop yaw',
        () async {
      final stack = await _solidStack(0xFFFF0000);
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0.1),
      );
      final object = SpriteStackSceneObject(
        stack: stack,
        yaw: 0.3,
        billboard: false,
      );

      final projection = scene.projectObject(object, const ui.Size(200, 200))!;

      // ψ = camera.yaw - object.yaw + π, so a world-aligned prop stays aligned
      // with the projected ground grid instead of rotating against the orbit.
      expect(projection.yaw, closeTo(0.1 - 0.3 + math.pi, 1e-9));

      stack.dispose();
    });

    test('a prop at the orbit target faces away from a camera behind it',
        () async {
      final stack = await _solidStack(0xFFFF0000);
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0, pitch: 0.6, distance: 100),
      );
      final object = SpriteStackSceneObject(
        stack: stack,
        yaw: 0,
        billboard: false,
      );

      final projection = scene.projectObject(object, const ui.Size(200, 200))!;

      // Camera is south of the prop looking north; a north-facing prop shows
      // its back, which is ψ = π in the sprite's front-points-down convention
      // (equivalent to -π after the atan2 wrap).
      expect(math.cos(projection.yaw), closeTo(-1, 1e-9));
      expect(math.sin(projection.yaw), closeTo(0, 1e-9));

      stack.dispose();
    });

    test('props default to world-aligned yaw', () async {
      final stack = await _solidStack(0xFFFF0000);
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0.1),
      );
      final object = SpriteStackSceneObject(stack: stack, yaw: 0.3);

      expect(
        scene.projectObject(object, const ui.Size(200, 200))!.yaw,
        closeTo(0.1 - 0.3 + math.pi, 1e-9),
      );

      stack.dispose();
    });

    test('billboard props keep a fixed screen yaw while the camera orbits',
        () async {
      final stack = await _solidStack(0xFFFF0000);
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0.1),
      );
      final object = SpriteStackSceneObject(
        stack: stack,
        yaw: 0.3,
        billboard: true,
      );

      expect(
        scene.projectObject(object, const ui.Size(200, 200))!.yaw,
        closeTo(0.3, 1e-9),
      );

      scene.camera.yaw = 2.0;
      expect(
        scene.projectObject(object, const ui.Size(200, 200))!.yaw,
        closeTo(0.3, 1e-9),
      );

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

    test('the drawn prop stays on its point while the camera orbits', () async {
      // Regression: the sprite used to be anchored by the bottom edge of the
      // ground slice — the edge facing the camera — so orbiting swung the drawn
      // footprint around the prop's world point. Props drifted across their own
      // collision box as the camera moved.
      final stack = await _solidStack(0xFFFF0000);
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0, pitch: 0.55, distance: 600),
        zoom: 3,
        background: const ui.Color(0xFF000000),
      );
      const size = ui.Size(200, 200);
      final object = SpriteStackSceneObject(
        stack: stack,
        shadow: false,
        outline: false,
        pixelSnap: false,
        collider: const SpriteStackCollider(size: Size(4, 4)),
      );
      scene.objects.add(object);
      expect(scene.collisionBodyOf(object)!.center, Offset.zero);

      for (final yaw in <double>[0, 0.7, 1.4, 2.1, 2.8, 3.5, 4.2, 4.9, 5.6]) {
        scene.camera.yaw = yaw;
        final ground = scene.projectPoint(object.position, size)!;
        final ink = _inkBounds(await _render(scene), 200, 200);

        expect(ink, isNotNull, reason: 'yaw $yaw drew nothing');
        expect(
          ink!.center.dx,
          closeTo(ground.dx, 3),
          reason: 'the prop slid sideways at yaw $yaw',
        );
        expect(
          ink.center.dy,
          closeTo(ground.dy, 3),
          reason: 'the prop slid in depth at yaw $yaw',
        );
      }

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

  group('SpriteStackSky', () {
    // Black to white so the gradient can be checked by channel value.
    const sky = SpriteStackSky(
      top: ui.Color(0xFF000000),
      horizon: ui.Color(0xFFFFFFFF),
    );

    SpriteStackScene buildScene({
      double pitch = 0,
      double zoom = 1,
      SpriteStackSky? backdrop = sky,
      SpriteStackGround? ground,
      ui.Color? background,
    }) =>
        SpriteStackScene(
          camera: SpriteStackCamera.orbit(
            yaw: 0.4,
            pitch: pitch,
            distance: 100,
          ),
          zoom: zoom,
          sky: backdrop,
          ground: ground,
          background: background,
        );

    test('puts the horizon on the centre line at a level pitch', () async {
      final scene = buildScene();

      expect(scene.horizonY(const ui.Size(200, 200)), closeTo(100, 1e-9));
    });

    test('raises the horizon by tan(pitch) times the focal length', () async {
      // focal = zoom * distance = 200; tan(pi / 4) = 1.
      final scene = buildScene(pitch: math.pi / 4, zoom: 2);

      expect(
        scene.horizonY(const ui.Size(200, 200)),
        closeTo(-100, 1e-6),
      );
    });

    test('keeps the horizon independent of yaw', () async {
      final scene = buildScene();
      final first = scene.horizonY(const ui.Size(200, 200));
      scene.camera.yaw = 2.7;

      expect(scene.horizonY(const ui.Size(200, 200)), closeTo(first, 1e-9));
    });

    test('paints a gradient above the horizon', () async {
      final pixels = await _render(buildScene());

      final top = _red(pixels, 200, 10, 0);
      final middle = _red(pixels, 200, 10, 50);
      final low = _red(pixels, 200, 10, 99);

      // The gradient spans the visible band: 0 at the top edge, ~half-way at
      // the middle and almost the horizon colour just above the line.
      expect(top, lessThan(10));
      expect(middle, inInclusiveRange(110, 145));
      expect(low, greaterThan(240));
    });

    test('fills below the horizon with bottom, defaulting to horizon',
        () async {
      final pixels = await _render(buildScene());

      // The default `bottom` is the horizon colour.
      expect(_pixelAt(pixels, 200, 10, 150), 0xFFFFFFFF);
      expect(_pixelAt(pixels, 200, 10, 199), 0xFFFFFFFF);

      final withBottom = await _render(
        buildScene(
          backdrop: const SpriteStackSky(
            top: ui.Color(0xFF000000),
            horizon: ui.Color(0xFFFFFFFF),
            bottom: ui.Color(0xFF00FF00),
          ),
        ),
      );
      expect(_pixelAt(withBottom, 200, 10, 150), 0xFF00FF00);
    });

    test('follows the camera pitch', () async {
      // focal = 100, tan(0.5) ~ 0.5463 -> horizon at ~45.4.
      final pixels = await _render(buildScene(pitch: 0.5));

      expect(_red(pixels, 200, 10, 10), lessThan(250));
      expect(_pixelAt(pixels, 200, 10, 60), 0xFFFFFFFF);
    });

    test('pins the horizon with horizonFraction', () async {
      final pixels = await _render(
        buildScene(
          // A steep pitch would push the camera horizon off-screen; the
          // fraction keeps it at 25% of the canvas.
          pitch: 0.9,
          backdrop: const SpriteStackSky(
            horizon: ui.Color(0xFFFFFFFF),
            bottom: ui.Color(0xFF00FF00),
            horizonFraction: 0.25,
          ),
        ),
      );

      expect(_pixelAt(pixels, 200, 10, 10), isNot(0xFF00FF00));
      expect(_pixelAt(pixels, 200, 10, 60), 0xFF00FF00);
    });

    test('wins over a flat background colour', () async {
      final pixels = await _render(
        buildScene(background: const ui.Color(0xFFFF0000)),
      );

      expect(_countColor(pixels, 0xFFFF0000), 0);
      expect(_pixelAt(pixels, 200, 10, 150), 0xFFFFFFFF);
    });

    test('stays behind the ground', () async {
      final pixels = await _render(
        buildScene(
          pitch: 0.7,
          ground: const SpriteStackGround(
            extent: 400,
            step: 0,
            fill: ui.Color(0xFF203040),
          ),
        ),
      );

      expect(_pixelAt(pixels, 200, 100, 100), 0xFF203040);
      expect(_pixelAt(pixels, 200, 100, 150), 0xFF203040);
    });

    test('degrades to a flat fill when the camera looks straight down',
        () async {
      final pixels = await _render(
        buildScene(
          pitch: SpriteStackCamera.maxPitch,
          backdrop: const SpriteStackSky(
            top: ui.Color(0xFF000000),
            horizon: ui.Color(0xFFFFFFFF),
            bottom: ui.Color(0xFF00FF00),
          ),
        ),
      );

      expect(_pixelAt(pixels, 200, 10, 10), 0xFF00FF00);
    });
  });

  group('SpriteStackScene roll', () {
    // Tall and thin: 4 wide, 12 slices up.
    Future<SpriteStack> tall() async {
      return _solidStack(0xFFFF0000, sliceCount: 12);
    }

    SpriteStackSceneObject objectAt(SpriteStack stack, double yaw) =>
        SpriteStackSceneObject(
          stack: stack,
          yaw: yaw,
          scale: 2,
          outline: false,
          shadow: false,
        );

    test('turns a tall prop on its side at a quarter turn', () async {
      final stack = await tall();
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0, pitch: 0.6, distance: 300),
        zoom: 3,
        background: const ui.Color(0xFF000000),
      );
      final object = objectAt(stack, 0);
      scene.objects.add(object);

      final upright = await _render(scene);
      final uprightInk = _inkBounds(upright, 200, 200)!;
      expect(uprightInk.height, greaterThan(uprightInk.width));

      object.roll = math.pi / 2;
      final rolled = await _render(scene);
      final rolledInk = _inkBounds(rolled, 200, 200)!;
      expect(rolledInk.width, greaterThan(rolledInk.height));

      stack.dispose();
    });

    test('rolls whatever the camera angle is', () async {
      // The roll is a render effect, not a projection: a side view must tilt
      // the sprite just like a rear view does.
      final stack = await tall();
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0, pitch: 0.6, distance: 300),
        zoom: 3,
        background: const ui.Color(0xFF000000),
      );
      final object = objectAt(stack, math.pi / 2);
      scene.objects.add(object);

      final flat = _inkBounds(await _render(scene), 200, 200)!;
      object.roll = math.pi / 2;
      final banked = _inkBounds(await _render(scene), 200, 200)!;

      expect(flat.height, greaterThan(flat.width));
      expect(banked.width, greaterThan(banked.height));

      stack.dispose();
    });

    test('rollPivot moves the rotation centre', () async {
      final stack = await tall();
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0, pitch: 0.6, distance: 300),
        zoom: 3,
        background: const ui.Color(0xFF000000),
      );
      final object = objectAt(stack, 0)
        ..roll = math.pi / 2
        ..rollPivot = 0;
      scene.objects.add(object);

      final feet = _inkBounds(await _render(scene), 200, 200)!;
      object.rollPivot = 1;
      final top = _inkBounds(await _render(scene), 200, 200)!;

      expect(feet, isNot(top));
      // Pivoting at the feet keeps the body level with the ground point;
      // pivoting at the top lifts it a body height up the screen.
      expect(top.top, lessThan(feet.top));

      stack.dispose();
    });

    test('a rolled prop is not culled early near the edge', () async {
      final stack = await tall();
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(yaw: 0, pitch: 0.6, distance: 300),
        zoom: 3,
        background: const ui.Color(0xFF000000),
      );
      // Unrotated bounds end just past the right edge (x ~211 of 200). Rolling
      // left swings the body back into the canvas, so the rotated bounds must
      // keep it alive.
      final object = objectAt(stack, 0)
        ..position = const SpriteStackPoint(20.5, 0, 0)
        ..roll = -math.pi / 2;
      scene.objects.add(object);

      await _render(scene);

      expect(scene.stats.drawn, 1);

      stack.dispose();
    });
  });

  group('SpriteStackScene paint', () {
    test('counts drawn, culled, behind and tiny props', () async {
      final stack = await _solidStack(0xFFFF0000, sliceCount: 4);
      final camera = SpriteStackCamera.orbit(yaw: 0, pitch: 0.6, distance: 300);
      final basis = camera.basis;

      final scene = SpriteStackScene(
        camera: camera,
        objects: [
          SpriteStackSceneObject(stack: stack, scale: 4),
          SpriteStackSceneObject(
            stack: stack,
            position: basis.forward * 300 + basis.right * 20000,
            scale: 4,
          ),
          // The eye sits `distance` behind the target, so anything closer to
          // the camera than -distance along forward is behind it.
          SpriteStackSceneObject(
            stack: stack,
            position: basis.forward * -400,
            scale: 4,
          ),
          SpriteStackSceneObject(
            stack: stack,
            position: basis.forward * 1000000,
            scale: 4,
          ),
        ],
      );

      await _render(scene);

      expect(scene.stats.drawn, 1);
      expect(scene.stats.culled, 1);
      expect(scene.stats.behindCamera, 1);
      expect(scene.stats.tooSmall, 1);
      expect(scene.stats.total, 4);
    });

    test('minimumProjectedPixels can be disabled', () async {
      final stack = await _solidStack(0xFFFF0000, sliceCount: 4);
      final camera = SpriteStackCamera.orbit(yaw: 0, pitch: 0.6, distance: 300);
      final scene = SpriteStackScene(
        camera: camera,
        objects: [
          SpriteStackSceneObject(
            stack: stack,
            position: camera.basis.forward * 1000000,
            scale: 4,
          ),
        ],
      )..minimumProjectedPixels = 0;

      await _render(scene);

      expect(scene.stats.tooSmall, 0);
      expect(scene.stats.drawn, 1);
    });

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

/// Bounding box of every non-black pixel.
ui.Rect? _inkBounds(Uint8List pixels, int width, int height) {
  var minX = width;
  var minY = height;
  var maxX = -1;
  var maxY = -1;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * 4;
      if (pixels[offset] == 0 &&
          pixels[offset + 1] == 0 &&
          pixels[offset + 2] == 0) {
        continue;
      }
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < 0) return null;
  return ui.Rect.fromLTRB(
    minX.toDouble(),
    minY.toDouble(),
    maxX + 1.0,
    maxY + 1.0,
  );
}

int _red(Uint8List pixels, int width, int x, int y) =>
    pixels[(y * width + x) * 4];

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
