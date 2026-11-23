import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_sprite_stack_example/f1_game/f1_game_screen.dart';

void main() {
  testWidgets('F1GameScreen mounts without throwing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: F1GameScreen()),
    );

    // Let the game load assets and run several frames.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(tester.takeException(), isNull);
    expect(find.byType(F1GameScreen), findsOneWidget);
  });
}
