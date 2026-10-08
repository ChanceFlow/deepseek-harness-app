/// The house menu surface's material.
///
/// A menu in the pin is a translucent fill over a blurred page, not a Material
/// card: `MenuSurface.module.css` `.material` paints `--dsw-menu-surface-fill`
/// with `--dsw-menu-backdrop-filter` (`blur(40px) saturate(150%)`, :25-31), the
/// surface's corner is `--dsw-radius-lg` (:3-5), and the card lifts on
/// `--dsw-elevation-prominent` with the menu's own `--dsw-alias-border-l1`
/// stroke (`Menu.module.css:16-18`), with `border: 0` on the list itself.
///
/// These assertions exist because the fill's alpha assumes the blur: a sheet
/// that dropped the `BackdropFilter` would still pass every geometry test while
/// rendering as a flat see-through panel.
library;

import 'package:app/ui/shared/menu_material.dart';
import 'package:app/ui/shared/menu_sheet.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

/// Opens the house sheet over a bare page and hands back the card's finder.
Future<Finder> _openMenu(WidgetTester tester) async {
  await tester.pumpWidget(
    l10nApp(
      theme: DshTheme.light(),
      home: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showMenuSheet<void>(
              context,
              builder: (_) => const SizedBox(height: 120, child: Text('rows')),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return find.byKey(const ValueKey('menu-sheet-card'));
}

/// The one decorated layer a predicate selects, the fill or the elevation.
BoxDecoration _decoration(
  WidgetTester tester,
  Finder card,
  bool Function(BoxDecoration) test,
) {
  return tester
      .widgetList<DecoratedBox>(
        find.descendant(of: card, matching: find.byType(DecoratedBox)),
      )
      .map((box) => box.decoration)
      .whereType<BoxDecoration>()
      .firstWhere(test);
}

void main() {
  final scheme = DshTheme.light().colorScheme;

  testWidgets('the card is the pin\'s menu material', (tester) async {
    final card = await _openMenu(tester);
    expect(card, findsOneWidget);
    expect(tester.widget(card), isA<MenuMaterial>());
  });

  testWidgets('the fill is the translucent menu surface', (tester) async {
    final card = await _openMenu(tester);
    final fill = _decoration(tester, card, (box) => box.color != null);
    expect(fill.color, scheme.menuSurfaceFill);
    // The menu's corner: `--dsw-radius-lg`, the non-compact MenuSurface.
    expect(fill.borderRadius, BorderRadius.circular(kRadiusLg));
    // `Menu.module.css` keeps `border: 0` on the list: the hairline is the
    // elevation's stroke, drawn outside the clip, not an inner border.
    expect(fill.border, isNull);
  });

  testWidgets('the fill sits on the pin\'s blur and saturation', (
    tester,
  ) async {
    final card = await _openMenu(tester);
    final backdrop = tester.widget<BackdropFilter>(
      find.descendant(of: card, matching: find.byType(BackdropFilter)),
    );
    expect(backdrop.filter, menuBackdropFilter());
  });

  testWidgets('the card lifts on the pin\'s elevation and its own stroke', (
    tester,
  ) async {
    final card = await _openMenu(tester);
    final lift = _decoration(
      tester,
      card,
      (box) => box.boxShadow?.isNotEmpty ?? false,
    );
    // `--dsw-elevation-prominent` with the menu's `border-l1` rebind, on an
    // outer box so the clip cannot eat the ring.
    expect(
      lift.boxShadow,
      DshElevation.prominent(scheme, stroke: scheme.borderL1),
    );
    expect(lift.borderRadius, BorderRadius.circular(kRadiusLg));
  });

  testWidgets('the modal sheet paints no shadow of its own', (tester) async {
    await _openMenu(tester);
    // The transparent sheet still carries the framework's modal elevation unless
    // it is zeroed, and that shadow lands under the card's `DshElevation` ring —
    // a second, heavier lift than the pin's. `showModalBottomSheet` takes no
    // `shadowColor` on this Flutter version, so a zero elevation is the whole
    // guard.
    expect(tester.widget<BottomSheet>(find.byType(BottomSheet)).elevation, 0);
  });

  testWidgets('a ListTile row keeps an ink surface inside the panel', (
    tester,
  ) async {
    // A `ListTile` paints its ink on the nearest `Material`, and the panel's
    // fill is a coloured `DecoratedBox`: without a Material between them the
    // framework asserts that the row's background and splashes may be
    // invisible, which is how the message menu's rows first failed.
    await tester.pumpWidget(
      l10nApp(
        theme: DshTheme.light(),
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showMenuSheet<void>(
                context,
                builder: (_) => ListTile(
                  dense: true,
                  title: const Text('row'),
                  onTap: () {},
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('row'), findsOneWidget);
    // The row's ink surface sits above the panel's fill, not below it.
    expect(
      find.ancestor(of: find.byType(ListTile), matching: find.byType(Material)),
      findsWidgets,
    );
  });

  testWidgets('the sheet keeps its own 4px card padding', (tester) async {
    final card = await _openMenu(tester);
    // `Menu.module.css:11` — the card pads its rows by 4px.
    expect(tester.widget<MenuMaterial>(card).padding, const EdgeInsets.all(4));
  });
}
