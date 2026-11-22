import 'package:bonfire/bonfire.dart';

import 'cached_stack.dart';

/// Static scenery (tree, house...) drawn from a pre-rendered sprite stack.
///
/// Bonfire Y-sorts [GameComponent]s by the bottom of their rect, so props and
/// the car overlap correctly.
class StackProp extends GameComponent {
  StackProp({
    required Vector2 center,
    required this.visual,
    this.yaw = 0,
  }) {
    final fp = visual.footprint;
    size = Vector2(fp.width, fp.height);
    position = center - size / 2;
  }

  final CachedStack visual;
  final double yaw;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    visual.paint(canvas, yaw);
    canvas.restore();
  }
}
