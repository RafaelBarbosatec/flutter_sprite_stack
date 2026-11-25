import 'dart:ui';

/// A vertical gradient backdrop painted behind a `SpriteStackScene`.
///
/// The gradient is anchored to the **horizon** — the vanishing line of the
/// ground plane at `z = 0` — so it holds still while the camera orbits and only
/// moves when the camera tilts. Above the horizon the backdrop blends from
/// [top] to [horizon]; below it, [bottom] shows through wherever the ground
/// does not cover the viewport.
///
/// A flat-coloured floor and a gradient sky read best when they meet: set the
/// ground's `fadeColor` to [bottom] (or to [horizon]) so distant cells dissolve
/// into the backdrop instead of ending on a hard edge.
///
/// ```dart
/// SpriteStackScene(
///   sky: const SpriteStackSky(
///     top: Color(0xFF07101B),
///     horizon: Color(0xFF23415C),
///     bottom: Color(0xFF0B1118),
///   ),
///   ground: const SpriteStackGround(
///     fill: Color(0xFF142430),
///     fadeColor: Color(0xFF0B1118),
///     fadeDistance: 2400,
///   ),
/// );
/// ```
///
/// With an orbit camera the horizon only enters the frame at a shallow pitch:
/// the projection is fairly telephoto, so a top-down-ish view fills the screen
/// with ground. Lower `SpriteStackCamera.pitch` to bring the sky into view.
class SpriteStackSky {
  const SpriteStackSky({
    this.top = const Color(0xFF070D17),
    this.horizon = const Color(0xFF22384F),
    this.bottom,
    this.horizonFraction,
  }) : assert(
          horizonFraction == null ||
              (horizonFraction >= 0 && horizonFraction <= 1),
          'horizonFraction must be within 0..1',
        );

  /// Colour at the top of the visible sky band.
  final Color top;

  /// Colour at the horizon line.
  final Color horizon;

  /// Colour below the horizon. Defaults to [horizon] when `null`.
  ///
  /// Only visible where the ground does not reach; matching it to the ground's
  /// `fadeColor` hides the edge of the floor.
  final Color? bottom;

  /// Pins the horizon to a fraction of the canvas height (`0` top, `1`
  /// bottom) instead of deriving it from the camera.
  ///
  /// Useful for a stylised painted backdrop that should not follow the pitch.
  final double? horizonFraction;
}
