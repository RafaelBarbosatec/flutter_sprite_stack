import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';
import 'package:flutter_sprite_stack_example/stack_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders one frame of [stack] on a stage-sized canvas, exactly like the demo,
/// and returns the bounding box of everything that was painted.
Future<Rect> _renderStage({
  required SpriteStack stack,
  required Size stage,
  required double scale,
  required double yaw,
  double pitch = SpriteStack.defaultPitch,
  double spacing = 1,
  required double? projectedHeight,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final offset = stackCenterOffset(
    stack,
    canvas: stage,
    scale: scale,
    pitch: pitch,
    spacing: spacing,
    projectedHeight: projectedHeight,
  );
  stack.render(
    canvas,
    position: Offset(stage.width / 2, stage.height) + offset,
    yaw: yaw,
    pitch: pitch,
    scale: scale,
    spacing: spacing,
  );

  final image = await recorder
      .endRecording()
      .toImage(stage.width.toInt(), stage.height.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();

  var minX = image.width, maxX = -1, minY = image.height, maxY = -1;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (bytes[(y * image.width + x) * 4 + 3] == 0) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  image.dispose();
  return Rect.fromLTRB(
    minX.toDouble(),
    minY.toDouble(),
    maxX.toDouble(),
    maxY.toDouble(),
  );
}

void main() {
  testWidgets('measured height keeps the prop centred while it spins',
      (tester) async {
    await tester.runAsync(() async {
      const stage = Size(390, 359);
      const scale = 4.2;
      const slices = 21;
      final stack = await SpriteStack.load(
        'sprites/spaceship/slices.png',
        sliceCount: slices,
      );

      final projected = await measureProjectedHeight(stack);
      // The real silhouette is smaller than the slice box, so the measurement
      // has to be used, and it must exclude the lift.
      final boxHeight = stack.heightFor() - (slices - 1);
      expect(projected, greaterThan(0));
      expect(projected, lessThan(boxHeight));

      for (final yaw in [0.0, 0.3, 0.6, 0.9, 1.2, 1.5708]) {
        final rect = await _renderStage(
          stack: stack,
          stage: stage,
          scale: scale,
          yaw: yaw,
          projectedHeight: projected,
        );
        final centreY = rect.center.dy;
        // ignore: avoid_print
        print('yaw $yaw -> rect $rect centreY ${centreY.toStringAsFixed(1)}');
        expect(
          (centreY - stage.height / 2).abs(),
          lessThan(stage.height * 0.06),
          reason: 'prop should sit in the middle of the stage',
        );
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(stage.height));
      }

      // Without the measurement the slice box is used, which is visibly
      // off-centre for stacks whose strip has padding (the cottage, the tree).
      final cottage = await SpriteStack.load(
        'sprites/house/slices.png',
        sliceCount: 29,
      );
      final offCentre = await _renderStage(
        stack: cottage,
        stage: stage,
        scale: 4.2,
        yaw: 0.6,
        projectedHeight: null,
      );
      expect(
        (offCentre.center.dy - stage.height / 2).abs(),
        greaterThan(6),
      );
      cottage.dispose();

      stack.dispose();
    });
  }, timeout: const Timeout(Duration(seconds: 60)));
}
