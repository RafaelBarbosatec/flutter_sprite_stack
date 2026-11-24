import 'package:flutter/material.dart';
import 'package:flutter_sprite_stack_example/helicopter_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in const [
    Size(320, 568), // small phone
    Size(390, 844), // phone portrait
    Size(844, 390), // phone landscape
    Size(1024, 768), // tablet
  ]) {
    testWidgets(
      'HelicopterScreen fits ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: HelicopterScreen(),
          ),
        );

        expect(find.byType(HelicopterScreen), findsOneWidget);

        // rootBundle uses real IO, which testWidgets' fake async blocks.
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));

        // Controls built and nothing overflowed at this size.
        expect(find.text('Rotor RPM'), findsOneWidget);
        expect(find.text('Hover'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
