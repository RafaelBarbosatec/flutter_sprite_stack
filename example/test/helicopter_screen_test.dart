import 'package:flutter/material.dart';
import 'package:flutter_sprite_stack_example/helicopter_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('HelicopterScreen mounts and builds controls', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: HelicopterScreen(),
      ),
    );

    // Initial loading or loaded state
    expect(find.byType(HelicopterScreen), findsOneWidget);
    expect(find.text('AH-64 Viper / Animated Helicopter'), findsOneWidget);
  });
}
