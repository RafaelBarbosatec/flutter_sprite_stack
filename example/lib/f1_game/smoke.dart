import 'dart:math' as math;
import 'dart:ui';

import 'package:bonfire/bonfire.dart';

/// Builds one pixel-art smoke puff using Flame's particle system.
///
/// The puff is an [AcceleratedParticle] (drifts away and rises) wrapping a
/// [ComputedParticle] that draws a square growing and fading in four steps,
/// so it matches the crisp pixel look of the sprite stacks.
ParticleSystemComponent buildSmokePuff({
  required Vector2 position,
  required Vector2 velocity,
  required math.Random random,
  int? priority,
  double intensity = 1,
}) {
  final lifespan = 0.55 + random.nextDouble() * 0.45;
  final startSize = 3 + random.nextInt(2) * 1.0;
  final grow = (7 + random.nextDouble() * 5) * (0.7 + intensity * 0.5);
  final paint = Paint()..isAntiAlias = false;

  return ParticleSystemComponent(
    position: position,
    priority: priority,
    particle: AcceleratedParticle(
      lifespan: lifespan,
      speed: velocity,
      // Warm exhaust smoke rises (screen up) while it slows down.
      acceleration: Vector2(0, -26) - velocity * 1.4,
      child: ComputedParticle(
        renderer: (canvas, particle) {
          final t = particle.progress;
          // Fade in 4 pixel-art steps.
          final alpha = switch (t) {
            < 0.25 => 0.85,
            < 0.5 => 0.62,
            < 0.75 => 0.38,
            _ => 0.18,
          };
          // Light grey at birth, darker as it dissipates.
          final tone = (236 - t * 46).round();
          final side = (startSize + grow * t).roundToDouble();
          paint.color = Color.fromRGBO(tone, tone, tone + 6, alpha);
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: side,
              height: side,
            ),
            paint,
          );
        },
      ),
    ),
  );
}
