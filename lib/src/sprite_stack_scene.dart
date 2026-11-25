import 'dart:math' as math;
import 'dart:ui';

import 'slice_cut.dart';
import 'sprite_stack.dart';
import 'sprite_stack_camera.dart';
import 'sprite_stack_motion.dart';
import 'sprite_stack_point.dart';
import 'sprite_stack_sky.dart';

/// Optional ground plane painted under the objects of a `SpriteStackScene`.
///
/// The plane lies on `z = 0` and spans `-extent..extent` on both horizontal
/// axes. Grid lines are clipped against the camera's near plane, so they stay
/// correct even with the camera at ground level.
///
/// The floor itself is painted cell by cell (see [fill], [checker] and
/// [colorAt]); each cell is a projected quad clipped against the near plane.
/// Cells are flat colours, not textures: a texture would need subdivision or a
/// textured rasterizer to be perspective-correct.
class SpriteStackGround {
  const SpriteStackGround({
    this.extent = 800,
    this.step = 100,
    this.color = const Color(0x3326323F),
    this.axisColor = const Color(0x663A4A5E),
    this.strokeWidth = 1,
    this.cellSize = 100,
    this.fill,
    this.checker = const <Color>[],
    this.colorAt,
    this.fadeColor,
    this.fadeDistance = 0,
  });

  /// Half the grid size, in world units.
  final double extent;

  /// Distance between lines, in world units. `0` hides the lines.
  final double step;

  /// Color of the regular lines.
  final Color color;

  /// Color of the two lines through the origin.
  final Color axisColor;

  /// Stroke width in logical pixels.
  final double strokeWidth;

  /// Side of a painted cell, in world units. Only used when the floor is
  /// painted; `0` disables cell painting.
  final double cellSize;

  /// Base color of the floor.
  ///
  /// Used when neither [checker] nor [colorAt] provide a color. Leave it `null`
  /// to keep the floor transparent.
  final Color? fill;

  /// Colors alternated by cell parity: `(ix + iy) % checker.length`.
  final List<Color> checker;

  /// Per-cell color from the world position of the cell centre.
  ///
  /// Overrides [fill] and [checker]. Called once per painted cell; useful for
  /// procedural floors (roads, grass, water, noise).
  final Color Function(double x, double y)? colorAt;

  /// Color distant cells are mixed towards. `null` disables the fade.
  final Color? fadeColor;

  /// Camera distance at which [fadeColor] is fully applied. `0` disables it.
  final double fadeDistance;

  /// Whether the floor paints any cell.
  bool get paintsFloor => fill != null || checker.isNotEmpty || colorAt != null;
}

/// A prop placed in a [SpriteStackScene].
///
/// [position] is the ground contact point in world space. [yaw] is the prop's
/// world rotation. By default the scene derives the visible sprite yaw from the
/// camera basis, so the prop stays aligned with the projected ground plane and
/// reads as a fixed object on the map while the camera moves.
///
/// Set [billboard] to `true` for a true billboard: the prop is drawn with its
/// [yaw] as a fixed screen-space angle, so it always keeps one facing on screen
/// instead of turning with the world.
///
/// [scale] is a multiplier on the projected art scale. The scene does not own
/// the [stack]; dispose it yourself when no scene uses it.
class SpriteStackSceneObject {
  SpriteStackSceneObject({
    required this.stack,
    this.position = SpriteStackPoint.zero,
    this.yaw = 0,
    this.billboard = false,
    this.scale = 1,
    this.spacing = 1,
    this.frame = 0,
    this.time = 0,
    this.motion,
    this.cut,
    this.outline = true,
    this.shadow = true,
    this.pixelSnap = true,
    this.outlineColor = const Color(0xFF181C24),
    this.shadowColor = const Color(0xFFBAC6D4),
    this.roll = 0,
    this.rollPivot = 0,
  });

  final SpriteStack stack;
  SpriteStackPoint position;
  double yaw;

  /// When `true`, [yaw] is a fixed screen-space angle and the camera orbit does
  /// not rotate the prop. The default `false` keeps the prop aligned with the
  /// projected ground plane, which is what most scenery should use.
  bool billboard;

  double scale;
  double spacing;
  int frame;
  double time;
  StackMotion? motion;
  SliceCut? cut;
  bool outline;
  bool shadow;
  bool pixelSnap;
  Color outlineColor;
  Color shadowColor;

  /// Screen-space tilt of the finished sprite, in radians, forwarded to
  /// `SpriteStack.render`.
  ///
  /// Like the pitch squash it is a drawing effect, not a re-projection: the
  /// silhouette rotates and no new side of the prop is revealed. The baked
  /// ground shadow tilts with the body, so pair a banked airborne prop with
  /// `shadow: false`.
  double roll;

  /// Pivot of [roll], as a fraction of the prop's projected body height above
  /// its ground point: `0` is the feet (it leans, grounded), `0.5` the middle,
  /// `1` the top.
  double rollPivot;
}

/// Where a [SpriteStackSceneObject] lands on screen.
class SpriteStackSceneProjection {
  const SpriteStackSceneProjection({
    required this.position,
    required this.depth,
    required this.scale,
    required this.yaw,
    required this.pitch,
    required this.bounds,
  });

  /// Ground contact point in screen coordinates, ready for
  /// `SpriteStack.render(position:)`.
  final Offset position;

  /// Camera-space depth: smaller is closer to the camera.
  final double depth;

  /// Art-pixel scale the stack is drawn with.
  final double scale;

  /// Prop yaw passed to `SpriteStack.render`: derived from the camera-to-prop
  /// vector for world-aligned props, or the fixed screen-space yaw for
  /// billboards.
  final double yaw;

  /// Prop pitch passed to `SpriteStack.render`: the camera's elevation above
  /// the prop, derived from the camera-to-prop vector.
  final double pitch;

  /// Projected bounds of the stack at [position].
  final Rect bounds;

  /// Whether these bounds touch a canvas of [size].
  bool isVisibleIn(Size size) => bounds.overlaps(Offset.zero & size);
}

/// Counters from the last [SpriteStackScene.paint].
///
/// Useful to see culling at work: a scene with 200 props spread over a big
/// world should draw only the ones on screen.
class SpriteStackSceneStats {
  const SpriteStackSceneStats({
    this.drawn = 0,
    this.culled = 0,
    this.behindCamera = 0,
    this.tooSmall = 0,
  });

  /// Props that reached `SpriteStack.render`.
  final int drawn;

  /// Props whose projected bounds miss the canvas.
  final int culled;

  /// Props behind the camera's near plane.
  final int behindCamera;

  /// Props smaller than [SpriteStackScene.minimumProjectedPixels].
  final int tooSmall;

  /// Every prop in the scene.
  int get total => drawn + culled + behindCamera + tooSmall;

  @override
  String toString() =>
      'drawn $drawn, culled $culled, behind $behindCamera, tiny $tooSmall';
}

/// A set of sprite stacks drawn with an orbiting 3D camera.
///
/// The renderer stays [SpriteStack] itself: the scene only projects each prop's
/// ground point, derives the visible yaw from the camera, scales by perspective
/// and sorts by depth. The volume and the mesh are not drawn; use them to
/// delimit props for collision and culling.
///
/// ```dart
/// final scene = SpriteStackScene(
///   camera: SpriteStackCamera.orbit(yaw: 0.6, pitch: 0.5, distance: 700),
///   zoom: 1.5,
///   sky: const SpriteStackSky(),
///   ground: const SpriteStackGround(),
///   objects: [
///     SpriteStackSceneObject(stack: car, position: SpriteStackPoint(0, 0, 0)),
///   ],
/// );
///
/// scene.paint(canvas, size);
/// ```
///
/// Sorting is per object (painter's algorithm), so two intersecting props
/// cannot resolve per pixel.
class SpriteStackScene {
  SpriteStackScene({
    SpriteStackCamera? camera,
    this.zoom = 1,
    this.background,
    this.sky,
    this.ground,
    List<SpriteStackSceneObject>? objects,
  })  : camera = camera ?? SpriteStackCamera.orbit(),
        objects = objects ?? <SpriteStackSceneObject>[];

  /// Camera used to project the scene.
  SpriteStackCamera camera;

  /// Art pixels per world unit **at the camera's target plane**. Objects
  /// closer to the camera grow above this value, objects farther shrink.
  double zoom;

  /// Flat colour painted before anything else when set. Ignored when [sky] is
  /// set.
  Color? background;

  /// Gradient backdrop painted behind the ground and the objects.
  ///
  /// Takes precedence over [background]. Its horizon follows the camera, so
  /// [horizonY] is the same line both use.
  SpriteStackSky? sky;

  /// Optional ground grid painted before the objects.
  SpriteStackGround? ground;

  /// Props in the scene. Order only breaks depth ties.
  List<SpriteStackSceneObject> objects;

  /// Props whose projected bounds are smaller than this many pixels on **both**
  /// axes are skipped: at that size they cannot add a visible pixel.
  ///
  /// `0` disables the check. Culling runs before the stack is rendered, so it
  /// saves the software rasterizer's full pass.
  double minimumProjectedPixels = 0.5;

  /// Counters from the last [paint], updated in place.
  SpriteStackSceneStats stats = const SpriteStackSceneStats();

  /// Projects [object] for [size], or returns `null` when it is behind the
  /// camera.
  SpriteStackSceneProjection? projectObject(
    SpriteStackSceneObject object,
    Size size,
  ) =>
      _projectObject(object, size, camera.basis);

  SpriteStackSceneProjection? _projectObject(
    SpriteStackSceneObject object,
    Size size,
    SpriteStackCameraBasis basis,
  ) {
    final relative = object.position - basis.eye;
    final depth = relative.dot(basis.forward);
    if (depth < camera.near) return null;

    // Pixels per world unit at this depth, from the camera's focal length
    // (`zoom` art px per world unit at `camera.distance`).
    //
    // This is deliberately *not* multiplied by [SpriteStackSceneObject.scale]:
    // that is the prop's art scale, which changes how big the sprite is drawn,
    // never where its ground point lands. Folding it in here (as this code
    // used to) moved the prop away from screen centre in proportion to its art
    // scale — a prop with `scale: 1.4` was drawn 40% further out than the grid
    // cell it actually stands on. Because that error grows and shrinks as the
    // camera moves, the prop looked like it was sliding across the map instead
    // of staying in its cell.
    final perspective = zoom * camera.distance / depth;
    final screen = Offset(
      size.width / 2 + relative.dot(basis.right) * perspective,
      size.height / 2 - relative.dot(basis.up) * perspective,
    );
    final scale = perspective * object.scale;

    // The camera direction from the prop to the eye drives the sprite's own
    // yaw/pitch. Using the global camera yaw/pitch for every prop is only
    // exact at the orbit target; deriving per-prop values keeps off-centre
    // props glued to the ground as a follow camera moves past them.
    final toCamera = basis.eye - object.position;
    final horizontal =
        math.sqrt(toCamera.x * toCamera.x + toCamera.y * toCamera.y);
    final pitch =
        horizontal < 1e-9 ? math.pi / 2 : math.atan2(toCamera.z, horizontal);

    final double yaw;
    if (object.billboard) {
      yaw = object.yaw;
    } else {
      // World-aligned: express the camera direction in the prop's local
      // horizontal axes (right = source +X, forward = source +Y) and take its
      // azimuth. At the orbit target this reduces to
      // `camera.yaw - object.yaw + π`.
      final cosY = math.cos(object.yaw);
      final sinY = math.sin(object.yaw);
      yaw = math.atan2(
        -(toCamera.x * cosY + toCamera.y * sinY),
        -toCamera.x * sinY + toCamera.y * cosY,
      );
    }

    final bounds = object.stack.boundsFor(
      yaw: yaw,
      pitch: pitch,
      scale: scale,
      spacing: object.spacing,
      cut: object.cut,
      outline: object.outline,
      shadow: object.shadow,
      roll: object.roll,
      rollPivot: object.rollPivot,
    );
    return SpriteStackSceneProjection(
      position: screen,
      depth: depth,
      scale: scale,
      yaw: yaw,
      pitch: pitch,
      bounds: bounds.rectAt(screen),
    );
  }

  /// Screen y of the horizon for [size]: the vanishing line of the ground
  /// plane at `z = 0`.
  ///
  /// The value follows the camera pitch and can fall outside `0..size.height`
  /// — a top-down-ish orbit view pushes it far above the viewport — so clamp it
  /// before using it as a canvas coordinate. Same line the [sky] gradient and
  /// the [ground] fade are built around.
  double horizonY(Size size) {
    final basis = camera.basis;
    // Every horizontal direction lies on the ground plane; project the camera's
    // horizontal heading and take the depth → infinity limit.
    final heading = SpriteStackPoint(basis.forward.x, basis.forward.y, 0);
    if (heading.length < 1e-9) return -size.height;
    final unit = heading.normalized;
    final along = unit.dot(basis.forward);
    if (along < 1e-9) return -size.height;

    final focal = zoom * camera.distance;
    return size.height / 2 - (unit.dot(basis.up) / along) * focal;
  }

  /// Draws the backdrop, the ground grid and every visible prop, far to near.
  void paint(Canvas canvas, Size size) {
    final basis = camera.basis;
    _paintBackdrop(canvas, size);

    _paintGround(canvas, size, basis);

    final drawables = <_Drawable>[];
    var behindCamera = 0;
    var culled = 0;
    var tooSmall = 0;
    final minPixels = minimumProjectedPixels;
    for (var index = 0; index < objects.length; index++) {
      final object = objects[index];
      final projection = _projectObject(object, size, basis);
      if (projection == null) {
        behindCamera++;
        continue;
      }
      if (!projection.isVisibleIn(size)) {
        culled++;
        continue;
      }
      if (minPixels > 0 &&
          projection.bounds.width < minPixels &&
          projection.bounds.height < minPixels) {
        tooSmall++;
        continue;
      }
      drawables.add(_Drawable(index, object, projection));
    }
    stats = SpriteStackSceneStats(
      drawn: drawables.length,
      culled: culled,
      behindCamera: behindCamera,
      tooSmall: tooSmall,
    );
    drawables.sort((a, b) {
      final byDepth = b.projection.depth.compareTo(a.projection.depth);
      return byDepth != 0 ? byDepth : a.index.compareTo(b.index);
    });

    for (final item in drawables) {
      final object = item.object;
      final projection = item.projection;
      object.stack.render(
        canvas,
        position: projection.position,
        yaw: projection.yaw,
        pitch: projection.pitch,
        scale: projection.scale,
        spacing: object.spacing,
        frame: object.frame,
        motion: object.motion,
        time: object.time,
        cut: object.cut,
        outline: object.outline,
        shadow: object.shadow,
        pixelSnap: object.pixelSnap,
        outlineColor: object.outlineColor,
        shadowColor: object.shadowColor,
        roll: object.roll,
        rollPivot: object.rollPivot,
      );
    }
  }

  void _paintBackdrop(Canvas canvas, Size size) {
    final sky = this.sky;
    if (sky != null) {
      _paintSky(canvas, size, sky);
      return;
    }

    final backgroundColor = background;
    if (backgroundColor != null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);
    }
  }

  void _paintSky(Canvas canvas, Size size, SpriteStackSky sky) {
    final horizon = sky.horizonFraction == null
        ? horizonY(size)
        : sky.horizonFraction! * size.height;
    final below = sky.bottom ?? sky.horizon;

    // The gradient spans the visible sky band, so a sliver of sky still reads
    // as a gradient instead of a single haze tone.
    final skyBottom = horizon.clamp(0.0, size.height).toDouble();
    if (skyBottom > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, skyBottom),
        Paint()
          ..shader = Gradient.linear(
            Offset.zero,
            Offset(0, horizon),
            <Color>[sky.top, sky.horizon],
          ),
      );
    }
    if (skyBottom < size.height) {
      canvas.drawRect(
        Rect.fromLTRB(0, skyBottom, size.width, size.height),
        Paint()..color = below,
      );
    }
  }

  void _paintGround(Canvas canvas, Size size, SpriteStackCameraBasis basis) {
    final ground = this.ground;
    if (ground == null || ground.extent <= 0) return;

    if (ground.paintsFloor) {
      _paintGroundCells(canvas, size, basis, ground);
    }
    if (ground.step <= 0) return;

    final paint = Paint()
      ..strokeWidth = ground.strokeWidth
      ..style = PaintingStyle.stroke;

    final steps = (ground.extent / ground.step).floor();
    for (var i = -steps; i <= steps; i++) {
      final offset = i * ground.step;
      paint.color = i == 0 ? ground.axisColor : ground.color;
      _drawGroundSegment(
        canvas,
        paint,
        SpriteStackPoint(offset, -ground.extent, 0),
        SpriteStackPoint(offset, ground.extent, 0),
        size,
        basis,
      );
      _drawGroundSegment(
        canvas,
        paint,
        SpriteStackPoint(-ground.extent, offset, 0),
        SpriteStackPoint(ground.extent, offset, 0),
        size,
        basis,
      );
    }
  }

  void _paintGroundCells(
    Canvas canvas,
    Size size,
    SpriteStackCameraBasis basis,
    SpriteStackGround ground,
  ) {
    final cellSize = ground.cellSize;
    if (cellSize <= 0) return;

    final count = (ground.extent * 2 / cellSize).ceil();
    final paint = Paint()
      ..style = PaintingStyle.fill
      // Adjacent cells share edges; anti-aliasing them shows hairline seams.
      ..isAntiAlias = false;

    for (var iy = 0; iy < count; iy++) {
      final y0 = -ground.extent + iy * cellSize;
      final y1 = math.min(y0 + cellSize, ground.extent);
      for (var ix = 0; ix < count; ix++) {
        final x0 = -ground.extent + ix * cellSize;
        final x1 = math.min(x0 + cellSize, ground.extent);
        final centerX = (x0 + x1) / 2;
        final centerY = (y0 + y1) / 2;

        var color = ground.colorAt?.call(centerX, centerY);
        color ??= ground.checker.isNotEmpty
            ? ground.checker[(ix + iy) % ground.checker.length]
            : ground.fill;
        if (color == null) continue;

        final fadeColor = ground.fadeColor;
        if (fadeColor != null && ground.fadeDistance > 0) {
          final depth = (SpriteStackPoint(centerX, centerY, 0) - basis.eye)
              .dot(basis.forward);
          final t = (depth / ground.fadeDistance).clamp(0.0, 1.0).toDouble();
          color = Color.lerp(color, fadeColor, t)!;
        }

        paint.color = color;
        _fillGroundCell(
          canvas,
          paint,
          x0,
          y0,
          x1,
          y1,
          size,
          basis,
        );
      }
    }
  }

  void _fillGroundCell(
    Canvas canvas,
    Paint paint,
    double x0,
    double y0,
    double x1,
    double y1,
    Size size,
    SpriteStackCameraBasis basis,
  ) {
    final corners = <SpriteStackPoint>[
      SpriteStackPoint(x0, y0, 0),
      SpriteStackPoint(x1, y0, 0),
      SpriteStackPoint(x1, y1, 0),
      SpriteStackPoint(x0, y1, 0),
    ];
    final clipped = _clipGroundPolygon(corners, basis);
    if (clipped.length < 3) return;

    final path = Path();
    final first = _toScreen(clipped.first, size, basis);
    path.moveTo(first.dx, first.dy);
    for (var i = 1; i < clipped.length; i++) {
      final point = _toScreen(clipped[i], size, basis);
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  /// Sutherland-Hodgman against the camera's near plane.
  List<SpriteStackPoint> _clipGroundPolygon(
    List<SpriteStackPoint> polygon,
    SpriteStackCameraBasis basis,
  ) {
    final clipped = <SpriteStackPoint>[];
    for (var i = 0; i < polygon.length; i++) {
      final current = polygon[i];
      final next = polygon[(i + 1) % polygon.length];
      final currentDepth = (current - basis.eye).dot(basis.forward);
      final nextDepth = (next - basis.eye).dot(basis.forward);
      final currentInside = currentDepth >= camera.near;
      final nextInside = nextDepth >= camera.near;

      if (currentInside) clipped.add(current);
      if (currentInside != nextInside) {
        final t = (camera.near - currentDepth) / (nextDepth - currentDepth);
        clipped.add(current + (next - current) * t);
      }
    }
    return clipped;
  }

  void _drawGroundSegment(
    Canvas canvas,
    Paint paint,
    SpriteStackPoint from,
    SpriteStackPoint to,
    Size size,
    SpriteStackCameraBasis basis,
  ) {
    var start = from;
    var end = to;
    final startDepth = (start - basis.eye).dot(basis.forward);
    final endDepth = (end - basis.eye).dot(basis.forward);
    if (startDepth < camera.near && endDepth < camera.near) return;

    if (startDepth < camera.near) {
      final t = (camera.near - startDepth) / (endDepth - startDepth);
      start = start + (end - start) * t;
    } else if (endDepth < camera.near) {
      final t = (camera.near - endDepth) / (startDepth - endDepth);
      end = end + (start - end) * t;
    }

    canvas.drawLine(
      _toScreen(start, size, basis),
      _toScreen(end, size, basis),
      paint,
    );
  }

  Offset _toScreen(
    SpriteStackPoint point,
    Size size,
    SpriteStackCameraBasis basis,
  ) {
    final relative = point - basis.eye;
    final depth = math.max(relative.dot(basis.forward), 1e-6);
    final scale = zoom * camera.distance / depth;
    return Offset(
      size.width / 2 + relative.dot(basis.right) * scale,
      size.height / 2 - relative.dot(basis.up) * scale,
    );
  }
}

class _Drawable {
  const _Drawable(this.index, this.object, this.projection);

  final int index;
  final SpriteStackSceneObject object;
  final SpriteStackSceneProjection projection;
}
