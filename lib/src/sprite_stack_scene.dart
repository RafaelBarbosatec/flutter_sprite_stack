import 'dart:math' as math;
import 'dart:ui';

import 'slice_cut.dart';
import 'sprite_stack.dart';
import 'sprite_stack_camera.dart';
import 'sprite_stack_collision.dart';
import 'sprite_stack_motion.dart';
import 'sprite_stack_point.dart';
import 'sprite_stack_quality.dart';
import 'sprite_stack_sky.dart';
import 'sprite_stack_volume.dart';

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
    this.collider,
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

  /// Collision proxy for this prop, or `null` for a walk-through prop.
  ///
  /// A plain `const SpriteStackCollider()` derives the footprint from the
  /// stack volume (see [SpriteStack.toVolume]); give it an explicit `size` for
  /// stacks built with `SpriteStack.fromImage`, which cannot be read back.
  ///
  /// The volume is built once and cached on this object, so a scene can query
  /// [SpriteStackScene.collisionBodies] every frame without re-scanning the
  /// atlas.
  SpriteStackCollider? collider;

  /// Manual slice decimation for this prop, or `null` to let the scene derive
  /// one from the projected scale.
  ///
  /// `1` draws every cross-section; `N` draws every `N`th one. The scene's
  /// [SpriteStackScene.sliceLod] controls the automatic choice.
  int? sliceStep;

  SpriteStackVolume? _collisionVolume;
  int? _collisionVolumeThreshold;

  /// Volume backing [collider], built on first use and reused afterwards.
  ///
  /// Throws [StateError] when the stack has no raw pixels and the collider
  /// does not provide an explicit [SpriteStackCollider.size].
  SpriteStackVolume collisionVolume(int alphaThreshold) {
    final cached = _collisionVolume;
    if (cached != null && _collisionVolumeThreshold == alphaThreshold) {
      return cached;
    }
    final volume = stack.toVolume(alphaThreshold: alphaThreshold);
    _collisionVolume = volume;
    _collisionVolumeThreshold = alphaThreshold;
    return volume;
  }
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
    this.slicesDrawn = 0,
    this.slicesTotal = 0,
  });

  /// Props that reached `SpriteStack.render`.
  final int drawn;

  /// Props whose projected bounds miss the canvas.
  final int culled;

  /// Props behind the camera's near plane.
  final int behindCamera;

  /// Props smaller than [SpriteStackScene.minimumProjectedPixels].
  final int tooSmall;

  /// Cross-sections the last frame asked the rasterizer to draw, after slice
  /// LOD. A `SliceCut` can still hide some of them.
  final int slicesDrawn;

  /// Cross-sections [drawn] props would have asked for without slice LOD.
  final int slicesTotal;

  /// How much slice LOD saved, as a fraction of [slicesTotal].
  double get sliceLodSaving =>
      slicesTotal == 0 ? 0 : 1 - slicesDrawn / slicesTotal;

  /// Every prop in the scene.
  int get total => drawn + culled + behindCamera + tooSmall;

  @override
  String toString() => 'drawn $drawn, culled $culled, behind $behindCamera, '
      'tiny $tooSmall, slices $slicesDrawn/$slicesTotal';
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

  /// Props whose projected bounds are smaller than this many pixels on **both**
  /// axes skip the 1 px outline pass.
  ///
  /// At that size the ink ring is most of the prop, so it reads as a blot and
  /// costs a full second sweep of the rasterizer's buffer. `0` keeps the
  /// outline at every size.
  double outlineMinimumPixels = 0;

  /// Props below this size on both axes skip their ground shadow. `0` keeps
  /// the shadow at every size.
  double shadowMinimumPixels = 0;

  /// Whether props draw their outline at all. Turning it off saves one buffer
  /// sweep per prop; [SpriteStackSceneObject.outline] still applies per object.
  bool drawOutlines = true;

  /// Whether props draw their ground shadow at all. [SpriteStackSceneObject.shadow]
  /// still applies per object.
  bool drawShadows = true;

  /// Whether distant props drop cross-sections they cannot show.
  ///
  /// Consecutive slices are [SpriteStackSceneObject.spacing] art pixels apart,
  /// so a prop drawn at a scale below 1 puts them closer together than a device
  /// pixel — the downscale merges them anyway. When this is on, the scene draws
  /// every `N`th slice for those props, each one still at its true height, so
  /// the silhouette does not move: only sections that were already
  /// indistinguishable stop costing a full rasterizer pass.
  ///
  /// [sliceLodPixels] sets how far apart drawn slices may land. `false`
  /// restores the full-slice render for every prop, and
  /// [SpriteStackSceneObject.sliceStep] overrides the choice per object.
  bool sliceLod = true;

  /// Maximum distance between drawn slices, in device pixels, when [sliceLod]
  /// is on. Raising it decimates harder; `1` is the conservative default.
  double sliceLodPixels = 1;

  /// Replays the last painted frame while nothing that affects it changes.
  ///
  /// A still diorama costs one `drawPicture` instead of re-rasterising every
  /// prop, which is the single biggest saving this renderer has: the software
  /// rasterizer is CPU-bound per pixel, and a still scene repeats the same
  /// pixels every frame.
  ///
  /// Off by default, because the cache cannot see two things:
  /// [SpriteStackGround.colorAt] reading state other than its arguments, and a
  /// stack image changing behind the scene's back. Turn it on when the paint is
  /// a pure function of the scene's fields, and call [clearStillCache] if you
  /// dispose a stack that a cached frame still references.
  bool cacheStillFrames = false;

  /// How many paints replayed a cached still frame. Useful in a demo or a test.
  int get stillFrameHits => _stillFrameHits;
  int _stillFrameHits = 0;

  int? _stillKey;
  Picture? _stillPicture;
  SpriteStackSceneStats _stillStats = const SpriteStackSceneStats();

  /// Drops the cached still frame and the next paint re-renders everything.
  void clearStillCache() {
    _stillPicture?.dispose();
    _stillPicture = null;
    _stillKey = null;
    _stillFrameHits = 0;
  }

  /// Applies a [SpriteStackSceneDetail]: the culling size, the outline and
  /// shadow size floors, and the two global passes.
  ///
  /// A [SpriteStackQualityGovernor] returns one of these from frame times.
  void applyDetail(SpriteStackSceneDetail detail) {
    minimumProjectedPixels = detail.minimumProjectedPixels;
    outlineMinimumPixels = detail.outlineMinimumPixels;
    shadowMinimumPixels = detail.shadowMinimumPixels;
    drawOutlines = detail.outlines;
    drawShadows = detail.shadows;
  }

  // Cached backdrop paint. The gradient only changes when the sky, the canvas
  // size or the horizon move, so an orbit keeps reusing the same shader.
  Paint? _skyPaint;
  SpriteStackSky? _skyPaintKey;
  Size? _skyPaintSize;
  double? _skyPaintHorizon;
  final Paint _skyBottomPaint = Paint();

  /// Counters from the last [paint], updated in place.
  SpriteStackSceneStats stats = const SpriteStackSceneStats();

  /// Projects [object] for [size], or returns `null` when it is behind the
  /// camera.
  SpriteStackSceneProjection? projectObject(
    SpriteStackSceneObject object,
    Size size,
  ) =>
      _projectObject(object, size, camera.basis);

  /// Projects any world point to screen, or returns `null` when it is behind
  /// the camera near plane.
  ///
  /// [projectObject] is the prop-specific version: it also derives the sprite's
  /// visible yaw and pitch and returns the projected bounds. This one is the
  /// raw camera projection, useful for debug overlays, labels and hit testing
  /// against the ground plane (`z = 0`).
  Offset? projectPoint(SpriteStackPoint point, Size size) {
    final basis = camera.basis;
    final relative = point - basis.eye;
    final depth = relative.dot(basis.forward);
    if (depth < camera.near) return null;
    final perspective = zoom * camera.distance / depth;
    return Offset(
      size.width / 2 + relative.dot(basis.right) * perspective,
      size.height / 2 - relative.dot(basis.up) * perspective,
    );
  }

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

  /// Slice decimation for [object] at its current [projection].
  ///
  /// Drawn slices stay at most [sliceLodPixels] device pixels apart: at a
  /// projected scale of `0.5` with `spacing: 1` every second cross-section
  /// would land half a pixel from the one below it, so drawing both is work
  /// the downscale throws away.
  int _autoSliceStep(
    SpriteStackSceneObject object,
    SpriteStackSceneProjection projection,
  ) {
    if (!sliceLod) return 1;
    final gap = object.spacing * projection.scale;
    if (gap <= 0) return 1;
    final step = (sliceLodPixels / gap).floor();
    return step < 1 ? 1 : step;
  }

  /// How many slices `render(sliceStep: step)` draws out of [sliceCount]:
  /// every `step`th one, plus the top slice if the stride does not land on it.
  static int _drawnSliceCount(int sliceCount, int step) {
    if (step <= 1) return sliceCount;
    if (sliceCount <= 0) return 0;
    final multiples = (sliceCount - 1) ~/ step + 1;
    return (sliceCount - 1) % step == 0 ? multiples : multiples + 1;
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

  /// Resolves [object]'s [SpriteStackSceneObject.collider] to a world-space
  /// body, or `null` when the prop is walk-through or has an empty footprint.
  ///
  /// The box faces are derived from the volume bounds, which are in source
  /// pixels, and placed with the same anchor the renderer uses: the source
  /// row `0` sits at the prop's ground point, and the slice centre sits half a
  /// slice depth forward of it, rotating in place as the prop turns. Sizes are
  /// scaled by the object's `scale`; the height also takes `spacing` into
  /// account.
  SpriteStackCollisionBody? collisionBodyOf(SpriteStackSceneObject object) {
    final collider = object.collider;
    if (collider == null) return null;
    final scale = object.scale;
    if (scale <= 0) return null;

    final double halfWidth;
    final double halfDepth;
    final double centerSide;
    final double centerForward;
    final double sliceDepth;
    final double height;

    final size = collider.size;
    if (size != null) {
      halfWidth = size.width / 2;
      halfDepth = size.height / 2;
      centerSide = collider.offset.dx;
      centerForward = collider.offset.dy;
      sliceDepth = size.height / 2;
      height = collider.height ?? double.infinity;
    } else {
      final volume = object.collisionVolume(collider.alphaThreshold);
      final bounds = volume.bounds;
      if (bounds == null) return null;
      // Centre of the tight voxel bounds in source pixels, relative to the
      // slice centre. The renderer anchors a stack at the ground slice's
      // bottom-centre and keeps that slice centre at `depth / 2` forward of
      // the anchor; the slice content rotates around it.
      final centerX = (bounds.minX + bounds.maxX + 1) / 2;
      final centerY = (bounds.minY + bounds.maxY + 1) / 2;
      halfWidth = bounds.width / 2;
      halfDepth = bounds.depth / 2;
      centerSide = volume.width / 2 - centerX;
      centerForward = centerY - volume.depth / 2;
      sliceDepth = volume.depth / 2;
      height = collider.height ?? (bounds.maxZ + 1) * object.spacing;
    }

    final padding = collider.padding;
    final boxHalfWidth = (halfWidth + padding) * scale;
    final boxHalfDepth = (halfDepth + padding) * scale;
    if (boxHalfWidth <= 0 || boxHalfDepth <= 0) return null;

    final yaw = object.yaw;
    final cosYaw = math.cos(yaw);
    final sinYaw = math.sin(yaw);
    // Prop-local to world. The slice centre stays `sliceDepth` forward of the
    // anchor as the prop turns; only the footprint rotates around it.
    final offsetX = (centerSide * cosYaw - centerForward * sinYaw) * scale;
    final offsetY =
        (sliceDepth + centerSide * sinYaw + centerForward * cosYaw) * scale;

    return SpriteStackCollisionBody(
      center: Offset(
        object.position.x + offsetX,
        object.position.y + offsetY,
      ),
      halfWidth: boxHalfWidth,
      halfDepth: boxHalfDepth,
      // The mirror above is a rotation by `yaw + pi` on the rectangle; a
      // footprint is centrally symmetric, so the same box comes out.
      yaw: yaw + math.pi,
      height: height * scale,
    );
  }

  /// Resolves every blocking prop to a world-space body.
  ///
  /// [ignore] skips one object, normally the character being moved (pass the
  /// same object to [move]). Bodies no taller than [stepHeight] are left out,
  /// so a character can step over curbs and low props.
  ///
  /// Objects without a [SpriteStackSceneObject.collider] are walk-through and
  /// cost nothing. Volume resolution is cached per object, so repeated calls
  /// only redo the projection maths.
  List<SpriteStackCollisionBody> collisionBodies({
    SpriteStackSceneObject? ignore,
    double stepHeight = 0,
  }) {
    final bodies = <SpriteStackCollisionBody>[];
    for (final object in objects) {
      if (identical(object, ignore)) continue;
      final body = collisionBodyOf(object);
      if (body == null) continue;
      if (body.height <= stepHeight) continue;
      bodies.add(body);
    }
    return bodies;
  }

  /// Draws the collision proxies over a painted frame, for debugging.
  ///
  /// Call it right after [paint], with the same canvas and size. Every prop
  /// with a [SpriteStackSceneObject.collider] is projected back to the screen
  /// as a filled, stroked quad — the same oriented box [move] resolves against,
  /// so what you see is what pushes the character. A vertical post at each
  /// corner shows the proxy height.
  ///
  /// * [ignore] leaves one object out, normally the character.
  /// * [stepHeight] paints bodies no taller than it in [steppedOverColor],
  ///   because [move] walks over them.
  /// * [circle] and [circleRadius] draw a character's ground circle as 24
  ///   projected segments; a world circle is not a circle on screen under
  ///   perspective.
  ///
  /// Debug only: it rebuilds the bodies on every call, so leave it off in
  /// release. Objects without a collider draw nothing.
  void paintCollisionDebug(
    Canvas canvas,
    Size size, {
    Color color = const Color(0xCC39FF88),
    Color fillColor = const Color(0x1F39FF88),
    Color steppedOverColor = const Color(0xCCFFB020),
    Color steppedOverFillColor = const Color(0x29FFB020),
    double strokeWidth = 1,
    SpriteStackSceneObject? ignore,
    double stepHeight = 0,
    SpriteStackPoint? circle,
    double circleRadius = 0,
    bool heightPosts = true,
  }) {
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.miter;

    for (final object in objects) {
      if (identical(object, ignore)) continue;
      final body = collisionBodyOf(object);
      if (body == null || body.isDegenerate) continue;

      final steppedOver = body.height <= stepHeight;
      final bodyColor = steppedOver ? steppedOverColor : color;
      stroke.color = bodyColor;
      fill.color = steppedOver ? steppedOverFillColor : fillColor;

      final corners = _bodyCorners(body);
      final path = Path();
      var visible = true;
      for (var i = 0; i < corners.length; i++) {
        final screen = projectPoint(
          SpriteStackPoint(corners[i].dx, corners[i].dy, 0),
          size,
        );
        if (screen == null) {
          visible = false;
          break;
        }
        if (i == 0) {
          path.moveTo(screen.dx, screen.dy);
        } else {
          path.lineTo(screen.dx, screen.dy);
        }
      }
      if (!visible) continue;
      path.close();
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);

      if (heightPosts && body.height.isFinite && body.height > 0) {
        for (final corner in corners) {
          final bottom = projectPoint(
            SpriteStackPoint(corner.dx, corner.dy, 0),
            size,
          );
          final top = projectPoint(
            SpriteStackPoint(corner.dx, corner.dy, body.height),
            size,
          );
          if (bottom != null && top != null) {
            canvas.drawLine(bottom, top, stroke);
          }
        }
      }
    }

    if (circle != null && circleRadius > 0) {
      stroke.color = color;
      const segments = 24;
      final path = Path();
      var visible = true;
      for (var i = 0; i <= segments; i++) {
        final angle = i * 2 * math.pi / segments;
        final screen = projectPoint(
          SpriteStackPoint(
            circle.x + math.cos(angle) * circleRadius,
            circle.y + math.sin(angle) * circleRadius,
            circle.z,
          ),
          size,
        );
        if (screen == null) {
          visible = false;
          break;
        }
        if (i == 0) {
          path.moveTo(screen.dx, screen.dy);
        } else {
          path.lineTo(screen.dx, screen.dy);
        }
      }
      if (visible) canvas.drawPath(path, stroke);
    }
  }

  /// The four world corners of a body's footprint, in order around the box.
  static List<Offset> _bodyCorners(SpriteStackCollisionBody body) {
    final c = math.cos(body.yaw);
    final s = math.sin(body.yaw);
    final ax = Offset(c, s) * body.halfWidth;
    final ay = Offset(-s, c) * body.halfDepth;
    return [
      body.center - ax - ay,
      body.center + ax - ay,
      body.center + ax + ay,
      body.center - ax + ay,
    ];
  }

  /// Whether a circle at [position] with [radius] overlaps any blocking prop.
  ///
  /// A cheap query for "can I stand here?"; [move] uses the same bodies.
  bool blocks(
    SpriteStackPoint position, {
    double radius = 0,
    SpriteStackSceneObject? ignore,
    double stepHeight = 0,
  }) {
    final point = Offset(position.x, position.y);
    for (final body in collisionBodies(
      ignore: ignore,
      stepHeight: stepHeight,
    )) {
      if (body.overlaps(point, radius)) return true;
    }
    return false;
  }

  /// Moves a circle from [position] by [delta], sliding along blocking props.
  ///
  /// The move is swept in substeps no longer than [radius] (or four world
  /// units when [radius] is `0`) so a fast character cannot tunnel through a
  /// prop between frames, and every substep is pushed out of contact along
  /// the contact normal. Pushing along the normal is what keeps the tangential
  /// part of the movement: walking diagonally into a wall slides along it
  /// instead of stopping dead.
  ///
  /// * [radius] is the character's ground radius in world units. `0` is a
  ///   point.
  /// * [ignore] skips one object, normally the character itself.
  /// * [stepHeight] ignores bodies no taller than this, so a curb can be
  ///   walked over.
  /// * [maxSubsteps] caps the sweep cost. The substep is always at most
  ///   [radius], so a move longer than `maxSubsteps × radius` is **truncated**
  ///   instead of taking a long step through a prop. The default covers
  ///   `32 × radius` world units per frame.
  ///
  /// The returned position keeps the requested `z`. Nothing here mutates the
  /// object: move it yourself with the result.
  ///
  /// ```dart
  /// final result = scene.move(
  ///   player.position,
  ///   delta: Offset(vx * dt, vy * dt),
  ///   radius: 12,
  ///   ignore: player,
  /// );
  /// player.position = result.position;
  /// ```
  SpriteStackMoveResult move(
    SpriteStackPoint position, {
    required Offset delta,
    double radius = 0,
    SpriteStackSceneObject? ignore,
    double stepHeight = 0,
    int maxSubsteps = 32,
  }) {
    final start = Offset(position.x, position.y);
    final end = start + delta;
    final bodies = collisionBodies(ignore: ignore, stepHeight: stepHeight);
    if (bodies.isEmpty || (delta.dx == 0 && delta.dy == 0)) {
      return SpriteStackMoveResult(
        position: SpriteStackPoint(end.dx, end.dy, position.z),
        applied: delta,
      );
    }

    // Broad phase: nothing whose world AABB misses the swept box (inflated by
    // the character radius) can be touched, so open-space movement skips the
    // substep loop entirely.
    final swept = Rect.fromLTRB(
      math.min(start.dx, end.dx) - radius,
      math.min(start.dy, end.dy) - radius,
      math.max(start.dx, end.dx) + radius,
      math.max(start.dy, end.dy) + radius,
    );
    var blockedCandidate = false;
    for (final body in bodies) {
      if (body.bounds.overlaps(swept)) {
        blockedCandidate = true;
        break;
      }
    }
    if (!blockedCandidate) {
      return SpriteStackMoveResult(
        position: SpriteStackPoint(end.dx, end.dy, position.z),
        applied: delta,
      );
    }

    final stride = radius > 1e-6 ? radius : 4.0;
    var steps = (delta.distance / stride).ceil();
    if (steps < 1) steps = 1;
    // Never lengthen a substep to fit the budget: truncate the sweep instead.
    // A substep longer than the radius could land the circle deep inside a
    // prop and resolve out through its far face, which is tunnelling.
    var sweep = delta;
    if (steps > maxSubsteps) {
      steps = maxSubsteps;
      sweep = delta / delta.distance * (maxSubsteps * stride);
    }
    final step = sweep / steps.toDouble();

    var current = start;
    final hits = <SpriteStackCollisionBody>[];
    for (var i = 0; i < steps; i++) {
      var next = current + step;
      // Settle corners where one body pushes the circle into another; more
      // passes than this tend to fight between two overlapping props.
      for (var pass = 0; pass < 4; pass++) {
        var pushed = false;
        for (final body in bodies) {
          final resolved = body.resolve(next, radius);
          if (resolved == null) continue;
          next = resolved;
          if (!hits.contains(body)) hits.add(body);
          pushed = true;
        }
        if (!pushed) break;
      }
      current = next;
    }

    return SpriteStackMoveResult(
      position: SpriteStackPoint(current.dx, current.dy, position.z),
      applied: current - start,
      hits: hits,
    );
  }

  /// Draws the backdrop, the ground grid and every visible prop, far to near.
  ///
  /// With [cacheStillFrames] on, the frame is recorded once and replayed while
  /// the scene's fields stay the same; see [stillFrameHits].
  void paint(Canvas canvas, Size size) {
    if (!cacheStillFrames) {
      _paint(canvas, size);
      return;
    }

    final key = _stillKeyFor(size);
    if (key == _stillKey) {
      var picture = _stillPicture;
      if (picture == null) {
        // The second identical frame: record it once, then replay. Recording
        // runs the rasterizer exactly like a normal paint; every frame after
        // this one is a display-list replay.
        final recorder = PictureRecorder();
        _paint(Canvas(recorder), size);
        picture = recorder.endRecording();
        _stillPicture = picture;
        _stillStats = stats;
      } else {
        stats = _stillStats;
      }
      _stillFrameHits++;
      canvas.drawPicture(picture);
      return;
    }

    _stillKey = key;
    _stillPicture?.dispose();
    _stillPicture = null;
    _paint(canvas, size);
  }

  void _paint(Canvas canvas, Size size) {
    final basis = camera.basis;
    _paintBackdrop(canvas, size);

    _paintGround(canvas, size, basis);

    final drawables = <_Drawable>[];
    var behindCamera = 0;
    var culled = 0;
    var tooSmall = 0;
    var slicesDrawn = 0;
    var slicesTotal = 0;
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
      final step = object.sliceStep ?? _autoSliceStep(object, projection);
      final count = object.stack.sliceCount;
      slicesTotal += count;
      slicesDrawn += _drawnSliceCount(count, step);
      drawables.add(_Drawable(index, object, projection, step));
    }
    stats = SpriteStackSceneStats(
      drawn: drawables.length,
      culled: culled,
      behindCamera: behindCamera,
      tooSmall: tooSmall,
      slicesDrawn: slicesDrawn,
      slicesTotal: slicesTotal,
    );
    drawables.sort((a, b) {
      final byDepth = b.projection.depth.compareTo(a.projection.depth);
      return byDepth != 0 ? byDepth : a.index.compareTo(b.index);
    });

    final outlineFloor = outlineMinimumPixels;
    final shadowFloor = shadowMinimumPixels;
    for (final item in drawables) {
      final object = item.object;
      final projection = item.projection;
      final projectedWidth = projection.bounds.width;
      final projectedHeight = projection.bounds.height;
      // Detail tiers: ink and shadow are each a full sweep of the rasterizer's
      // buffer, and below a few pixels they read as a blot rather than detail.
      final outline = drawOutlines &&
          object.outline &&
          !(outlineFloor > 0 &&
              projectedWidth < outlineFloor &&
              projectedHeight < outlineFloor);
      final shadow = drawShadows &&
          object.shadow &&
          !(shadowFloor > 0 &&
              projectedWidth < shadowFloor &&
              projectedHeight < shadowFloor);
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
        outline: outline,
        shadow: shadow,
        pixelSnap: object.pixelSnap,
        outlineColor: object.outlineColor,
        shadowColor: object.shadowColor,
        roll: object.roll,
        rollPivot: object.rollPivot,
        sliceStep: item.step,
      );
    }
  }

  /// A hash of everything [paint] reads. Equal hash means an equal frame.
  ///
  /// Written next to the paint code on purpose: a new field that affects the
  /// picture has to be added here too, or the still-frame cache would replay a
  /// stale one. The cache tests change each field in turn.
  int _stillKeyFor(Size size) {
    var hash = size.width.hashCode;
    hash = Object.hash(hash, size.height);

    final camera = this.camera;
    hash = Object.hash(
      hash,
      camera.yaw,
      camera.pitch,
      camera.distance,
      camera.near,
      camera.target.x,
      camera.target.y,
      camera.target.z,
    );
    hash = Object.hash(hash, zoom, background);
    hash = Object.hash(
      hash,
      minimumProjectedPixels,
      outlineMinimumPixels,
      shadowMinimumPixels,
      drawOutlines,
      drawShadows,
      sliceLod,
      sliceLodPixels,
    );

    final sky = this.sky;
    if (sky == null) {
      hash = Object.hash(hash, 0);
    } else {
      hash = Object.hash(
        hash,
        1,
        sky.top,
        sky.horizon,
        sky.bottom,
        sky.horizonFraction,
      );
    }

    final ground = this.ground;
    if (ground == null) {
      hash = Object.hash(hash, 0);
    } else {
      hash = Object.hash(
        hash,
        1,
        ground.extent,
        ground.step,
        ground.color,
        ground.axisColor,
        ground.strokeWidth,
        ground.cellSize,
        ground.fill,
        ground.colorAt,
        ground.fadeColor,
        ground.fadeDistance,
        Object.hashAll(ground.checker),
      );
    }

    final objects = this.objects;
    hash = Object.hash(hash, objects.length);
    for (final object in objects) {
      hash = Object.hash(
        hash,
        identityHashCode(object.stack),
        object.position.x,
        object.position.y,
        object.position.z,
        object.yaw,
        object.billboard,
        object.scale,
        object.spacing,
        object.frame,
        object.outline,
        object.shadow,
        object.pixelSnap,
        object.outlineColor,
        object.shadowColor,
        object.roll,
        object.rollPivot,
        object.sliceStep,
      );
      final motion = object.motion;
      if (motion == null) {
        hash = Object.hash(hash, 0);
      } else {
        // `time` only affects the picture when a motion reads it.
        hash = Object.hash(
          hash,
          1,
          object.time,
          motion.sway,
          motion.speed,
          motion.wave,
          motion.phase,
          motion.lean,
        );
      }
      final cut = object.cut;
      if (cut == null) {
        hash = Object.hash(hash, 0);
      } else {
        hash = Object.hash(hash, cut.top, cut.bottom);
      }
    }
    return hash;
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
      final cached = _skyPaint;
      if (cached == null ||
          _skyPaintKey != sky ||
          _skyPaintSize != size ||
          _skyPaintHorizon != horizon) {
        _skyPaint = Paint()
          ..shader = Gradient.linear(
            Offset.zero,
            Offset(0, horizon),
            <Color>[sky.top, sky.horizon],
          );
        _skyPaintKey = sky;
        _skyPaintSize = size;
        _skyPaintHorizon = horizon;
      }
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, skyBottom),
        _skyPaint!,
      );
    }
    if (skyBottom < size.height) {
      canvas.drawRect(
        Rect.fromLTRB(0, skyBottom, size.width, size.height),
        _skyBottomPaint..color = below,
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

    // Per-frame constants for the cheap reject below.
    final eye = basis.eye;
    final forward = basis.forward;
    final right = basis.right;
    final up = basis.up;
    final focal = zoom * camera.distance;
    final near = camera.near;
    final halfDiag = cellSize * 0.7071067811865476; // half the cell diagonal
    final halfWidth = size.width / 2;
    final halfHeight = size.height / 2;

    for (var iy = 0; iy < count; iy++) {
      final y0 = -ground.extent + iy * cellSize;
      final y1 = math.min(y0 + cellSize, ground.extent);
      for (var ix = 0; ix < count; ix++) {
        final x0 = -ground.extent + ix * cellSize;
        final x1 = math.min(x0 + cellSize, ground.extent);
        final centerX = (x0 + x1) / 2;
        final centerY = (y0 + y1) / 2;

        // Cells fully behind the near plane, or whose projected centre is
        // farther outside the canvas than the cell's own projected radius,
        // cannot contribute a pixel. Skipping them here avoids building and
        // clipping a polygon (and four projected points) per hidden cell —
        // most of a large floor when the camera looks at one corner.
        final rx = centerX - eye.x;
        final ry = centerY - eye.y;
        final rz = -eye.z;
        final depth = rx * forward.x + ry * forward.y + rz * forward.z;
        if (depth + halfDiag <= near) continue;
        final scale = focal / math.max(depth, near);
        final screenX =
            halfWidth + (rx * right.x + ry * right.y + rz * right.z) * scale;
        final screenY =
            halfHeight - (rx * up.x + ry * up.y + rz * up.z) * scale;
        final radius = halfDiag * focal / math.max(depth - halfDiag, near) + 2;
        if (screenX < -radius ||
            screenX > size.width + radius ||
            screenY < -radius ||
            screenY > size.height + radius) {
          continue;
        }

        var color = ground.colorAt?.call(centerX, centerY);
        color ??= ground.checker.isNotEmpty
            ? ground.checker[(ix + iy) % ground.checker.length]
            : ground.fill;
        if (color == null) continue;

        final fadeColor = ground.fadeColor;
        if (fadeColor != null && ground.fadeDistance > 0) {
          final t = (depth / ground.fadeDistance).clamp(0.0, 1.0).toDouble();
          if (t > 0) color = Color.lerp(color, fadeColor, t)!;
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
  const _Drawable(this.index, this.object, this.projection, this.step);

  final int index;
  final SpriteStackSceneObject object;
  final SpriteStackSceneProjection projection;
  final int step;
}
