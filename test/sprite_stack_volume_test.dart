import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SpriteStackVolume.fromVoxels', () {
    test('keeps the occupancy buffer and index order', () {
      // 2 x 2 x 2, with only the top cell of the first column solid.
      final cells = Uint8List(8);
      cells[4] = 1; // (x: 0, y: 0, z: 1)

      final volume = SpriteStackVolume.fromVoxels(
        cells,
        width: 2,
        depth: 2,
        height: 2,
      );

      expect(volume.width, 2);
      expect(volume.depth, 2);
      expect(volume.height, 2);
      expect(volume.voxelCount, 8);
      expect(volume.solidVoxelCount, 1);
      expect(volume.isSolid(0, 0, 1), isTrue);
      expect(volume.isSolid(1, 0, 1), isFalse);
      expect(
          volume.bounds,
          const SpriteStackVolumeBounds(
            minX: 0,
            minY: 0,
            minZ: 1,
            maxX: 0,
            maxY: 0,
            maxZ: 1,
          ));
    });

    test('treats any non-zero byte as solid', () {
      final volume = SpriteStackVolume.fromVoxels(
        Uint8List.fromList([0, 2, 255, 0]),
        width: 2,
        depth: 2,
        height: 1,
      );

      expect(volume.solidVoxelCount, 2);
      expect(volume.isSolid(1, 0, 0), isTrue);
      expect(volume.isSolid(0, 1, 0), isTrue);
    });

    test('rejects non-positive dimensions', () {
      expect(
        () => SpriteStackVolume.fromVoxels(
          Uint8List(0),
          width: 0,
          depth: 1,
          height: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => SpriteStackVolume.fromVoxels(
          Uint8List(0),
          width: 1,
          depth: -1,
          height: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => SpriteStackVolume.fromVoxels(
          Uint8List(0),
          width: 1,
          depth: 1,
          height: 0,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a buffer with the wrong length', () {
      expect(
        () => SpriteStackVolume.fromVoxels(
          Uint8List(3),
          width: 2,
          depth: 2,
          height: 1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('SpriteStackVolume.fromPixels', () {
    test('reads one slice per column of the strip', () {
      // 2 x 2 slices: the ground slice is full, the top slice has one pixel.
      final pixels = _atlas(
        sliceWidth: 2,
        sliceHeight: 2,
        slices: [
          [255, 255, 255, 255],
          [255, 0, 0, 0],
        ],
      );

      final volume = SpriteStackVolume.fromPixels(
        pixels,
        sliceWidth: 2,
        sliceHeight: 2,
        sliceCount: 2,
      );

      expect(volume.width, 2);
      expect(volume.depth, 2);
      expect(volume.height, 2);
      expect(volume.solidVoxelCount, 5);
      expect(volume.isSolid(0, 0, 0), isTrue);
      expect(volume.isSolid(1, 1, 0), isTrue);
      expect(volume.isSolid(0, 0, 1), isTrue);
      expect(volume.isSolid(1, 0, 1), isFalse);
      expect(volume.bounds!.width, 2);
      expect(volume.bounds!.depth, 2);
      expect(volume.bounds!.height, 2);
    });

    test('alpha exactly at the threshold is solid', () {
      expect(_singleVoxelVolume(alpha: 127).solidVoxelCount, 0);
      expect(_singleVoxelVolume(alpha: 128).solidVoxelCount, 1);
      expect(
        _singleVoxelVolume(alpha: 200, threshold: 200).solidVoxelCount,
        1,
      );
    });

    test('rejects an alpha threshold outside 1..255', () {
      for (final threshold in [0, 256, -5]) {
        expect(
          () => _singleVoxelVolume(alpha: 255, threshold: threshold),
          throwsArgumentError,
          reason: 'threshold $threshold',
        );
      }
    });

    test('rejects a buffer smaller than the atlas', () {
      expect(
        () => SpriteStackVolume.fromPixels(
          Uint8List(4),
          sliceWidth: 2,
          sliceHeight: 2,
          sliceCount: 2,
        ),
        throwsArgumentError,
      );
    });

    test('clamps the frame to the available atlas rows', () {
      final pixels = Uint8List(2 * 4); // 1 x 1 slice, 2 stacked frames.
      pixels[3] = 0; // frame 0: empty
      pixels[7] = 255; // frame 1: solid

      SpriteStackVolume build(int frame) => SpriteStackVolume.fromPixels(
            pixels,
            sliceWidth: 1,
            sliceHeight: 1,
            sliceCount: 1,
            frameCount: 2,
            frame: frame,
          );

      expect(build(0).solidVoxelCount, 0);
      expect(build(1).solidVoxelCount, 1);
      expect(build(9).solidVoxelCount, 1);
      expect(build(-3).solidVoxelCount, 0);
    });

    test('bounds ignore the transparent padding around the prop', () {
      // 3 x 3 slice with a single solid pixel at (1, 1).
      final slice = List<int>.filled(9, 0);
      slice[1 * 3 + 1] = 255;

      final volume = SpriteStackVolume.fromPixels(
        _atlas(sliceWidth: 3, sliceHeight: 3, slices: [slice]),
        sliceWidth: 3,
        sliceHeight: 3,
        sliceCount: 1,
      );

      final bounds = volume.bounds!;
      expect(bounds.minX, 1);
      expect(bounds.maxX, 1);
      expect(bounds.minY, 1);
      expect(bounds.maxY, 1);
      expect(bounds.minZ, 0);
      expect(bounds.maxZ, 0);
      expect(bounds.width, 1);
      expect(bounds.depth, 1);
      expect(bounds.height, 1);
      expect(bounds.contains(1, 1, 0), isTrue);
      expect(bounds.contains(0, 1, 0), isFalse);
      expect(bounds.width * bounds.depth * bounds.height, 1);
    });

    test('an empty volume has no bounds', () {
      final volume = _singleVoxelVolume(alpha: 0);

      expect(volume.solidVoxelCount, 0);
      expect(volume.bounds, isNull);
      expect(volume.isSolid(0, 0, 0), isFalse);
    });

    test('coordinates outside the grid are empty', () {
      final volume = _singleVoxelVolume(alpha: 255);

      expect(volume.isSolid(-1, 0, 0), isFalse);
      expect(volume.isSolid(0, -1, 0), isFalse);
      expect(volume.isSolid(0, 0, -1), isFalse);
      expect(volume.isSolid(1, 0, 0), isFalse);
      expect(volume.isSolid(0, 1, 0), isFalse);
      expect(volume.isSolid(0, 0, 1), isFalse);
    });
  });

  group('SpriteStack.toVolume', () {
    test('reconstructs the volume from decoded slices', () async {
      // 4 x 2 strip: two 2 x 2 slices, the top one with a single pixel.
      final stack = await _stackFromSlices([
        [255, 255, 255, 255],
        [255, 0, 0, 0],
      ], sliceWidth: 2);

      final volume = stack.toVolume();

      expect(volume.width, 2);
      expect(volume.depth, 2);
      expect(volume.height, 2);
      expect(volume.solidVoxelCount, 5);

      stack.dispose();
    });

    test('selects a frame from an atlas', () async {
      // 1 x 1 slice, two stacked frames: empty then solid.
      final pixels = Uint8List(2 * 4);
      pixels[7] = 255;
      final image = await _decodeImage(pixels, 1, 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final stack = await SpriteStack.decode(
        png!.buffer.asUint8List(),
        sliceCount: 1,
        frameCount: 2,
      );
      image.dispose();

      expect(stack.toVolume(frame: 0).solidVoxelCount, 0);
      expect(stack.toVolume(frame: 1).solidVoxelCount, 1);

      stack.dispose();
    });

    test('throws when the stack has no raw pixels', () async {
      final image = await _decodeImage(
        Uint8List.fromList([255, 255, 255, 255]),
        1,
        1,
      );
      final stack = SpriteStack.fromImage(image, sliceCount: 1);

      expect(() => stack.toVolume(), throwsStateError);

      stack.dispose();
    });
  });

  group('SpriteStackMesher', () {
    const mesher = SpriteStackMesher();

    test('a single voxel becomes six quads', () {
      final mesh = mesher.build(_volumeFrom([
        [
          [1],
        ],
      ]));

      expect(mesh.quadCount, 6);
      expect(mesh.triangleCount, 12);
      expect(mesh.isEmpty, isFalse);
      expect(
          mesh.bounds,
          const SpriteStackVolumeBounds(
            minX: 0,
            minY: 0,
            minZ: 0,
            maxX: 0,
            maxY: 0,
            maxZ: 0,
          ));
      expect(mesh.quads.every((quad) => quad.area == 1), isTrue);
      expect(
        mesh.quads.map((quad) => quad.axis).toSet(),
        {0, 1, 2},
      );
      expect(
        mesh.quads.map((quad) => quad.direction).toSet(),
        {1, -1},
      );
      expect(
        mesh.quads.map((quad) => quad.plane).toSet(),
        {0, 1},
      );
    });

    test('a solid cube merges every face into one quad', () {
      final mesh = mesher.build(_volumeFrom([
        [
          [1, 1],
          [1, 1],
        ],
        [
          [1, 1],
          [1, 1],
        ],
      ]));

      expect(mesh.quadCount, 6);
      expect(mesh.triangleCount, 12);
      expect(mesh.quads.every((quad) => quad.area == 4), isTrue);
    });

    test('a flat slab keeps its thickness on every axis', () {
      // 4 x 1 x 4.
      final layer = List.generate(4, (_) => List<int>.filled(4, 1));
      final mesh = mesher.build(_volumeFrom([layer]));

      expect(mesh.quadCount, 6);
      final areas = mesh.quads.map((quad) => quad.area).toList()..sort();
      expect(areas, [4, 4, 4, 4, 16, 16]);
      expect(mesh.bounds!.width, 4);
      expect(mesh.bounds!.depth, 4);
      expect(mesh.bounds!.height, 1);
    });

    test('shared faces are interior and neighbouring faces merge', () {
      // Two voxels side by side on the x axis: 10 exposed unit faces.
      final volume = SpriteStackVolume.fromVoxels(
        Uint8List.fromList([0, 1, 1]),
        width: 3,
        depth: 1,
        height: 1,
      );

      final mesh = mesher.build(volume);

      expect(mesh.quadCount, 6);
      final areas = mesh.quads.map((quad) => quad.area).toList()..sort();
      expect(areas, [1, 1, 2, 2, 2, 2]);
      expect(
        mesh.quads.fold<int>(0, (sum, quad) => sum + quad.area),
        10,
      );
    });

    test('an empty volume has no mesh', () {
      final mesh = mesher.build(_volumeFrom([
        [
          [0, 0],
          [0, 0],
        ],
      ]));

      expect(mesh.isEmpty, isTrue);
      expect(mesh.quadCount, 0);
      expect(mesh.triangleCount, 0);
      expect(mesh.bounds, isNull);
    });

    test('corner winding matches the outward normal', () {
      final mesh = mesher.build(_volumeFrom([
        [
          [1, 1],
          [1, 1],
        ],
        [
          [1, 1],
          [1, 1],
        ],
      ]));

      for (final quad in mesh.quads) {
        final corners = quad.corners;
        expect(corners.length, 4, reason: '$quad');

        final first = corners[0];
        final second = corners[1];
        final third = corners[2];
        final edge1 = SpriteStackPoint(
          second.x - first.x,
          second.y - first.y,
          second.z - first.z,
        );
        final edge2 = SpriteStackPoint(
          third.x - second.x,
          third.y - second.y,
          third.z - second.z,
        );
        final cross = SpriteStackPoint(
          edge1.y * edge2.z - edge1.z * edge2.y,
          edge1.z * edge2.x - edge1.x * edge2.z,
          edge1.x * edge2.y - edge1.y * edge2.x,
        );
        final normal = quad.normal;

        expect(
          cross.x * normal.x + cross.y * normal.y + cross.z * normal.z,
          greaterThan(0),
          reason: 'winding is clockwise for $quad',
        );
      }
    });

    test('quads lie on their face plane and inside the bounds', () {
      final mesh = mesher.build(_volumeFrom([
        [
          [1, 1, 0],
          [1, 1, 0],
        ],
        [
          [0, 1, 1],
          [0, 1, 1],
        ],
      ]));
      final bounds = mesh.bounds!;

      for (final quad in mesh.quads) {
        for (final corner in quad.corners) {
          final alongAxis = switch (quad.axis) {
            0 => corner.x,
            1 => corner.y,
            _ => corner.z,
          };
          expect(alongAxis, quad.plane.toDouble(), reason: '$quad');
          expect(
            corner.x >= bounds.minX && corner.x <= bounds.maxX + 1,
            isTrue,
          );
          expect(
            corner.y >= bounds.minY && corner.y <= bounds.maxY + 1,
            isTrue,
          );
          expect(
            corner.z >= bounds.minZ && corner.z <= bounds.maxZ + 1,
            isTrue,
          );
        }
      }
    });

    test('meshing is deterministic', () {
      final volume = _volumeFrom([
        [
          [1, 0, 1],
          [1, 1, 0],
        ],
        [
          [0, 1, 0],
          [1, 1, 1],
        ],
      ]);

      expect(mesher.build(volume).quads, mesher.build(volume).quads);
    });

    test('keeps the source volume on the mesh', () {
      final volume = _singleVoxelVolume(alpha: 255);
      final mesh = mesher.build(volume);

      expect(mesh.volume, same(volume));
      expect(mesh.bounds, volume.bounds);
    });
  });
}

/// RGBA atlas with one frame, white pixels and the given alpha per slice.
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

SpriteStackVolume _singleVoxelVolume({
  required int alpha,
  int threshold = 128,
}) =>
    SpriteStackVolume.fromPixels(
      _atlas(
        sliceWidth: 1,
        sliceHeight: 1,
        slices: [
          [alpha],
        ],
      ),
      sliceWidth: 1,
      sliceHeight: 1,
      sliceCount: 1,
      alphaThreshold: threshold,
    );

Future<SpriteStack> _stackFromSlices(
  List<List<int>> slices, {
  required int sliceWidth,
}) async {
  final pixels = _atlas(
    sliceWidth: sliceWidth,
    sliceHeight: slices.first.length ~/ sliceWidth,
    slices: slices,
  );
  final image = await _decodeImage(
    pixels,
    sliceWidth * slices.length,
    slices.first.length ~/ sliceWidth,
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final stack = await SpriteStack.decode(
    png!.buffer.asUint8List(),
    sliceCount: slices.length,
  );
  image.dispose();
  return stack;
}

/// Builds a volume from `[z][y][x]` layers of 0/1 values.
SpriteStackVolume _volumeFrom(List<List<List<int>>> layers) {
  final height = layers.length;
  final depth = layers.first.length;
  final width = layers.first.first.length;
  final cells = Uint8List(width * depth * height);
  var index = 0;
  for (var z = 0; z < height; z++) {
    for (var y = 0; y < depth; y++) {
      for (var x = 0; x < width; x++) {
        cells[index++] = layers[z][y][x];
      }
    }
  }
  return SpriteStackVolume.fromVoxels(
    cells,
    width: width,
    depth: depth,
    height: height,
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
