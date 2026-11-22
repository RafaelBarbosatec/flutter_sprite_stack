import 'package:flame/components.dart';

import 'sprite_stack_animation.dart';
import 'sprite_stack_component.dart';

/// Flame/Bonfire component that plays a [SpriteStackAnimation].
///
/// It is a [SpriteStackComponent] with the frame driven by the animation, so
/// bounds, culling, hit boxes and Y sorting behave exactly the same. Every
/// camera option is forwarded:
///
/// ```dart
/// add(
///   AnimatedSpriteStackComponent(
///     animation: torch,
///     position: Vector2(120, 200),
///     stackScale: 4,
///     priority: 10,
///   ),
/// );
/// ```
class AnimatedSpriteStackComponent extends SpriteStackComponent {
  AnimatedSpriteStackComponent({
    required this.animation,
    super.yaw,
    super.pitch,
    super.stackScale,
    super.spacing,
    super.pixelSnap,
    super.outline,
    super.shadow,
    super.outlineColor,
    super.shadowColor,
    super.position,
    super.priority,
  }) : super(stack: animation.stack);

  /// Playback state for [stack].
  final SpriteStackAnimation animation;

  @override
  void update(double dt) {
    super.update(dt);
    animation.update(dt);
    frame = animation.frame;
  }
}
