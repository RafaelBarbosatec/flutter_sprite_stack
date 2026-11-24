import 'package:flutter/material.dart';
import 'package:flutter_sprite_stack_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DemoScreen mounts in phone size and wide size without overflow',
      (tester) async {
    // Mobile screen (portrait)
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const SpriteStackExampleApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.byType(DemoScreen), findsOneWidget);

    // Verify chips and sliders exist
    expect(find.text('X-Wing'), findsOneWidget);
    expect(find.text('Car'), findsOneWidget);

    // Tablet / Desktop screen (landscape)
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });
}
