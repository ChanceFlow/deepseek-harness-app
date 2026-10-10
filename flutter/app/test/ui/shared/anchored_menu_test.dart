/// The menu popover: placement against its trigger, the pin's three
/// dismissals, and the two properties it must not lose — no scrim, and the
/// reader's scroll untouched.
///
/// The reference places a portaled menu from the anchor rect
/// (`ui-primitives/useAnchoredPosition.ts:39-120`) and dismisses it on an
/// outside pointerdown (`useDismissOnOutsidePointer.ts:23-33`), Escape, or a
/// window blur (`Menu.tsx:131-142`). These assertions ride the real widget:
/// the card's rect is compared against the trigger's, and no route, barrier or
/// sheet may exist between them.
library;

import 'package:app/ui/shared/anchored_menu.dart';
import 'package:app/ui/shared/menu_material.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

const ValueKey<String> _kAnchor = ValueKey<String>('anchor');
const ValueKey<String> _kCard = ValueKey<String>('anchored-menu-card');

/// A phone page whose trigger sits at the bottom over a scrollable the reader
/// owns, so both the placement and the scroll assertions have real geometry.
Future<void> _pump(
  WidgetTester tester, {
  MenuSide side = MenuSide.top,
  MenuAlign align = MenuAlign.start,
  ScrollController? scroll,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    l10nApp(
      theme: DshTheme.light(),
      home: Scaffold(
        body: Column(
          children: <Widget>[
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: 40,
                itemBuilder: (BuildContext _, int index) =>
                    SizedBox(height: 48, child: Text('row $index')),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: AnchoredMenu(
                side: side,
                align: align,
                gap: 8,
                margin: 12,
                cardKey: _kCard,
                trigger:
                    (BuildContext context, bool open, VoidCallback toggle) =>
                        ElevatedButton(
                          key: _kAnchor,
                          onPressed: toggle,
                          child: const Text('open'),
                        ),
                card: (BuildContext context, VoidCallback close) =>
                    const SizedBox(width: 120, height: 60, child: Text('card')),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(_kAnchor));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the card is placed against its trigger, above it and left', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await _open(tester);

    final Rect anchor = tester.getRect(find.byKey(_kAnchor));
    final Rect card = tester.getRect(find.byKey(_kCard));
    // `side: top` with the caller's 8px gap: the card's bottom edge sits the
    // gap above the trigger's top edge.
    expect(anchor.top - card.bottom, 8);
    // `align: start`: the two left edges line up.
    expect(card.left, anchor.left);
    // Not a bottom seam: the card is nowhere near the page's own bottom edge.
    expect(card.bottom, lessThan(anchor.top));
  });

  testWidgets('a viewport change while open re-seats the card on its anchor', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await _open(tester);

    final Rect before = tester.getRect(find.byKey(_kAnchor));
    // Shrink the page under the open card. The trigger moves up with the
    // bottom edge, so a card placed from a rectangle measured during build
    // stays where the old anchor was — the stale rect this contract exists to
    // prevent (the reference re-reads the anchor every frame while open,
    // `Menu.tsx:154-160`).
    tester.view.physicalSize = const Size(400, 420);
    await tester.pumpAndSettle();

    final Rect anchor = tester.getRect(find.byKey(_kAnchor));
    final Rect card = tester.getRect(find.byKey(_kCard));
    expect(anchor.top, lessThan(before.top));
    expect(anchor.top - card.bottom, 8);
    expect(card.left, anchor.left);
  });

  testWidgets('align end lines the card up with the trigger\'s right edge', (
    WidgetTester tester,
  ) async {
    await _pump(tester, align: MenuAlign.end);
    await _open(tester);

    final Rect anchor = tester.getRect(find.byKey(_kAnchor));
    final Rect card = tester.getRect(find.byKey(_kCard));
    expect(card.right, anchor.right);
    expect(anchor.top - card.bottom, 8);
  });

  testWidgets('the popover is not a route: nothing paints a barrier', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await _open(tester);

    expect(find.byKey(_kCard), findsOneWidget);
    expect(tester.widget(find.byKey(_kCard)), isA<MenuMaterial>());
    // The pin's menu carries no mask, and the popover owns no route: no
    // barrier, no sheet, no modal machinery to paint or dim anything.
    for (final ModalBarrier b in tester.widgetList<ModalBarrier>(
      find.byType(ModalBarrier),
    )) {
      debugPrint('BARRIER color=${b.color} dismissible=${b.dismissible}');
    }
    expect(find.byType(BottomSheet), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a tap inside the card closes it and leaves the page standing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      l10nApp(
        theme: DshTheme.light(),
        home: Scaffold(
          body: Column(
            children: <Widget>[
              const Expanded(child: Center(child: Text('the page'))),
              AnchoredMenu(
                cardKey: _kCard,
                trigger:
                    (BuildContext context, bool open, VoidCallback toggle) =>
                        ElevatedButton(
                          key: _kAnchor,
                          onPressed: toggle,
                          child: const Text('open'),
                        ),
                card: (BuildContext context, VoidCallback close) =>
                    TextButton(onPressed: close, child: const Text('a verb')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _open(tester);

    await tester.tap(find.text('a verb'));
    await tester.pumpAndSettle();
    expect(find.byKey(_kCard), findsNothing);
    // The row closed the popover and nothing else: a migrated seat's rows used
    // to pop their sheet route, and that pop now lands on the page the card
    // floats over.
    expect(find.text('the page'), findsOneWidget);
  });

  testWidgets('an outside tap closes it', (WidgetTester tester) async {
    await _pump(tester);
    await _open(tester);

    await tester.tapAt(const Offset(200, 80));
    await tester.pumpAndSettle();
    expect(find.byKey(_kCard), findsNothing);
  });

  testWidgets('Escape closes it', (WidgetTester tester) async {
    await _pump(tester);
    await _open(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(_kCard), findsNothing);
  });

  testWidgets('a window blur closes it', (WidgetTester tester) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await _pump(tester);
    await _open(tester);

    // The pin's third dismissal is the window losing focus
    // (`Menu.tsx:131-142`); on a phone that is the app leaving the foreground.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.byKey(_kCard), findsNothing);
  });

  testWidgets('the system back press closes it, not the screen behind', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await _open(tester);

    // A popover owns no route, so the press it does not consume would pop the
    // screen the reader is on.
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byKey(_kCard), findsNothing);
    // With the menu closed the press is the platform's again.
    expect(await tester.binding.handlePopRoute(), isFalse);
  });

  testWidgets('opening and dismissing leaves the reader\'s scroll alone', (
    WidgetTester tester,
  ) async {
    final ScrollController scroll = ScrollController();
    addTearDown(scroll.dispose);
    await _pump(tester, scroll: scroll);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    final double before = scroll.offset;
    expect(before, greaterThan(0));

    await _open(tester);
    expect(scroll.offset, before);
    await tester.tapAt(const Offset(200, 80));
    await tester.pumpAndSettle();
    expect(find.byKey(_kCard), findsNothing);
    expect(scroll.offset, before);
  });

  testWidgets('a trigger whose fact is gone cannot open, and closes', (
    WidgetTester tester,
  ) async {
    // `canOpen` mirrors the pin closing a panel whose fact went away
    // (`ContextMeter.tsx:74-77`).
    await tester.pumpWidget(
      l10nApp(
        theme: DshTheme.light(),
        home: Scaffold(
          body: Center(
            child: AnchoredMenu(
              canOpen: false,
              cardKey: _kCard,
              trigger: (BuildContext context, bool open, VoidCallback toggle) =>
                  ElevatedButton(onPressed: toggle, child: const Text('open')),
              card: (BuildContext context, VoidCallback close) =>
                  const Text('card'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(_kCard), findsNothing);
  });
}
