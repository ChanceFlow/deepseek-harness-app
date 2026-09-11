import 'package:app/ui/shared/tappable_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `HapticFeedback.vibrate` calls the wrapper actually made, read back
/// through the real platform channel rather than a seam invented for the test.
Future<List<MethodCall>> _captureHaptics(WidgetTester tester) async {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') calls.add(call);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

Finder _scaleInDshTappable() => find.descendant(
  of: find.byType(DshTappable),
  matching: find.byType(ScaleTransition),
);

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

  testWidgets('wrapping a Material control keeps its tap and fires it once', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DshTappable(
              child: IconButton(
                tooltip: 'Seat',
                onPressed: () => taps += 1,
                icon: const Icon(Icons.add),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Seat'));
    await tester.pumpAndSettle();
    // The wrapper observes the pointer; it neither owns nor doubles the tap.
    expect(taps, 1);
  });

  testWidgets('one press of a wrapped seat fires one haptic', (tester) async {
    final haptics = await _captureHaptics(tester);
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DshTappable(
              enableHaptic: true,
              child: IconButton(
                tooltip: 'Seat',
                onPressed: () => taps += 1,
                icon: const Icon(Icons.add),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Seat'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(haptics, hasLength(1));
    expect(haptics.single.arguments, 'HapticFeedbackType.selectionClick');
  });

  testWidgets('a disabled seat does not scale, click, or run its tap', (
    tester,
  ) async {
    final haptics = await _captureHaptics(tester);
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DshTappable(
              enabled: false,
              enableHaptic: true,
              onTap: () => taps += 1,
              child: const ColoredBox(
                color: Colors.blue,
                child: SizedBox(width: 80, height: 80),
              ),
            ),
          ),
        ),
      ),
    );

    // Disabled passes the child through: no scale skin is even built, so a
    // press cannot animate the seat.
    expect(_scaleInDshTappable(), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(DshTappable),
        matching: find.byType(ColoredBox),
      ),
    );
    await tester.pumpAndSettle();
    expect(taps, 0);
    expect(haptics, isEmpty);
  });

  testWidgets('a muted TickerMode holds the scale at rest and the tap lands', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: TickerMode(
          enabled: false,
          child: Scaffold(
            body: Center(
              child: DshTappable(
                onTap: () => tapped = true,
                pressedScale: 0.5,
                child: const ColoredBox(
                  color: Colors.blue,
                  child: SizedBox(width: 100, height: 100),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(DshTappable)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    // The ticker is muted, so the controller never advances: the scale stays
    // at rest instead of reaching the pressed 0.5.
    final scaleFinder = _scaleInDshTappable();
    expect(scaleFinder, findsOneWidget);
    expect(tester.widget<ScaleTransition>(scaleFinder).scale.value, 1.0);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });
}
