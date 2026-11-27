import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';
import 'package:flutter_test/flutter_test.dart';

/// CPU benchmark for the hot paths: the software rasterizer, the painted
/// ground and a full scene paint.
///
/// It only records commands into a `PictureRecorder`, so the numbers are the
/// Dart-side cost this package owns (rasterisation, projection, culling), not
/// GPU time.
///
/// ```bash
/// PERF=1 flutter test test/performance_test.dart
/// ```
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final enabled = Platform.environment['PERF'] == '1';

  test(
    'reports the CPU cost of the hot paths',
    () async {
      final car = await _loadFile('example/sprites/car/slices.png', 15);
      final house = await _loadFile('example/sprites/house/slices.png', 29);
      final tree = await _loadFile('example/sprites/tree/slices.png', 43);
      final palm = await _loadFile('example/sprites/palmeira/slices.png', 26);

      const size = ui.Size(900, 600);
      const fade = ui.Color(0xFF16232F);

      SpriteStackScene buildScene() {
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
            bottom: fade,
          ),
          ground: const SpriteStackGround(
            extent: 700,
            step: 70,
            cellSize: 70,
            checker: [ui.Color(0xFF142430), ui.Color(0xFF1D303D)],
            fadeColor: fade,
            fadeDistance: 2400,
          ),
        );
        final props = <SpriteStack>[house, tree, palm, car];
        for (var i = 0; i < 13; i++) {
          final angle = i * 2 * math.pi / 13;
          final radius = 140 + (i % 4) * 130;
          scene.objects.add(
            SpriteStackSceneObject(
              stack: props[i % props.length],
              position: SpriteStackPoint(
                math.cos(angle) * radius,
                math.sin(angle) * radius,
                0,
              ),
              yaw: angle,
              scale: 0.9 + (i % 3) * 0.2,
            ),
          );
        }
        return scene;
      }

      final scene = buildScene();
      final groundOnly = buildScene()..objects.clear();

      // A still frame: the same pixels every time. The cache should turn the
      // whole scene into one display-list replay.
      final still = buildScene()..cacheStillFrames = false;
      final stillCached = buildScene()..cacheStillFrames = true;

      // Many tiny props: ink and shadow are what the detail tiers drop.
      SpriteStackScene tinyPropsScene({required bool tiers}) {
        final tiny = SpriteStackScene(
          camera: SpriteStackCamera.orbit(
            yaw: 0.85,
            pitch: 0.6,
            distance: 900,
          ),
          zoom: 1,
          ground: const SpriteStackGround(
            extent: 700,
            step: 70,
            cellSize: 70,
            checker: [fade, ui.Color(0xFF1D303D)],
          ),
        );
        final props = <SpriteStack>[house, tree, palm, car];
        for (var i = 0; i < 60; i++) {
          final angle = i * 2 * math.pi / 60;
          tiny.objects.add(
            SpriteStackSceneObject(
              stack: props[i % props.length],
              position: SpriteStackPoint(
                math.cos(angle) * 320,
                math.sin(angle) * 320,
                0,
              ),
              yaw: angle,
              scale: 0.22,
            ),
          );
        }
        if (tiers) {
          tiny
            ..outlineMinimumPixels = 30
            ..shadowMinimumPixels = 30;
        }
        return tiny;
      }

      final inkOn = tinyPropsScene(tiers: false);
      final inkOff = tinyPropsScene(tiers: true);

      // Warm up the JIT and the image cache.
      _measure(scene, size, frames: 12);
      _measure(groundOnly, size, frames: 12);
      _measureStill(still, size, frames: 12);
      _measureStill(stillCached, size, frames: 12);
      _measure(inkOn, size, frames: 12);
      _measure(inkOff, size, frames: 12);

      // Three rounds in the same process: shared CI runners vary a lot between
      // jobs, so the spread matters as much as the median.
      final full = <_Stats>[];
      final ground = <_Stats>[];
      final single = <_Stats>[];
      final stillOff = <_Stats>[];
      final stillOn = <_Stats>[];
      final tiersOff = <_Stats>[];
      final tiersOn = <_Stats>[];
      for (var round = 0; round < 3; round++) {
        full.add(_measure(scene, size, frames: 40));
        ground.add(_measure(groundOnly, size, frames: 40));
        single.add(_measureProp(car, size, frames: 80));
        stillOff.add(_measureStill(still, size, frames: 40));
        stillOn.add(_measureStill(stillCached, size, frames: 40));
        tiersOff.add(_measure(inkOn, size, frames: 40));
        tiersOn.add(_measure(inkOff, size, frames: 40));
      }

      _report('scene_paint_13_props_400_cells', full);
      _report('ground_400_cells', ground);
      _report('single_prop_render', single);
      _report('still_frame_13_props_no_cache', stillOff);
      _report('still_frame_13_props_cached', stillOn);
      _report('tiny_props_60_ink_and_shadow', tiersOff);
      _report('tiny_props_60_detail_tiers', tiersOn);

      // Loose sanity checks so a catastrophic regression fails the build
      // instead of only printing a slow number.
      expect(full.first.medianMs, lessThan(80),
          reason: 'scene paint is 10x slower');
      expect(ground.first.medianMs, lessThan(40),
          reason: 'ground paint regressed');
      expect(stillCached.stillFrameHits, greaterThan(0),
          reason: 'the still frame never came from the cache');
    },
    skip: !enabled,
  );
}

class _Stats {
  _Stats(this.medianMs, this.p90Ms, this.frames);

  final double medianMs;
  final double p90Ms;
  final int frames;

  String get line => 'median ${medianMs.toStringAsFixed(2)} ms · '
      'p90 ${p90Ms.toStringAsFixed(2)} ms · $frames frames';
}

_Stats _measure(SpriteStackScene scene, ui.Size size, {required int frames}) {
  final samples = <double>[];
  for (var i = 0; i < frames; i++) {
    scene.camera.yaw += 0.01;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final watch = Stopwatch()..start();
    scene.paint(canvas, size);
    watch.stop();
    recorder.endRecording().dispose();
    samples.add(watch.elapsedMicroseconds / 1000);
  }
  return _stats(samples);
}

/// Paints the same frame every time: no camera or scene change. With
/// `cacheStillFrames` on, every frame after the first replay is a display-list
/// draw.
_Stats _measureStill(
  SpriteStackScene scene,
  ui.Size size, {
  required int frames,
}) {
  final samples = <double>[];
  for (var i = 0; i < frames; i++) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final watch = Stopwatch()..start();
    scene.paint(canvas, size);
    watch.stop();
    recorder.endRecording().dispose();
    samples.add(watch.elapsedMicroseconds / 1000);
  }
  return _stats(samples);
}

_Stats _measureProp(
  SpriteStack stack,
  ui.Size size, {
  required int frames,
}) {
  final samples = <double>[];
  for (var i = 0; i < frames; i++) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final watch = Stopwatch()..start();
    stack.render(
      canvas,
      position: ui.Offset(size.width / 2, size.height * 0.7),
      yaw: i * 0.03,
      pitch: 0.9,
      scale: 4,
    );
    watch.stop();
    recorder.endRecording().dispose();
    samples.add(watch.elapsedMicroseconds / 1000);
  }
  return _stats(samples);
}

_Stats _stats(List<double> samples) {
  final sorted = List<double>.of(samples)..sort();
  final median = sorted[sorted.length ~/ 2];
  final p90 = sorted[(sorted.length * 0.9).floor().clamp(0, sorted.length - 1)];
  return _Stats(median, p90, sorted.length);
}

void _report(String label, List<_Stats> rounds) {
  final medians = rounds.map((r) => r.medianMs).toList()..sort();
  // Printed so CI logs carry the numbers, one per line and easy to grep. The
  // minimum is the least noisy estimate; the spread shows the runner's mood.
  // ignore: avoid_print
  print(
    'PERF $label: best ${medians.first.toStringAsFixed(2)} ms · '
    'median ${medians[medians.length ~/ 2].toStringAsFixed(2)} ms · '
    'worst ${medians.last.toStringAsFixed(2)} ms · '
    '${rounds.first.frames} frames x ${rounds.length} rounds',
  );
}

Future<SpriteStack> _loadFile(String path, int sliceCount) async {
  final bytes = await File(path).readAsBytes();
  return SpriteStack.decode(bytes, sliceCount: sliceCount);
}
