/// The WebView shell's frame: one page per host on a strip, the exposé
/// drawer, and the settings orb.
///
/// The pages are stand-ins here (`hostViewBuilder`), so no platform view is
/// created; what is under test is the shell, not the WebView.
library;

import 'package:app/di/providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/shell/shell_page_strip.dart';
import 'package:app/shell/shell_root.dart';
import 'package:app/theme/theme.dart';
import 'package:domain/model/backend.dart';
import 'package:domain/model/connection_state.dart' as domain;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final BackendConfig _laptop = BackendConfig(
  id: 'laptop',
  label: 'Laptop',
  baseUri: Uri.parse('http://10.0.0.5:3083'),
);
final BackendConfig _desktop = BackendConfig(
  id: 'desktop',
  label: 'Desktop',
  baseUri: Uri.parse('http://10.0.0.6:3083'),
);

Widget _shell(List<BackendConfig> hosts, {String? activeId}) {
  return ProviderScope(
    overrides: [
      backendRegistryStateProvider.overrideWith(
        (ref) => Stream<BackendRegistryState>.value(
          BackendRegistryState(backends: hosts, activeId: activeId),
        ),
      ),
      backendConnectionStateProvider.overrideWith(
        (ref, backendId) => Stream<domain.ConnectionState>.value(
          const domain.ConnectionState(phase: domain.ConnectionPhase.connected),
        ),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: DshTheme.light(),
      home: ShellRoot(
        hostViewBuilder: (context, backend) => Text('page:${backend.id}'),
      ),
    ),
  );
}

ShellPageStrip _strip(WidgetTester tester) =>
    tester.widget<ShellPageStrip>(find.byType(ShellPageStrip));

void main() {
  testWidgets('hosts sit side by side on one strip; the active page fills '
      'the window', (tester) async {
    await tester.pumpWidget(_shell([_laptop, _desktop], activeId: 'laptop'));
    await tester.pumpAndSettle();

    // Both pages are built; only the active one is inside the window.
    expect(find.text('page:laptop'), findsOneWidget);
    expect(find.text('page:desktop'), findsOneWidget);
    final strip = _strip(tester);
    expect(strip.position, 0);
    expect(strip.verticalOffset, 0);
    expect(tester.getTopLeft(find.text('page:laptop')).dx, 0);
    expect(
      tester.getTopLeft(find.text('page:desktop')).dx,
      tester.view.physicalSize.width / tester.view.devicePixelRatio,
    );

    // The grabber is the persistent way in.
    expect(find.byKey(const ValueKey<String>('shell-grabber')), findsOneWidget);
  });

  testWidgets('the grabber pushes the strip down and opens the drawer', (
    tester,
  ) async {
    await tester.pumpWidget(_shell([_laptop, _desktop], activeId: 'laptop'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('shell-grabber')));
    await tester.pumpAndSettle();

    expect(_strip(tester).verticalOffset, kExposeDrawerHeight);
    expect(
      find.byKey(const ValueKey<String>('host-bubble:laptop')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('host-bubble:desktop')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('tapping another bubble sweeps the strip and collapses', (
    tester,
  ) async {
    await tester.pumpWidget(_shell([_laptop, _desktop], activeId: 'laptop'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('shell-grabber')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('host-bubble:desktop')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final midway = _strip(tester).position;
    expect(midway, greaterThan(0), reason: 'the strip left the first host');
    expect(midway, lessThan(1), reason: 'it has not landed yet');

    await tester.pumpAndSettle();
    expect(_strip(tester).position, 1);
    expect(_strip(tester).verticalOffset, 0, reason: 'the drawer collapsed');
    expect(
      find.byKey(const ValueKey<String>('host-bubble:desktop')).hitTestable(),
      findsNothing,
    );
  });

  testWidgets('no hosts renders the empty shell with the add action', (
    tester,
  ) async {
    await tester.pumpWidget(_shell(const []));
    await tester.pumpAndSettle();

    expect(find.byType(ShellPageStrip), findsNothing);
    expect(find.text('No hosts yet'), findsOneWidget);
    expect(find.text('Add host'), findsOneWidget);
  });
}
