/// The native settings page: hosts, notifications, appearance, language and
/// about, with every mutation observed at the seam the widget uses.
///
/// The registry controller is concrete and starts a store read on
/// construction, so the page's dispatch seam records actions instead; the
/// appearance and language seams do the same for their controllers, and a
/// [SystemNotifier] subclass records the permission ask.
library;

import 'dart:io';

import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/local_state/local_state_providers.dart';
import 'package:app/local_state/local_state_store.dart';
import 'package:app/local_state/locale_preference.dart';
import 'package:app/notifications/notification_channel_health.dart';
import 'package:app/notifications/notification_preferences.dart';
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

/// An in-memory [LocalStateStore]: this is a widget test under fake async,
/// where real file IO never settles; the disk round-trip belongs to
/// `local_state_store_test.dart` and the preferences unit test. The settings
/// rows still exercise the real preference controller over the store seam.
class _MemoryLocalStateStore extends LocalStateStore {
  _MemoryLocalStateStore() : super(File('local_state.json'));

  final Map<String, Object?> values = <String, Object?>{};

  @override
  Object? read(String key) => values[key];

  @override
  void write(String key, Object? value) {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> flush() async {}

  @override
  bool get isLoaded => true;
}

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

/// The platform health seam: the test flips [health] as the user would in
/// Android's own settings page, and counts the opens the block performed.
class _HealthSeam {
  NotificationChannelHealth health = const NotificationChannelHealth(
    appEnabled: false,
  );
  int opened = 0;
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
  required LocalStateStore store,
  Future<NotificationChannelHealth> Function()? health,
  OpenNotificationSettings? openNotificationSettings,
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
      localStateStoreProvider.overrideWith((ref) async => store),
      notificationChannelHealthProvider.overrideWith(
        (ref) =>
            health?.call() ??
            Future<NotificationChannelHealth>.value(
              const NotificationChannelHealth(),
            ),
      ),
      openNotificationSettingsProvider.overrideWithValue(
        openNotificationSettings ?? ({String? channelId}) async {},
      ),
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
  LocalStateStore? store,
  _FakeNotifier? notifier,
  Future<NotificationChannelHealth> Function()? health,
  OpenNotificationSettings? openNotificationSettings,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final LocalStateStore stateStore = store ?? _MemoryLocalStateStore();
  await tester.pumpWidget(
    _app(
      hosts: hosts,
      activeId: activeId,
      recorder: recorder,
      notifier: notifier ?? _FakeNotifier(),
      store: stateStore,
      health: health,
      openNotificationSettings: openNotificationSettings,
    ),
  );
  await tester.pumpAndSettle();
}

List<TextField> _fields(WidgetTester tester) =>
    tester.widgetList<TextField>(find.byType(TextField)).toList();

Switch _switch(WidgetTester tester, String arbKey) =>
    tester.widget<Switch>(find.byKey(ValueKey<String>(arbKey)));

Future<void> _toggle(WidgetTester tester, String arbKey) async {
  await tester.tap(find.byKey(ValueKey<String>(arbKey)));
  await tester.pumpAndSettle();
}

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

  testWidgets('notification preferences render under the permission row', (
    tester,
  ) async {
    final recorder = _Recorder();
    await _pumpSettings(
      tester,
      hosts: [_laptop],
      activeId: 'laptop',
      recorder: recorder,
    );

    expect(
      find.text('Choose what the app may tell you about.'),
      findsOneWidget,
    );
    for (final String key in <String>[
      'settingsNotifyReplies',
      'settingsNotifyFailures',
      'settingsNotifyAttention',
    ]) {
      expect(_switch(tester, key).value, isTrue, reason: '$key defaults to on');
    }
    expect(find.text('Notifications'), findsNWidgets(2));
  });

  testWidgets('toggling a preference persists its key through the store', (
    tester,
  ) async {
    final recorder = _Recorder();
    final LocalStateStore store = _MemoryLocalStateStore();
    await _pumpSettings(
      tester,
      hosts: [_laptop],
      activeId: 'laptop',
      recorder: recorder,
      store: store,
    );

    await _toggle(tester, 'settingsNotifyReplies');
    expect(_switch(tester, 'settingsNotifyReplies').value, isFalse);
    expect(store.read(kAppNotifyRepliesKey), isFalse);

    // The whole row toggles, not just the switch.
    await tester.tap(find.text('Failures and stops'));
    await tester.pumpAndSettle();
    expect(_switch(tester, 'settingsNotifyFailures').value, isFalse);
    expect(store.read(kAppNotifyFailuresKey), isFalse);

    await _toggle(tester, 'settingsNotifyAttention');
    expect(_switch(tester, 'settingsNotifyAttention').value, isFalse);
    expect(store.read(kAppNotifyAttentionKey), isFalse);
  });

  testWidgets('the master switch gates the seats but keeps their values', (
    tester,
  ) async {
    final recorder = _Recorder();
    final LocalStateStore store = _MemoryLocalStateStore();
    await _pumpSettings(
      tester,
      hosts: [_laptop],
      activeId: 'laptop',
      recorder: recorder,
      store: store,
    );

    await _toggle(tester, 'settingsNotifyMaster');

    expect(_switch(tester, 'settingsNotifyMaster').value, isFalse);
    expect(store.read(kAppNotifyEnabledKey), isFalse);
    for (final String key in <String>[
      'settingsNotifyReplies',
      'settingsNotifyFailures',
      'settingsNotifyAttention',
    ]) {
      final Switch row = _switch(tester, key);
      expect(
        row.value,
        isTrue,
        reason: '$key keeps its stored value while the master is off',
      );
      expect(
        row.onChanged,
        isNull,
        reason: '$key is inert while the master is off',
      );
    }

    await _toggle(tester, 'settingsNotifyMaster');
    expect(_switch(tester, 'settingsNotifyReplies').onChanged, isNotNull);
    expect(store.read(kAppNotifyEnabledKey), isTrue);
  });

  testWidgets('the health block stays hidden while every channel posts', (
    tester,
  ) async {
    final recorder = _Recorder();
    await _pumpSettings(
      tester,
      hosts: [_laptop],
      activeId: 'laptop',
      recorder: recorder,
      health: () async => const NotificationChannelHealth(),
    );

    expect(find.text('System settings'), findsNothing);
    expect(find.text('Open Android settings'), findsNothing);
  });

  testWidgets('a blocked channel shows the block and opening re-reads health', (
    tester,
  ) async {
    final recorder = _Recorder();
    final seam = _HealthSeam();
    await _pumpSettings(
      tester,
      hosts: [_laptop],
      activeId: 'laptop',
      recorder: recorder,
      health: () async => seam.health,
      openNotificationSettings: ({String? channelId}) async {
        seam.opened += 1;
        seam.health = const NotificationChannelHealth();
      },
    );

    expect(
      find.text(
        'Android has silenced some notifications. '
        'The app cannot turn them back on.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Open Android settings'));
    await tester.pumpAndSettle();

    expect(seam.opened, 1);
    expect(
      find.text(
        'Android has silenced some notifications. '
        'The app cannot turn them back on.',
      ),
      findsNothing,
      reason: 'the block invalidates the health provider after the return',
    );
  });
}
