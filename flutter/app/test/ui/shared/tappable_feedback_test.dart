import 'package:app/ui/shared/tappable_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DshTappable fires onTap and renders child', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DshTappable(
            onTap: () => tapped = true,
            child: const Text('Tap Me'),
          ),
        ),
      ),
    );

    expect(find.text('Tap Me'), findsOneWidget);
    await tester.tap(find.text('Tap Me'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  testWidgets('DshTappable animates scale down on tap down and springs back', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DshTappable(
              onTap: () {},
              pressedScale: 0.9,
              child: const ColoredBox(
                color: Colors.blue,
                child: SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(DshTappable));
    final gesture = await tester.startGesture(center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final scaleFinder = find.descendant(
      of: find.byType(DshTappable),
      matching: find.byType(ScaleTransition),
    );
    expect(scaleFinder, findsOneWidget);
    final scaleTransition = tester.widget<ScaleTransition>(scaleFinder);
    expect(scaleTransition.scale.value, lessThan(1.0));

    // Release gesture
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleTransition.scale.value, equals(1.0));
  });

  testWidgets(
    'DshTappable skips ScaleTransition when reduced motion is enabled',
    (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: DshTappable(
                onTap: () => tapped = true,
                child: const Text('Reduced Motion'),
              ),
            ),
          ),
        ),
      );

      final scaleFinder = find.descendant(
        of: find.byType(DshTappable),
        matching: find.byType(ScaleTransition),
      );
      expect(scaleFinder, findsNothing);
      await tester.tap(find.text('Reduced Motion'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    },
  );
}
