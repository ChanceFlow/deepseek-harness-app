/// The session row's pin verb: an archived row offers none (the Host
/// refuses a pinned archived session), a pinned row offers unpin and wears
/// the glyph, an unpinned row offers pin.
library;

import 'package:app/ui/shared/session_tree.dart';
import 'package:domain/model/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

SessionSummary _session({bool archived = false}) => SessionSummary(
  id: 's1',
  title: 'session s1',
  blank: false,
  archived: archived,
  updatedAtEpochMs: 0,
);

Future<void> _pumpRow(
  WidgetTester tester, {
  required bool pinned,
  required bool archived,
  VoidCallback? onPin,
  VoidCallback? onUnpin,
  VoidCallback? onUnarchive,
}) => tester.pumpWidget(
  l10nApp(
    home: Scaffold(
      body: SessionTreeRow(
        session: _session(archived: archived),
        selected: false,
        nowEpochMs: 0,
        showVerbButton: true,
        pinned: pinned,
        onPin: onPin,
        onUnpin: onUnpin,
        onUnarchive: onUnarchive,
      ),
    ),
  ),
);

void main() {
  testWidgets('an unpinned row offers Pin session', (tester) async {
    var pinned = 0;
    await _pumpRow(
      tester,
      pinned: false,
      archived: false,
      onPin: () => pinned++,
    );

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Pin session'), findsOneWidget);
    expect(find.text('Unpin session'), findsNothing);
    // The panel rides the house menu surface, not a Material card:
    // `showMenuSheet` mounts its material under this anchor key.
    expect(find.byKey(const ValueKey('menu-sheet-card')), findsOneWidget);

    await tester.tap(find.text('Pin session'));
    await tester.pumpAndSettle();
    expect(pinned, 1);
  });

  testWidgets('a pinned row wears the glyph and offers Unpin session', (
    tester,
  ) async {
    var unpinned = 0;
    await _pumpRow(
      tester,
      pinned: true,
      archived: false,
      onUnpin: () => unpinned++,
    );

    expect(find.byIcon(Icons.push_pin), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Unpin session'), findsOneWidget);
    expect(find.text('Pin session'), findsNothing);

    await tester.tap(find.text('Unpin session'));
    await tester.pumpAndSettle();
    expect(unpinned, 1);
  });

  testWidgets('an archived row never offers the pin verb', (tester) async {
    await _pumpRow(
      tester,
      pinned: false,
      archived: true,
      onPin: () {},
      onUnpin: () {},
      onUnarchive: () {},
    );

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Pin session'), findsNothing);
    expect(find.text('Unarchive session'), findsOneWidget);
  });
}
