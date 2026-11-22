import 'dart:math' as math;

import 'sprite_stack.dart';

/// Plays the frames of a [SpriteStack] frame atlas.
///
/// The stack carries the frames (strips stacked vertically, frame `0` on top);
/// this class only decides **which** frame is visible at a given time. Rendering
/// cost does not change with the frame count — a 6-frame walk cycle still draws
/// the same number of slices per frame as a still prop.
///
/// ```dart
/// final torch = await SpriteStackAnimation.load(
///   'sprites/torch.png',
///   sliceCount: 18,
///   frameCount: 4,
///   frameDuration: 0.09,
/// );
///
/// // In a Flame component's update:
/// torch.update(dt);
/// canvas.draw... // stack.render(..., frame: torch.frame)
/// ```
class SpriteStackAnimation {
  SpriteStackAnimation(
    this.stack, {
    this.frameDuration = 0.1,
    this.loop = true,
    this.pingPong = false,
    this.onComplete,
    this.onFrame,
    int startFrame = 0,
  })  : assert(frameDuration > 0, 'frameDuration must be greater than 0'),
        _tick = startFrame < 0 ? 0 : startFrame;

  /// Loads a frame atlas from a Flutter asset and starts it.
  static Future<SpriteStackAnimation> load(
    String assetPath, {
    required int sliceCount,
    required int frameCount,
    double frameDuration = 0.1,
    bool loop = true,
    bool pingPong = false,
    bool autoPlay = true,
  }) async {
    final stack = await SpriteStack.load(
      assetPath,
      sliceCount: sliceCount,
      frameCount: frameCount,
    );
    return SpriteStackAnimation(
      stack,
      frameDuration: frameDuration,
      loop: loop,
      pingPong: pingPong,
    ).._playing = autoPlay;
  }

  /// The stack whose frames are played.
  final SpriteStack stack;

  /// How long each frame stays on screen, in seconds.
  double frameDuration;

  /// Whether the animation restarts after the last frame.
  ///
  /// When `false`, [update] stops on the last frame, sets [isFinished] and
  /// calls [onComplete] once.
  bool loop;

  /// Whether playback bounces (`0 → n-1 → 0`) instead of wrapping.
  bool pingPong;

  /// Called once when a non-looping animation reaches its last frame.
  void Function()? onComplete;

  /// Called after each [update] that changes the visible frame.
  ///
  /// A single [update] that skips several frames (a long `dt`) reports only the
  /// frame it lands on, not every frame in between.
  void Function(int frame)? onFrame;

  /// How long the animation has been playing, in seconds.
  double get elapsed => _elapsed;

  /// Number of frames in [stack].
  int get frameCount => stack.frameCount;

  /// Whether [update] should advance the animation.
  bool get isPlaying => _playing;

  /// Whether a non-looping animation reached its last frame.
  bool get isFinished => _finished;

  /// Index of the visible frame.
  int get frame {
    final count = frameCount;
    if (count <= 1) return 0;
    if (!pingPong) {
      return loop ? _tick % count : math.min(_tick, count - 1);
    }
    final cycle = 2 * (count - 1);
    final tick = loop ? _tick % cycle : math.min(_tick, cycle);
    return tick < count ? tick : cycle - tick;
  }

  double _elapsed = 0;
  int _tick;
  bool _playing = true;
  bool _finished = false;

  /// Last tick that keeps the animation on screen.
  int get _lastTick {
    final count = frameCount;
    if (!pingPong) return count - 1;
    return 2 * (count - 1);
  }

  /// Advances the animation by [dt] seconds.
  void update(double dt) {
    if (!_playing || _finished || frameDuration <= 0 || dt <= 0) return;

    final previous = frame;
    _elapsed += dt;
    var steps = 0;
    while (_elapsed >= frameDuration && steps++ < 240) {
      _elapsed -= frameDuration;
      if (!loop && _tick >= _lastTick) {
        _finish();
        break;
      }
      _tick++;
    }

    final current = frame;
    if (current != previous) onFrame?.call(current);
  }

  /// Starts or resumes playback.
  void play() {
    if (_finished) reset();
    _playing = true;
  }

  /// Pauses playback, keeping the current frame.
  void stop() => _playing = false;

  /// Rewinds to the first frame and pauses.
  void reset() {
    _tick = 0;
    _elapsed = 0;
    _playing = false;
    _finished = false;
  }

  void _finish() {
    _playing = false;
    _finished = true;
    onComplete?.call();
  }
}
