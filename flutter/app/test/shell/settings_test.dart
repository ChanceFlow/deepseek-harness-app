/// The native settings page: hosts, notifications, appearance, language and
/// about, with every mutation observed at the seam the widget uses.
///
/// The registry controller is concrete and starts a store read on
/// construction, so the page's dispatch seam records actions instead; the
/// appearance and language seams do the same for their controllers, and a
/// [SystemNotifier] subclass records the permission ask.
library;

import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/local_state/locale_preference.dart';
import 'package:app/notifications/system_notifier.dart';
import 'package:app/shell/host_editor.dart';
import 'package:app/shell/shell_settings.dart';
import 'package:app/theme/theme.dart';
import 'package:app/theme/theme_preference.dart';
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
final BackendConfig _disabled = BackendConfig(
  id: 'disabled',
  label: 'Build box',
  baseUri: Uri.parse('http://10.0.0.7:3083'),
  enabled: false,
);

/// Records every mutation the page routes to a controller seam.
class _Recorder {
  final List<BackendAction> actions = <BackendAction>[];
  final List<ThemePreference> themes = <ThemePreference>[];
  final List<AppLocalePreference> locales = <AppLocalePreference>[];

  void dispatch(BackendAction action) => actions.add(action);

  Future<void> selectTheme(ThemePreference preference) async {
    themes.add(preference);
  }

  Future<void> selectLocale(AppLocalePreference preference) async {
    locales.add(preference);
  }
}

/// A notifier that answers the one ask the settings row makes.
class _FakeNotifier extends SystemNotifier {
  bool _granted = false;
  int requests = 0;

  @override
  bool get permissionGranted => _granted;

  @override
  Future<bool> ensurePermissionRequested() async {
    requests += 1;
    _granted = true;
    return _granted;
  }
}

Widget _app({
  required List<BackendConfig> hosts,
  required String? activeId,
  required _Recorder recorder,
  required _FakeNotifier notifier,
}) {
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
      shellRegistryDispatchProvider.overrideWithValue(recorder.dispatch),
      shellThemePreferenceProvider.overrideWith(
        (ref) => Stream<ThemePreferenceState>.value(
          const ThemePreferenceState(
            exposed: true,
            writable: true,
            preference: ThemePreference.system,
          ),
        ),
      ),
      appOledAppearanceProvider.overrideWith(
        (ref) => Stream<bool>.value(false),
      ),
      shellThemeSelectProvider.overrideWithValue(recorder.selectTheme),
      shellThemeRefreshProvider.overrideWithValue(() async {}),
      appLocalePreferenceProvider.overrideWith(
        (ref) => Stream<AppLocalePreference>.value(AppLocalePreference.system),
      ),
      shellLocaleSelectProvider.overrideWithValue(recorder.selectLocale),
      systemNotifierProvider.overrideWithValue(notifier),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: DshTheme.light(),
      home: const ShellSettingsScreen(),
    ),
  );
}

/// Pumps the settings page on a tall surface so every card builds without
/// scrolling; the cards are one list, not a lazy pager.
Future<void> _pumpSettings(
  WidgetTester tester, {
  required List<BackendConfig> hosts,
  required String? activeId,
  required _Recorder recorder,
  _FakeNotifier? notifier,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    _app(
      hosts: hosts,
      activeId: activeId,
      recorder: recorder,
      notifier: notifier ?? _FakeNotifier(),
    ),
  );
  await tester.pumpAndSettle();
}

List<TextField> _fields(WidgetTester tester) =>
    tester.widgetList<TextField>(find.byType(TextField)).toList();

void main() {
  testWidgets('hosts render with their labels, authorities and active check', (
    tester,
  ) async {
    final recorder = _Recorder();
    await _pumpSettings(
      tester,
      hosts: [_laptop, _desktop],
      activeId: 'laptop',
      recorder: recorder,
    );

    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Desktop'), findsOneWidget);
    expect(find.text('10.0.0.5:3083'), findsOneWidget);
    expect(find.text('10.0.0.6:3083'), findsOneWidget);
    expect(
      find.byIcon(Icons.check),
      findsOneWidget,
      reason: 'only the active host carries the check',
    );
    expect(find.text('Settings'), findsOneWidget);
    expect(
      find.text('$kDshAppVersion (build $kDshBuildNumber)'),
      findsOneWidget,
    );
  });

  testWidgets('a disabled host states its disabled status', (tester) async {
    final recorder = _Recorder();
    await _pumpSettings(
      tester,
      hosts: [_laptop, _disabled],
      activeId: 'laptop',
      recorder: recorder,
    );

    expect(find.text('Build box'), findsOneWidget);
    expect(find.text('Disabled'), findsOneWidget);
  });

  testWidgets('add opens a blank editor', (tester) async {
    final recorder = _Recorder();
    await _pumpSettings(
      tester,
      hosts: [_laptop],
      activeId: 'laptop',
      recorder: recorder,
    );

    await tester.tap(find.byTooltip('Add host'));
    await tester.pumpAndSettle();

    expect(find.byType(HostEditorSheet), findsOneWidget);
    final List<TextField> fields = _fields(tester);
    expect(fields, hasLength(2));
    expect(fields[0].controller!.text, isEmpty);
    expect(fields[1].controller!.text, isEmpty);
  });

  testWidgets('editing a host pre-fills its label and URL', (tester) async {
    final recorder = _Recorder();
    await _pumpSettings(
      tester,
      hosts: [_laptop, _desktop],
      activeId: 'laptop',
      recorder: recorder,
    );

    await tester.tap(find.text('Desktop'));
    await tester.pumpAndSettle();

    expect(find.byType(HostEditorSheet), findsOneWidget);
    final List<TextField> fields = _fields(tester);
    expect(fields[0].controller!.text, 'Desktop');
    expect(fields[1].controller!.text, 'http://10.0.0.6:3083');
  });

  testWidgets('an invalid URL is refused inline and dispatches nothing', (
    tester,
  ) async {
    final recorder = _Recorder();
    await _pumpSettings(
      tester,
      hosts: [_laptop],
      activeId: 'laptop',
      recorder: recorder,
    );

    await tester.tap(find.byTooltip('Add host'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'New host');
    await tester.enterText(find.byType(TextField).at(1), 'ftp://example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid host base URL.'), findsOneWidget);
    expect(find.byType(HostEditorSheet), findsOneWidget);
    expect(recorder.actions, isEmpty);
  });

  testWidgets('a valid new host dispatches AddBackend', (tester) async {
    final recorder = _Recorder();
    await _pumpSettings(
      tester,
      hosts: [_laptop],
      activeId: 'laptop',
      recorder: recorder,
    );

    await tester.tap(find.byTooltip('Add host'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Build box');
    await tester.enterText(
      find.byType(TextField).at(1),
      'https://10.0.0.7:3083',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(recorder.actions, hasLength(1));
    final BackendAction action = recorder.actions.single;
    expect(action, isA<AddBackend>());
    final AddBackend add = action as AddBackend;
    expect(add.label, 'Build box');
    expect(add.baseUrl, 'https://10.0.0.7:3083');
    expect(add.trustHostCertificate, isFalse);
  });

  testWidgets('saving an existing host dispatches the four mutations', (
    tester,
  ) async {
    final recorder = _Recorder();
    await _pumpSettings(
      tester,
      hosts: [_laptop, _desktop],
      activeId: 'laptop',
      recorder: recorder,
    );

    await tester.tap(find.text('Desktop'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Studio');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(recorder.actions, hasLength(4));
    final RenameBackend rename = recorder.actions[0] as RenameBackend;
    expect(rename.label, 'Studio');
    expect(recorder.actions[1], isA<UpdateBackendUrl>());
    expect(recorder.actions[2], isA<SetBackendTrustHostCertificate>());
    expect(recorder.actions[3], isA<SetBackendEnabled>());
  });

  testWidgets('removing the active host is refused before any dialog', (
    tester,
  ) async {
    final recorder = _Recorder();
    await _pumpSettings(
      tester,
      hosts: [_laptop, _desktop],
      activeId: 'laptop',
      recorder: recorder,
    );

    await tester.tap(find.text('Laptop'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(
      find.text('Switch away before removing the active host.'),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(recorder.actions, isEmpty);
  });

  testWidgets('removing the last host is refused', (tester) async {
    final recorder = _Recorder();
    await _pumpSettings(
      tester,
      hosts: [_laptop],
      activeId: 'laptop',
      recorder: recorder,
    );

    await tester.tap(find.text('Laptop'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(find.text('The last host cannot be removed.'), findsOneWidget);
    expect(recorder.actions, isEmpty);
  });

  testWidgets('the appearance choice calls the theme seam', (tester) async {
    final recorder = _Recorder();
    await _pumpSettings(
      tester,
      hosts: [_laptop],
      activeId: 'laptop',
      recorder: recorder,
    );

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(recorder.themes, <ThemePreference>[ThemePreference.dark]);
  });

  testWidgets('the language choice calls the locale seam', (tester) async {
    final recorder = _Recorder();
    await _pumpSettings(
      tester,
      hosts: [_laptop],
      activeId: 'laptop',
      recorder: recorder,
    );

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(recorder.locales, <AppLocalePreference>[AppLocalePreference.en]);
  });

  testWidgets('the notification row asks the notifier and shows the grant', (
    tester,
  ) async {
    final recorder = _Recorder();
    final notifier = _FakeNotifier();
    await _pumpSettings(
      tester,
      hosts: [_laptop],
      activeId: 'laptop',
      recorder: recorder,
      notifier: notifier,
    );

    expect(find.text('Allow'), findsOneWidget);
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();

    expect(notifier.requests, 1);
    expect(find.text('Allow'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });
}
