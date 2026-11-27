import 'package:flutter_sprite_stack/flutter_sprite_stack.dart';
import 'package:flutter_test/flutter_test.dart';

/// [feed] runs [frames] frames of [gap] ms and returns the last change, if any.
SpriteStackSceneDetail? feed(
  SpriteStackQualityGovernor governor,
  int frames,
  double gap, {
  bool moving = true,
  bool busy = false,
}) {
  SpriteStackSceneDetail? changed;
  for (var i = 0; i < frames; i++) {
    final next = governor.frame(gap, moving: moving, busy: busy);
    if (next != null) changed = next;
  }
  return changed;
}

void main() {
  group('SpriteStackSceneDetail', () {
    test('presets go from sharpest to cheapest', () {
      const levels = SpriteStackSceneDetail.levels;

      expect(levels, hasLength(4));
      expect(levels.first, SpriteStackSceneDetail.sharp);
      expect(levels.first.outlines, isTrue);
      expect(levels.first.shadows, isTrue);
      expect(levels.first.outlineMinimumPixels, 0);
      expect(levels.last.outlines, isFalse);
      expect(levels.last.shadows, isFalse);
      for (var i = 1; i < levels.length; i++) {
        expect(
          levels[i].minimumProjectedPixels,
          greaterThanOrEqualTo(levels[i - 1].minimumProjectedPixels),
        );
      }
    });

    test('applyDetail writes every switch into the scene', () {
      final scene = SpriteStackScene();

      scene.applyDetail(SpriteStackSceneDetail.fast);

      expect(scene.minimumProjectedPixels, 2);
      expect(scene.outlineMinimumPixels, 16);
      expect(scene.shadowMinimumPixels, 0);
      expect(scene.drawOutlines, isTrue);
      expect(scene.drawShadows, isFalse);
    });

    test('copyWith replaces only what it is given', () {
      final tuned = SpriteStackSceneDetail.balanced.copyWith(
        outlineMinimumPixels: 4,
      );

      expect(tuned.outlineMinimumPixels, 4);
      expect(
        tuned.minimumProjectedPixels,
        SpriteStackSceneDetail.balanced.minimumProjectedPixels,
      );
      expect(tuned.shadows, SpriteStackSceneDetail.balanced.shadows);
    });
  });

  group('SpriteStackQualityGovernor', () {
    SpriteStackQualityGovernor governor({
      int startLevel = 0,
      int slowWindows = 2,
      double backoffMs = 30000,
    }) =>
        SpriteStackQualityGovernor(
          startLevel: startLevel,
          windowMs: 500,
          settleMs: 0,
          fewestFrames: 5,
          slowWindows: slowWindows,
          backoffMs: backoffMs,
        );

    test('stays at the sharpest level while frames are on time', () {
      final g = governor();

      expect(g.level, 0);
      expect(feed(g, 600, 16.7), isNull);
      expect(g.level, 0);
    });

    test('steps down after two slow windows and not before', () {
      final g = governor();

      expect(feed(g, 20, 25), isNull);
      expect(g.level, 0);

      final changed = feed(g, 20, 25);
      expect(changed, SpriteStackSceneDetail.balanced);
      expect(g.level, 1);
    });

    test('a crawling window drops two levels at once, without motion', () {
      final g = governor();

      final changed = feed(g, 10, 60, moving: false);

      expect(changed, SpriteStackSceneDetail.fast);
      expect(g.level, 2);
    });

    test('waits for the picture to move before changing', () {
      final g = governor();

      feed(g, 20, 25, moving: false);
      expect(feed(g, 20, 25, moving: false), isNull);
      expect(g.waitingForMotion, isTrue);
      expect(g.level, 0);

      // The first moving frame applies the waiting change.
      final changed = g.frame(16.7, moving: true);
      expect(changed, SpriteStackSceneDetail.balanced);
      expect(g.level, 1);
      expect(g.waitingForMotion, isFalse);
    });

    test('a change waiting for motion applies after the timeout', () {
      const wait = 3000.0;
      final g = SpriteStackQualityGovernor(
        windowMs: 500,
        settleMs: 0,
        fewestFrames: 5,
        slowWindows: 2,
        waitForMotionMs: wait,
      );

      feed(g, 20, 25, moving: false);
      feed(g, 20, 25, moving: false);
      expect(g.waitingForMotion, isTrue);

      feed(g, (wait / 25).ceil(), 25, moving: false);
      expect(g.level, 1);
    });

    test('busy frames are left out of the judgement', () {
      final g = governor();

      expect(feed(g, 200, 200, busy: true), isNull);
      expect(g.level, 0);
    });

    test('climbs a level after fast windows', () {
      final g = governor(startLevel: 2);

      expect(g.level, 2);
      final changed = feed(g, 160, 16.7);
      expect(changed, SpriteStackSceneDetail.balanced);
      expect(g.level, 1);
    });

    test('a level that proves slow is undone and not retried for a while', () {
      final g = governor(startLevel: 1, backoffMs: 10000);

      // Five fast windows: try level 0.
      expect(feed(g, 160, 16.7), SpriteStackSceneDetail.sharp);
      expect(g.level, 0);

      // Slow inside the trial: back to 1 at once.
      expect(feed(g, 20, 25), SpriteStackSceneDetail.balanced);
      expect(g.level, 1);

      // Five more fast windows fit inside the backoff: no new try.
      expect(feed(g, 160, 16.7), isNull);
      expect(g.level, 1);

      // Past the backoff, another run of fast windows tries again.
      expect(feed(g, 500, 16.7), SpriteStackSceneDetail.sharp);
      expect(g.level, 0);
    });

    test('reset goes back to the start level', () {
      final g = governor();

      feed(g, 20, 25);
      feed(g, 20, 25);
      expect(g.level, 1);

      g.reset();

      expect(g.level, 0);
      expect(g.waitingForMotion, isFalse);
    });
  });
}
