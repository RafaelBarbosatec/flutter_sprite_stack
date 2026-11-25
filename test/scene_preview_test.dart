import 'dart:io';
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
          ),
          SpriteStackSceneObject(
            stack: tree,
            position: const SpriteStackPoint(180, 130, 0),
            yaw: 0.2,
            scale: 1.1,
          ),
          SpriteStackSceneObject(
            stack: palm,
            position: const SpriteStackPoint(260, -140, 0),
            yaw: 1.2,
          ),
          SpriteStackSceneObject(
            stack: car,
            position: const SpriteStackPoint(-40, 150, 0),
            yaw: 2.4,
            scale: 0.9,
          ),
          SpriteStackSceneObject(
            stack: car,
            position: const SpriteStackPoint(-80, -170, 0),
            yaw: 0.6,
            scale: 0.9,
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

      for (final stack in stacks) {
        stack.dispose();
      }
    },
    skip: enabled ? false : 'set SCENE_PREVIEW=1 to render previews',
  );
}

Future<SpriteStack> _loadFile(String path, int sliceCount) async {
  final bytes = await File(path).readAsBytes();
  return SpriteStack.decode(bytes, sliceCount: sliceCount);
}

/// Paints the scene, writes [file] as PNG and returns the raw RGBA pixels.
Future<Uint8List> _renderPng(
  SpriteStackScene scene,
  ui.Size size,
  File file,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  scene.paint(canvas, size);
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
