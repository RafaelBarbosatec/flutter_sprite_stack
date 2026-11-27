import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the orbit-scene demo with the example assets and writes PNGs to
/// `build/scene_previews/`.
///
/// Skipped by default so `flutter test` stays fast and independent of the
/// example assets. Run it explicitly:
///
/// ```bash
/// SCENE_PREVIEW=1 flutter test test/scene_preview_test.dart
/// ```
///
/// CI runs it and uploads the PNGs as the `scene-previews` artifact.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final enabled = Platform.environment['SCENE_PREVIEW'] == '1';

  test(
    'renders the orbit scene with the example assets',
    () async {
      const size = ui.Size(900, 600);
      final output = Directory('build/scene_previews')
        ..createSync(recursive: true);

      final stacks = <SpriteStack>[
        await _loadFile('example/sprites/car/slices.png', 15),
        await _loadFile('example/sprites/house/slices.png', 29),
        await _loadFile('example/sprites/tree/slices.png', 43),
        await _loadFile('example/sprites/palmeira/slices.png', 26),
      ];
      final car = stacks[0];
      final house = stacks[1];
      final tree = stacks[2];
      final palm = stacks[3];

      const fadeColor = ui.Color(0xFF16232F);
      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(
          yaw: 0.85,
          pitch: 0.6,
          distance: 900,
          target: const SpriteStackPoint(0, 0, 30),
        ),
        zoom: 2.4,
        sky: const SpriteStackSky(
          top: ui.Color(0xFF070D16),
          horizon: ui.Color(0xFF27435E),
          bottom: fadeColor,
        ),
        ground: const SpriteStackGround(
          extent: 700,
          step: 70,
          color: ui.Color(0x332E4050),
          axisColor: ui.Color(0x664E6A84),
          cellSize: 70,
          checker: [ui.Color(0xFF142430), ui.Color(0xFF1D303D)],
          fadeColor: fadeColor,
          fadeDistance: 2400,
        ),
        objects: [
          SpriteStackSceneObject(
            stack: house,
            position: const SpriteStackPoint(-230, -40, 0),
            yaw: 0.5,
            collider: const SpriteStackCollider(padding: 2),
          ),
          SpriteStackSceneObject(
            stack: tree,
            position: const SpriteStackPoint(180, 130, 0),
            yaw: 0.2,
            scale: 1.1,
            collider: const SpriteStackCollider(padding: 2),
          ),
          SpriteStackSceneObject(
            stack: palm,
            position: const SpriteStackPoint(260, -140, 0),
            yaw: 1.2,
            collider: const SpriteStackCollider(padding: 2),
          ),
          SpriteStackSceneObject(
            stack: car,
            position: const SpriteStackPoint(-40, 150, 0),
            yaw: 2.4,
            scale: 0.9,
            collider: const SpriteStackCollider(),
          ),
          SpriteStackSceneObject(
            stack: car,
            position: const SpriteStackPoint(-80, -170, 0),
            yaw: 0.6,
            scale: 0.9,
            collider: const SpriteStackCollider(),
          ),
        ],
      );

      // Three orbit angles at the diorama pitch, plus one wide, shallow shot
      // that brings the horizon (and therefore the sky) into the frame. A
      // shorter orbit distance widens the field of view without shrinking the
      // props: the projection scale at the target is ~zoom either way.
      const shots = <(String, double, double, double)>[
        ('orbit_0.85', 0.85, 0.6, 900),
        ('orbit_2.95', 2.95, 0.6, 900),
        ('orbit_5.05', 5.05, 0.6, 900),
        ('horizon', 0.85, 0.2, 400),
      ];

      for (final (name, yaw, pitch, distance) in shots) {
        scene.camera
          ..yaw = yaw
          ..pitch = pitch
          ..distance = distance;
        final pixels = await _renderPng(
          scene,
          size,
          File('${output.path}/$name.png'),
        );

        var red = 0;
        final colors = <int>{};
        final pixelCount = size.width.toInt() * size.height.toInt();
        for (var i = 0; i < pixelCount; i++) {
          final r = pixels[i * 4];
          final g = pixels[i * 4 + 1];
          final b = pixels[i * 4 + 2];
          colors.add(
            (pixels[i * 4 + 3] << 24) | (r << 16) | (g << 8) | b,
          );
          // The car body is (208, 32, 40) in the asset palette.
          if (r > 120 && g < 80 && b < 90) red++;
        }

        // A blank or flat-gradient frame means the scene did not draw.
        expect(
          colors.length,
          greaterThan(200),
          reason: '$name produced only ${colors.length} colours',
        );
        expect(
          red,
          greaterThan(500),
          reason: '$name drew only $red car-body pixels',
        );

        if (name == 'horizon') {
          // The sky runs zenith -> horizon haze and stops at the line, where
          // the flat `bottom` fill takes over. Checked on the blue channel at
          // a column with no props in the way.
          final horizon = scene.horizonY(size);
          expect(horizon, inInclusiveRange(1, size.height - 1));
          final line = horizon.floor();
          int blue(int y) => pixels[(y * size.width.toInt() + 2) * 4 + 2];

          expect(blue(0), closeTo(0x16, 3), reason: 'missing sky at the top');
          expect(
            blue(line - 3),
            closeTo(0x5E, 6),
            reason: 'the sky does not reach the horizon colour',
          );
          expect(
            blue(line + 3),
            closeTo(0x2F, 3),
            reason: 'the fill below the horizon is not `bottom`',
          );
        } else {
          var visible = 0;
          for (final object in scene.objects) {
            final projection = scene.projectObject(object, size);
            if (projection != null && projection.isVisibleIn(size)) visible++;
          }
          expect(
            visible,
            greaterThanOrEqualTo(3),
            reason: '$name framed only $visible props',
          );
        }
      }

      // Collision overlay: the same diorama with the debug proxies drawn on
      // top, so a review can see what `paintCollisionDebug` actually draws.
      scene.camera
        ..yaw = 0.85
        ..pitch = 0.6
        ..distance = 900;
      final overlay = await _renderPng(
        scene,
        size,
        File('${output.path}/collision_overlay.png'),
        overdraw: (canvas, canvasSize) => scene.paintCollisionDebug(
          canvas,
          canvasSize,
          color: const ui.Color(0xFF00FF00),
          fillColor: const ui.Color(0x2600FF00),
          strokeWidth: 2,
        ),
      );
      var green = 0;
      for (var i = 0; i < overlay.length; i += 4) {
        if (overlay[i] == 0 &&
            overlay[i + 1] == 255 &&
            overlay[i + 2] == 0 &&
            overlay[i + 3] != 0) {
          green++;
        }
      }
      expect(
        green,
        greaterThan(400),
        reason: 'the collision overlay drew only $green outline pixels',
      );

      // Every body must land where its own projection says it does: sample the
      // midpoint of one edge of each projected quad and look for overlay ink.
      var aligned = 0;
      for (final object in scene.objects) {
        final body = scene.collisionBodyOf(object);
        if (body == null || body.isDegenerate) continue;
        final cos = math.cos(body.yaw);
        final sin = math.sin(body.yaw);
        final ax = ui.Offset(cos, sin) * body.halfWidth;
        final ay = ui.Offset(-sin, cos) * body.halfDepth;
        final corners = [
          body.center - ax - ay,
          body.center + ax - ay,
          body.center + ax + ay,
          body.center - ax + ay,
        ];
        final projected = <ui.Offset>[];
        for (final corner in corners) {
          final point = scene.projectPoint(
            SpriteStackPoint(corner.dx, corner.dy, 0),
            size,
          );
          if (point == null) break;
          projected.add(point);
        }
        if (projected.length != 4) continue;
        // Try every edge midpoint: one of them can fall off-canvas when the
        // prop sits at the frame edge, which says nothing about the overlay.
        var sampled = 0;
        var found = false;
        var lastMid = projected.first;
        for (var edge = 0; edge < 4; edge++) {
          final mid = (projected[edge] + projected[(edge + 1) % 4]) / 2;
          if (mid.dx < 2 ||
              mid.dy < 2 ||
              mid.dx > size.width - 2 ||
              mid.dy > size.height - 2) {
            continue;
          }
          sampled++;
          lastMid = mid;
          for (var dy = -2; dy <= 2 && !found; dy++) {
            for (var dx = -2; dx <= 2 && !found; dx++) {
              final x = mid.dx.round() + dx;
              final y = mid.dy.round() + dy;
              final i = (y * size.width.toInt() + x) * 4;
              if (overlay[i + 1] > 150 &&
                  overlay[i] < 100 &&
                  overlay[i + 2] < 100) {
                found = true;
              }
            }
          }
        }
        if (sampled == 0) continue;
        expect(found, isTrue,
            reason: 'no overlay ink near the edges of the body at '
                '${body.center} (last sample $lastMid)');
        aligned++;
      }
      expect(aligned, greaterThanOrEqualTo(4),
          reason: 'only $aligned collision bodies projected');

      for (final stack in stacks) {
        stack.dispose();
      }
    },
    skip: enabled ? false : 'set SCENE_PREVIEW=1 to render previews',
  );

  test(
    'renders the chase camera around the loop',
    () async {
      const size = ui.Size(900, 600);
      final output = Directory('build/scene_previews')
        ..createSync(recursive: true);

      final stacks = <SpriteStack>[
        await _loadFile('example/sprites/car/slices.png', 15),
        await _loadFile('example/sprites/tree/slices.png', 43),
        await _loadFile('example/sprites/palmeira/slices.png', 26),
      ];
      final carStack = stacks[0];

      const fadeColor = ui.Color(0xFF16232F);
      final camera = SpriteStackCamera.orbit(
        yaw: 0,
        pitch: 0.32,
        distance: 320,
        target: const SpriteStackPoint(0, 0, 30),
      );
      final scene = SpriteStackScene(
        camera: camera,
        zoom: 2.4,
        sky: const SpriteStackSky(
          top: ui.Color(0xFF070D16),
          horizon: ui.Color(0xFF27435E),
          bottom: fadeColor,
        ),
        ground: const SpriteStackGround(
          extent: 900,
          step: 90,
          cellSize: 90,
          checker: [ui.Color(0xFF142430), ui.Color(0xFF1D303D)],
          fadeColor: fadeColor,
          fadeDistance: 2400,
        ),
      );

      final car = SpriteStackSceneObject(stack: carStack);
      scene.objects.add(car);
      for (var i = 0; i < 10; i++) {
        final angle = i * 2 * math.pi / 10 + 0.4;
        scene.objects.add(
          SpriteStackSceneObject(
            stack: stacks[1 + i % 2],
            position: SpriteStackPoint(
              math.cos(angle) * 520,
              math.sin(angle) * 520,
              0,
            ),
            yaw: i * 0.7,
            scale: 1.1,
          ),
        );
      }

      final follow = SpriteStackFollowCamera(
        positionRate: 6,
        yawRate: 3,
        lookAhead: 55,
        height: 30,
      );

      const dt = 1 / 60;
      const radius = 330.0;
      const omega = 0.5;
      var angle = 0.0;
      var shot = 0;

      for (var step = 1; step <= 360; step++) {
        angle += omega * dt;
        final position = SpriteStackPoint(
          math.cos(angle) * radius,
          math.sin(angle) * radius,
          0,
        );
        final velocity = SpriteStackPoint(
          -math.sin(angle),
          math.cos(angle),
          0,
        );
        final yaw = math.atan2(velocity.y, velocity.x) - math.pi / 2;
        car
          ..position = position
          ..yaw = yaw;
        follow.update(
          camera,
          subject: position,
          yaw: yaw,
          velocity: velocity,
          dt: dt,
        );

        if (step % 120 != 0) continue;
        shot++;
        final pixels = await _renderPng(
          scene,
          size,
          File('${output.path}/chase_$shot.png'),
        );

        final projection = scene.projectObject(car, size);
        expect(projection, isNotNull, reason: 'chase_$shot lost the car');
        expect(projection!.isVisibleIn(size), isTrue);

        // The camera trails the car through the turn, so the car shows a
        // sliver of its flank instead of staying locked to one angle.
        // World-aligned props render at `camera - object + π` (the sprite
        // front is +Y), so the lag shows up as a deviation from π. The camera
        // aims `lookAhead` in front of the car, which adds up to
        // `atan(lookAhead / distance)` of offset, hence the loose tolerance.
        final lag = _wrap(yaw - camera.yaw).abs();
        expect(lag, greaterThan(0.05), reason: 'no camera lag in chase_$shot');
        expect(lag, lessThan(0.5), reason: 'camera lag is wild in chase_$shot');

        final renderLag = _wrap(projection.yaw - math.pi).abs();
        expect(
          renderLag,
          greaterThan(0.03),
          reason: 'car stays locked to the camera in chase_$shot',
        );
        expect(
          (renderLag - lag).abs(),
          lessThan(0.35),
          reason: 'render yaw does not track the camera lag in chase_$shot',
        );

        var red = 0;
        for (var i = 0; i < size.width.toInt() * size.height.toInt(); i++) {
          final r = pixels[i * 4];
          final g = pixels[i * 4 + 1];
          final b = pixels[i * 4 + 2];
          if (r > 120 && g < 80 && b < 90) red++;
        }
        expect(red, greaterThan(500), reason: 'chase_$shot drew no car');

        // Something must be behind the camera or off screen on a 360 degree
        // loop with props all around it.
        final stats = scene.stats;
        expect(stats.drawn, greaterThan(0));
        expect(stats.culled + stats.behindCamera, greaterThan(0));
      }

      expect(shot, 3);
      for (final stack in stacks) {
        stack.dispose();
      }
    },
    skip: enabled ? false : 'set SCENE_PREVIEW=1 to render previews',
  );

  test(
    'renders banked flight with the hull rolling into the turn',
    () async {
      const size = ui.Size(900, 600);
      final output = Directory('build/scene_previews')
        ..createSync(recursive: true);

      final stacks = <SpriteStack>[
        await _loadFile('example/sprites/spaceship/slices.png', 21),
        await _loadFile('example/sprites/tree/slices.png', 43),
        await _loadFile('example/sprites/palmeira/slices.png', 26),
      ];
      final shipStack = stacks[0];

      const fadeColor = ui.Color(0xFF16232F);
      final camera = SpriteStackCamera.orbit(
        yaw: 0,
        pitch: 0.22,
        distance: 300,
        target: const SpriteStackPoint(0, 0, 200),
      );
      final scene = SpriteStackScene(
        camera: camera,
        zoom: 2.4,
        sky: const SpriteStackSky(
          top: ui.Color(0xFF05090F),
          horizon: ui.Color(0xFF2C4C6B),
          bottom: fadeColor,
        ),
        ground: const SpriteStackGround(
          extent: 1000,
          step: 100,
          cellSize: 100,
          checker: [ui.Color(0xFF101B26), ui.Color(0xFF16232F)],
          fadeColor: fadeColor,
          fadeDistance: 2600,
        ),
      );

      final ship = SpriteStackSceneObject(
        stack: shipStack,
        position: const SpriteStackPoint(0, 0, 170),
        shadow: false,
        rollPivot: 0.45,
      );
      scene.objects.add(ship);
      for (var i = 0; i < 10; i++) {
        final angle = i * 2 * math.pi / 10;
        scene.objects.add(
          SpriteStackSceneObject(
            stack: stacks[1 + i % 2],
            position: SpriteStackPoint(
              math.cos(angle) * 700,
              math.sin(angle) * 700,
              0,
            ),
            yaw: i * 0.6,
            scale: 1.2,
          ),
        );
      }

      final follow = SpriteStackFollowCamera(
        positionRate: 5,
        yawRate: 2.4,
        lookAhead: 70,
        height: 30,
      );

      const dt = 1 / 60;
      const speed = 280.0;
      const radiusX = 470.0;
      const radiusY = 420.0;
      var distance = 0.0;
      var roll = 0.0;
      var lastYaw = _shipYaw(0, radiusX, radiusY);
      var shot = 0;

      double poseX(double angle) => radiusX * math.cos(angle);
      double poseY(double angle) => radiusY * math.sin(angle);

      for (var step = 1; step <= 360; step++) {
        distance += speed * dt;
        final angle = distance / 2800 * 2 * math.pi;
        final position = SpriteStackPoint(
          poseX(angle),
          poseY(angle),
          170 + math.sin(angle * 2) * 45,
        );
        final ahead = SpriteStackPoint(
          poseX(angle + 0.01),
          poseY(angle + 0.01),
          0,
        );
        final velocity = SpriteStackPoint(
          ahead.x - position.x,
          ahead.y - position.y,
          0,
        );
        final yaw = math.atan2(velocity.y, velocity.x) - math.pi / 2;

        final turnRate = _wrap(yaw - lastYaw) / dt;
        final wanted = (turnRate * 1.15).clamp(-0.85, 0.85).toDouble();
        roll += (wanted - roll) * (1 - math.exp(-4 * dt));
        lastYaw = yaw;

        ship
          ..position = position
          ..yaw = yaw
          ..roll = roll;
        follow.update(
          camera,
          subject: position,
          yaw: yaw,
          velocity: velocity,
          dt: dt,
        );

        if (step % 120 != 0) continue;
        shot++;
        await _renderPng(
          scene,
          size,
          File('${output.path}/flight_$shot.png'),
        );

        final projection = scene.projectObject(ship, size);
        expect(projection, isNotNull, reason: 'flight_$shot lost the ship');
        expect(projection!.isVisibleIn(size), isTrue);
        expect(
          roll.abs(),
          greaterThan(0.15),
          reason: 'flight_$shot is not banking',
        );
      }
      expect(shot, 3);

      // The roll has to reach pixels: an isolated render with the same bank is
      // taller than the flat one, because the hull turns diagonal.
      const magenta = ui.Color(0xFFFF00FF);
      final isolated = SpriteStackScene(
        camera: SpriteStackCamera.orbit(
          yaw: 0,
          pitch: 0.22,
          distance: 300,
        ),
        zoom: 4,
        background: magenta,
      );
      final solo = SpriteStackSceneObject(
        stack: shipStack,
        shadow: false,
        outline: false,
        rollPivot: 0.45,
      );
      isolated.objects.add(solo);

      final flatShot = await _renderPng(
        isolated,
        size,
        File('${output.path}/flight_roll_flat.png'),
      );
      solo.roll = 0.6;
      final bankedShot = await _renderPng(
        isolated,
        size,
        File('${output.path}/flight_roll_banked.png'),
      );

      final flat = _inkBounds(flatShot, size, magenta)!;
      final banked = _inkBounds(bankedShot, size, magenta)!;
      expect(flat.width, greaterThan(flat.height));
      expect(
        banked.height,
        greaterThan(flat.height * 1.3),
        reason: 'the banked hull should stand up in the frame',
      );

      for (final stack in stacks) {
        stack.dispose();
      }
    },
    skip: enabled ? false : 'set SCENE_PREVIEW=1 to render previews',
  );
}

/// Yaw of the ship at [angle], with the asset's +Y-front convention.
double _shipYaw(double angle, double radiusX, double radiusY) {
  final vx = -radiusX * math.sin(angle);
  final vy = radiusY * math.cos(angle);
  return math.atan2(vy, vx) - math.pi / 2;
}

/// Bounding box of every pixel that is not [background].
ui.Rect? _inkBounds(Uint8List pixels, ui.Size size, ui.Color background) {
  final width = size.width.toInt();
  final height = size.height.toInt();
  final br = (background.r * 255).round();
  final bg = (background.g * 255).round();
  final bb = (background.b * 255).round();
  var minX = width;
  var minY = height;
  var maxX = -1;
  var maxY = -1;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * 4;
      if (pixels[offset] == br &&
          pixels[offset + 1] == bg &&
          pixels[offset + 2] == bb) {
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

/// Wraps an angle to `-pi..pi`.
double _wrap(double angle) {
  final turn = angle % (2 * math.pi);
  return turn > math.pi ? turn - 2 * math.pi : turn;
}

Future<SpriteStack> _loadFile(String path, int sliceCount) async {
  final bytes = await File(path).readAsBytes();
  return SpriteStack.decode(bytes, sliceCount: sliceCount);
}

/// Paints the scene, writes [file] as PNG and returns the raw RGBA pixels.
Future<Uint8List> _renderPng(
  SpriteStackScene scene,
  ui.Size size,
  File file, {
  void Function(ui.Canvas canvas, ui.Size size)? overdraw,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  scene.paint(canvas, size);
  overdraw?.call(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

  await file.writeAsBytes(png!.buffer.asUint8List());

  image.dispose();
  picture.dispose();

  return rgba!.buffer.asUint8List();
}
