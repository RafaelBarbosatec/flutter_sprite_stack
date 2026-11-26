import 'dart:math' as math;

/// How much detail a `SpriteStackScene` draws.
///
/// This is the package's answer to the "far away is a shape, close up is a
/// drawing" idea: instead of blurring a distant prop, stop paying for detail
/// that cannot be seen. A prop smaller than [outlineMinimumPixels] on both axes
/// drops its 1 px ink ring (at that size the ring is most of the prop), and one
/// smaller than [shadowMinimumPixels] drops its ground shadow. Both passes are
/// a full sweep of the rasterizer's buffer, so skipping them is a real saving
/// when a scene has many small props.
///
/// [minimumProjectedPixels], [outlines] and [shadows] are the global switches:
/// the first culls sub-pixel props entirely, the other two turn a whole pass
/// off for a scene in trouble.
///
/// Apply one with `SpriteStackScene.applyDetail`, or let a
/// [SpriteStackQualityGovernor] pick between [levels] from the frame times.
class SpriteStackSceneDetail {
  const SpriteStackSceneDetail({
    this.minimumProjectedPixels = 0.5,
    this.outlineMinimumPixels = 0,
    this.shadowMinimumPixels = 0,
    this.outlines = true,
    this.shadows = true,
  });

  /// Props whose projected bounds are smaller than this many pixels on **both**
  /// axes are not drawn at all. `0` disables the check.
  final double minimumProjectedPixels;

  /// Props whose projected bounds are smaller than this many pixels on **both**
  /// axes skip the outline pass. `0` keeps the outline at every size.
  final double outlineMinimumPixels;

  /// Props below this size on both axes skip the ground shadow. `0` keeps the
  /// shadow at every size.
  final double shadowMinimumPixels;

  /// Whether the scene draws outlines at all.
  final bool outlines;

  /// Whether the scene draws ground shadows at all.
  final bool shadows;

  /// Everything on, exactly as before this class existed.
  static const SpriteStackSceneDetail sharp = SpriteStackSceneDetail();

  /// Drops ink and shadow from props under ten pixels. The look is unchanged
  /// for anything the player can read; tiny scenery stops being a blot.
  static const SpriteStackSceneDetail balanced = SpriteStackSceneDetail(
    minimumProjectedPixels: 1,
    outlineMinimumPixels: 10,
    shadowMinimumPixels: 14,
  );

  /// No shadows at all; outlines only on props over sixteen pixels.
  static const SpriteStackSceneDetail fast = SpriteStackSceneDetail(
    minimumProjectedPixels: 2,
    outlineMinimumPixels: 16,
    shadows: false,
  );

  /// Flat and cheap: no ink, no shadow, props under four pixels culled.
  static const SpriteStackSceneDetail minimal = SpriteStackSceneDetail(
    minimumProjectedPixels: 4,
    outlines: false,
    shadows: false,
  );

  /// Sharpest first. The indices are what [SpriteStackQualityGovernor] moves
  /// between.
  static const List<SpriteStackSceneDetail> levels = [
    sharp,
    balanced,
    fast,
    minimal,
  ];

  /// A copy with some fields replaced, for tuning a preset.
  SpriteStackSceneDetail copyWith({
    double? minimumProjectedPixels,
    double? outlineMinimumPixels,
    double? shadowMinimumPixels,
    bool? outlines,
    bool? shadows,
  }) =>
      SpriteStackSceneDetail(
        minimumProjectedPixels:
            minimumProjectedPixels ?? this.minimumProjectedPixels,
        outlineMinimumPixels: outlineMinimumPixels ?? this.outlineMinimumPixels,
        shadowMinimumPixels: shadowMinimumPixels ?? this.shadowMinimumPixels,
        outlines: outlines ?? this.outlines,
        shadows: shadows ?? this.shadows,
      );

  @override
  String toString() => 'SpriteStackSceneDetail('
      'cull: $minimumProjectedPixels, outline: $outlineMinimumPixels, '
      'shadow: $shadowMinimumPixels, outlines: $outlines, '
      'shadows: $shadows)';

  @override
  bool operator ==(Object other) =>
      other is SpriteStackSceneDetail &&
      other.minimumProjectedPixels == minimumProjectedPixels &&
      other.outlineMinimumPixels == outlineMinimumPixels &&
      other.shadowMinimumPixels == shadowMinimumPixels &&
      other.outlines == outlines &&
      other.shadows == shadows;

  @override
  int get hashCode => Object.hash(
        minimumProjectedPixels,
        outlineMinimumPixels,
        shadowMinimumPixels,
        outlines,
        shadows,
      );
}

/// Picks a [SpriteStackSceneDetail] from the frame times a caller measures.
///
/// Feed it the gap since the previous frame once per frame; it returns a new
/// detail when the level should change, or `null` when it should stay. It is
/// deliberately conservative, in the same spirit as the adaptive quality in
/// Little City:
///
/// * it judges **windows** of frames (two seconds by default), not single
///   frames, so one hitch does not drop the picture;
/// * a slow window is one whose **median** frame is late, or where a tenth of
///   the frames overshoot — a steady 30 fps and a stuttering 60 fps are both
///   slow;
/// * it steps down after two slow windows, and only two levels at once when
///   frames are really crawling;
/// * it waits for the **picture to be moving** before changing, because a
///   change of detail is invisible while the camera moves and a pop while it
///   is still;
/// * a level it climbed to and that proved slow is not tried again for a
///   while, with the wait doubling each time, so it cannot flicker between two
///   levels;
/// * frames the page spent rebuilding (a town edit, a texture upload) are
///   ignored: they say nothing about how fast the scene draws.
///
/// The governor is pure: no clock, no Flutter bindings, no allocation per
/// frame. Pass it the gaps you already have from your ticker.
///
/// ```dart
/// final governor = SpriteStackQualityGovernor();
/// Duration last = Duration.zero;
///
/// void tick(Duration elapsed) {
///   final gap = (elapsed - last).inMicroseconds / 1000;
///   last = elapsed;
///   final detail = governor.frame(gap, moving: cameraIsMoving);
///   if (detail != null) scene.applyDetail(detail);
/// }
/// ```
class SpriteStackQualityGovernor {
  SpriteStackQualityGovernor({
    this.levels = SpriteStackSceneDetail.levels,
    int startLevel = 0,
    this.windowMs = 2000,
    this.settleMs = 1500,
    this.waitForMotionMs = 3000,
    this.backoffMs = 30000,
    this.fewestFrames = 5,
    this.slowMedianMs = 21,
    this.slowWindows = 2,
    this.verySlowMedianMs = 30,
    this.crawlMedianMs = 50,
    this.longFrameMs = 34,
    this.longShare = 0.1,
    this.fastMedianMs = 17.5,
    this.fastP90Ms = 20,
    this.fastWindows = 5,
    this.trialMs = 12000,
  })  : assert(levels.isNotEmpty, 'there must be at least one level'),
        assert(startLevel >= 0 && startLevel < levels.length,
            'startLevel must be a valid index'),
        assert(fewestFrames > 0, 'fewestFrames must be positive'),
        _level = startLevel,
        _startLevel = startLevel {
    _quietUntil = settleMs;
    _nextBackoff = backoffMs;
  }

  /// The levels, sharpest first. Index 0 is the sharpest.
  final List<SpriteStackSceneDetail> levels;

  /// Milliseconds of frames judged together.
  final double windowMs;

  /// Milliseconds ignored after starting and after every level change, so
  /// shader compiles and one-off stalls do not count.
  final double settleMs;

  /// Milliseconds a change waits for the picture to move before it applies
  /// anyway.
  final double waitForMotionMs;

  /// Base wait before trying a level up again after it proved slow.
  final double backoffMs;

  /// Frames a window needs before it can be judged.
  final int fewestFrames;

  /// A median frame longer than this is slow.
  final double slowMedianMs;

  /// Windows in a row needed to step down.
  final int slowWindows;

  /// A median longer than this steps down after a single window.
  final double verySlowMedianMs;

  /// A median longer than this drops two levels at once, without waiting for
  /// motion.
  final double crawlMedianMs;

  /// A frame longer than this counts as a long frame.
  final double longFrameMs;

  /// Share of long frames that makes a window slow.
  final double longShare;

  /// A median at or under this (and a p90 under [fastP90Ms]) is fast.
  final double fastMedianMs;

  /// The 90th percentile under this is fast.
  final double fastP90Ms;

  /// Fast windows in a row needed to try one level up.
  final int fastWindows;

  /// How long after a level up a single slow window sends it back.
  final double trialMs;

  final int _startLevel;

  int _level;
  double _clock = 0;
  double _quietUntil = 0;
  double _windowStart = 0;
  final List<double> _gaps = <double>[];
  int _slowRun = 0;
  int _fastRun = 0;
  int? _pendingTo;
  double _pendingSince = 0;
  int? _trialFrom;
  double _trialUntil = 0;
  double _noUpUntil = 0;
  double _nextBackoff = 0;

  /// The current level index (0 is the sharpest).
  int get level => _level;

  /// The detail of the current level.
  SpriteStackSceneDetail get detail => levels[_level];

  /// Whether a level change is waiting for the picture to move.
  bool get waitingForMotion => _pendingTo != null;

  /// One frame. Returns the new detail when the level changes, else `null`.
  ///
  /// [gapMs] is the gap since the previous frame, in milliseconds. [moving] is
  /// whether the picture changed (camera or scene), used to apply a change
  /// where it cannot be seen. [busy] marks a frame the caller spent on its own
  /// work (a rebuild, an upload): it is left out of the judgement.
  SpriteStackSceneDetail? frame(
    double gapMs, {
    bool moving = false,
    bool busy = false,
  }) {
    if (_nextBackoff == 0) _nextBackoff = backoffMs;
    // A pause is not a slow frame: cap what one frame can add to the clock.
    _clock += math.min(gapMs, windowMs / 2);

    final pending = _pendingTo;
    if (pending != null) {
      if (moving || _clock - _pendingSince >= waitForMotionMs) {
        _pendingTo = null;
        _level = pending;
        _quietUntil = _clock + settleMs;
        _gaps.clear();
        _windowStart = _clock;
        return levels[_level];
      }
      return null;
    }

    if (_clock < _quietUntil) {
      _windowStart = _clock;
      return null;
    }
    if (busy) return null;

    _gaps.add(gapMs);
    if (_clock - _windowStart < windowMs || _gaps.length < fewestFrames) {
      return null;
    }

    final sorted = List<double>.of(_gaps)..sort();
    _gaps.clear();
    _windowStart = _clock;
    final count = sorted.length;
    final median = sorted[count >> 1];
    final p90 = sorted[math.min(count - 1, (count * 0.9).floor())];
    final longAt = math.min(longFrameMs, median * 1.6);
    var long = 0;
    for (final gap in sorted) {
      if (gap > longAt) long++;
    }
    final longRatio = long / count;
    final slow = median > slowMedianMs || longRatio >= longShare;
    final fast = !slow &&
        median <= fastMedianMs &&
        p90 <= fastP90Ms &&
        longRatio <= 0.08;

    if (slow) {
      _fastRun = 0;
      _slowRun++;

      // A level we climbed to that is slow again: back, and wait longer before
      // the next try.
      final trialFrom = _trialFrom;
      if (trialFrom != null && _clock <= _trialUntil) {
        _trialFrom = null;
        _noUpUntil = _clock + _nextBackoff;
        _nextBackoff *= 2;
        return _request(trialFrom, moving: true, now: true);
      }

      final target = math.min(
        levels.length - 1,
        _level + (median > crawlMedianMs ? 2 : 1),
      );
      if (median <= verySlowMedianMs && _slowRun < slowWindows) return null;
      if (target <= _level) return null;
      _slowRun = 0;
      return _request(target, moving: moving, now: median > crawlMedianMs);
    }

    _slowRun = 0;
    if (!fast) {
      _fastRun = 0;
      return null;
    }
    _fastRun++;
    if (_fastRun >= fastWindows && _level > 0 && _clock >= _noUpUntil) {
      _fastRun = 0;
      _trialFrom = _level;
      _trialUntil = _clock + settleMs + trialMs;
      return _request(_level - 1, moving: moving, now: false);
    }
    return null;
  }

  /// Back to [startLevel], forgetting everything measured.
  void reset() {
    _level = _startLevel;
    _clock = 0;
    _quietUntil = settleMs;
    _windowStart = 0;
    _gaps.clear();
    _slowRun = 0;
    _fastRun = 0;
    _pendingTo = null;
    _trialFrom = null;
    _trialUntil = 0;
    _noUpUntil = 0;
    _nextBackoff = backoffMs;
  }

  SpriteStackSceneDetail? _request(
    int to, {
    required bool moving,
    required bool now,
  }) {
    if (moving || now || waitForMotionMs <= 0) {
      _level = to;
      _quietUntil = _clock + settleMs;
      _gaps.clear();
      _windowStart = _clock;
      return levels[to];
    }
    _pendingTo = to;
    _pendingSince = _clock;
    return null;
  }
}
