/// The WebView shell's frame: one page per host, a switcher, and the bar.
///
/// The pages are stand-ins here (`hostViewBuilder`), so no platform view is
/// created; what is under test is the shell, not the WebView.
library;

import 'package:app/di/providers.dart';
import 'package:app/l10n/app_localizations.dart';
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

void main() {
  testWidgets('one page per enabled host, active host in the bar', (
    tester,
  ) async {
    await tester.pumpWidget(_shell([_laptop, _desktop], activeId: 'laptop'));
    await tester.pumpAndSettle();

    expect(find.text('page:laptop'), findsOneWidget);
    expect(find.text('page:desktop', skipOffstage: false), findsOneWidget);
    expect(
      tester.widget<IndexedStack>(find.byType(IndexedStack)).index,
      0,
      reason: 'the registry active host renders first',
    );
    expect(find.text('Laptop'), findsWidgets);
    expect(find.text('10.0.0.5:3083'), findsOneWidget);
  });

  testWidgets('the switcher moves the stack to another host', (tester) async {
    await tester.pumpWidget(_shell([_laptop, _desktop], activeId: 'laptop'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Desktop'));
    await tester.pumpAndSettle();

    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);
    expect(find.text('10.0.0.6:3083'), findsOneWidget);
  });

  testWidgets('no hosts renders the empty shell with the add action', (
    tester,
  ) async {
    await tester.pumpWidget(_shell(const []));
    await tester.pumpAndSettle();

    expect(find.byType(IndexedStack), findsNothing);
    // The bar and the empty state both name the absence.
    expect(find.text('No hosts yet'), findsWidgets);
    expect(find.text('Add host'), findsOneWidget);
  });
}
