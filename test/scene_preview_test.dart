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
      const background = ui.Color(0xFF0B1118);
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

      final scene = SpriteStackScene(
        camera: SpriteStackCamera.orbit(
          yaw: 0.85,
          pitch: 0.6,
          distance: 900,
          target: const SpriteStackPoint(0, 0, 30),
        ),
        zoom: 2.4,
        background: background,
        ground: const SpriteStackGround(
          extent: 700,
          step: 70,
          color: ui.Color(0x332E4050),
          axisColor: ui.Color(0x664E6A84),
          cellSize: 70,
          checker: [ui.Color(0xFF13202A), ui.Color(0xFF162430)],
          fadeColor: ui.Color(0xFF0B1118),
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

      for (final yaw in [0.85, 2.95, 5.05]) {
        scene.camera.yaw = yaw;
        final pixels = await _renderPng(
          scene,
          size,
          File('${output.path}/orbit_${yaw.toStringAsFixed(2)}.png'),
        );

        var painted = 0;
        final colors = <int>{};
        final pixelCount = size.width.toInt() * size.height.toInt();
        for (var i = 0; i < pixelCount; i++) {
          final rgba = (pixels[i * 4 + 3] << 24) |
              (pixels[i * 4] << 16) |
              (pixels[i * 4 + 1] << 8) |
              pixels[i * 4 + 2];
          if (rgba == 0xFF0B1118) continue;
          painted++;
          colors.add(rgba);
        }

        // A blank or single-colour frame means the scene did not draw.
        expect(
          painted,
          greaterThan(5000),
          reason: 'yaw $yaw painted only $painted pixels',
        );
        expect(
          colors.length,
          greaterThan(50),
          reason: 'yaw $yaw produced only ${colors.length} colours',
        );

        var visible = 0;
        for (final object in scene.objects) {
          final projection = scene.projectObject(object, size);
          if (projection != null && projection.isVisibleIn(size)) visible++;
        }
        expect(
          visible,
          greaterThanOrEqualTo(3),
          reason: 'yaw $yaw framed only $visible props',
        );
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
