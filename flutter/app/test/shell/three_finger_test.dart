/// The shell's one gesture: exactly three fingers swiping vertically.
library;

import 'package:app/shell/shell_gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  required VoidCallback onDown,
  required VoidCallback onUp,
  bool enabled = true,
}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: ThreeFingerSwipeDetector(
      enabled: enabled,
      onSwipeDown: onDown,
      onSwipeUp: onUp,
      child: const SizedBox.expand(),
    ),
  );
}

/// Three simultaneous pointers moving by [dy].
Future<void> _threeFingerSwipe(WidgetTester tester, double dy) async {
  final gestures = <TestGesture>[];
  for (var pointer = 1; pointer <= 3; pointer++) {
    gestures.add(
      await tester.startGesture(
        Offset(80.0 + pointer * 20, 300),
        pointer: pointer,
      ),
    );
  }
  for (final gesture in gestures) {
    await gesture.moveBy(Offset(0, dy));
  }
  await tester.pump();
  for (final gesture in gestures) {
    await gesture.up();
  }
  await tester.pump();
}

void main() {
  testWidgets('three fingers down fire the down swipe', (tester) async {
    var downs = 0;
    var ups = 0;
    await tester.pumpWidget(_host(onDown: () => downs++, onUp: () => ups++));
    await _threeFingerSwipe(tester, 60);
    expect(downs, 1);
    expect(ups, 0);
  });

  testWidgets('three fingers up fire the up swipe', (tester) async {
    var downs = 0;
    var ups = 0;
    await tester.pumpWidget(_host(onDown: () => downs++, onUp: () => ups++));
    await _threeFingerSwipe(tester, -60);
    expect(ups, 1);
    expect(downs, 0);
  });

  testWidgets('below the distance threshold nothing fires', (tester) async {
    var downs = 0;
    await tester.pumpWidget(_host(onDown: () => downs++, onUp: () {}));
    await _threeFingerSwipe(tester, 20);
    expect(downs, 0);
  });

  testWidgets('two fingers never fire', (tester) async {
    var downs = 0;
    await tester.pumpWidget(_host(onDown: () => downs++, onUp: () {}));
    final a = await tester.startGesture(const Offset(100, 300), pointer: 1);
    final b = await tester.startGesture(const Offset(140, 300), pointer: 2);
    await a.moveBy(const Offset(0, 60));
    await b.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(downs, 0);
    await a.up();
    await b.up();
  });

  testWidgets('a fourth finger cancels the gesture', (tester) async {
    var downs = 0;
    await tester.pumpWidget(_host(onDown: () => downs++, onUp: () {}));
    final gestures = <TestGesture>[];
    for (var pointer = 1; pointer <= 4; pointer++) {
      gestures.add(
        await tester.startGesture(
          Offset(80.0 + pointer * 20, 300),
          pointer: pointer,
        ),
      );
    }
    for (final gesture in gestures) {
      await gesture.moveBy(const Offset(0, 60));
    }
    await tester.pump();
    expect(downs, 0);
    for (final gesture in gestures) {
      await gesture.up();
    }
  });

  testWidgets('a disabled detector stays inert', (tester) async {
    var downs = 0;
    await tester.pumpWidget(
      _host(onDown: () => downs++, onUp: () {}, enabled: false),
    );
    await _threeFingerSwipe(tester, 60);
    expect(downs, 0);
  });
}
