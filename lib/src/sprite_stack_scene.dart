import 'dart:math' as math;
import 'dart:ui';

import 'slice_cut.dart';
import 'sprite_stack.dart';
import 'sprite_stack_camera.dart';
import 'sprite_stack_motion.dart';
import 'sprite_stack_point.dart';

/// Optional ground grid painted under the objects of a `SpriteStackScene`.
///
/// The grid lies on `z = 0` and spans `-extent..extent` on both horizontal
/// axes. Lines are clipped against the camera's near plane, so the grid stays
/// correct even with the camera at ground level.
class SpriteStackGround {
  const SpriteStackGround({
    this.extent = 800,
    this.step = 100,
    this.color = const Color(0x3326323F),
    this.axisColor = const Color(0x663A4A5E),
    this.strokeWidth = 1,
  });

  /// Half the grid size, in world units.
  final double extent;

  /// Distance between lines, in world units.
  final double step;

  /// Color of the regular lines.
  final Color color;

  /// Color of the two lines through the origin.
  final Color axisColor;

  /// Stroke width in logical pixels.
  final double strokeWidth;
}

/// A prop placed in a [SpriteStackScene].
///
/// [position] is the ground contact point in world space. [yaw] is the prop's
/// rotation in world space: the camera orbit is subtracted when drawing, so a
/// prop that does not change [yaw] keeps its facing while the camera moves.
///
/// [scale] is a multiplier on the projected art scale. The scene does not own
/// the [stack]; dispose it yourself when no scene uses it.
class SpriteStackSceneObject {
  SpriteStackSceneObject({
    required this.stack,
    this.position = SpriteStackPoint.zero,
    this.yaw = 0,
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
  });

  final SpriteStack stack;
  SpriteStackPoint position;
  double yaw;
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
}

/// Where a [SpriteStackSceneObject] lands on screen.
class SpriteStackSceneProjection {
  const SpriteStackSceneProjection({
    required this.position,
    required this.depth,
    required this.scale,
    required this.yaw,
    required this.bounds,
  });

  /// Ground contact point in screen coordinates, ready for
  /// `SpriteStack.render(position:)`.
  final Offset position;

  /// Camera-space depth: smaller is closer to the camera.
  final double depth;

  /// Art-pixel scale the stack is drawn with.
  final double scale;

  /// Prop yaw relative to the camera, passed to `SpriteStack.render`.
  final double yaw;

  /// Projected bounds of the stack at [position].
  final Rect bounds;

  /// Whether these bounds touch a canvas of [size].
  bool isVisibleIn(Size size) => bounds.overlaps(Offset.zero & size);
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
    this.ground,
    List<SpriteStackSceneObject>? objects,
  })  : camera = camera ?? SpriteStackCamera.orbit(),
        objects = objects ?? <SpriteStackSceneObject>[];

  /// Camera used to project the scene.
  SpriteStackCamera camera;

  /// Art pixels per world unit **at the camera's target plane**. Objects
  /// closer to the camera grow above this value, objects farther shrink.
  double zoom;

  /// Painted before anything else when set.
  Color? background;

  /// Optional ground grid painted before the objects.
  SpriteStackGround? ground;

  /// Props in the scene. Order only breaks depth ties.
  List<SpriteStackSceneObject> objects;

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

    final scale = zoom * object.scale * camera.distance / depth;
    final screen = Offset(
      size.width / 2 + relative.dot(basis.right) * scale,
      size.height / 2 - relative.dot(basis.up) * scale,
    );
    final yaw = object.yaw - camera.yaw;
    final bounds = object.stack.boundsFor(
      yaw: yaw,
      pitch: camera.pitch,
      scale: scale,
      spacing: object.spacing,
      cut: object.cut,
      outline: object.outline,
      shadow: object.shadow,
    );
    return SpriteStackSceneProjection(
      position: screen,
      depth: depth,
      scale: scale,
      yaw: yaw,
      bounds: bounds.rectAt(screen),
    );
  }

  /// Draws the background, the ground grid and every visible prop, far to near.
  void paint(Canvas canvas, Size size) {
    final backgroundColor = background;
    if (backgroundColor != null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);
    }

    final basis = camera.basis;
    _paintGround(canvas, size, basis);

    final drawables = <_Drawable>[];
    for (var index = 0; index < objects.length; index++) {
      final object = objects[index];
      final projection = _projectObject(object, size, basis);
      if (projection == null || !projection.isVisibleIn(size)) continue;
      drawables.add(_Drawable(index, object, projection));
    }
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
        pitch: camera.pitch,
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
      );
    }
  }

  void _paintGround(Canvas canvas, Size size, SpriteStackCameraBasis basis) {
    final ground = this.ground;
    if (ground == null || ground.step <= 0 || ground.extent <= 0) return;

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
