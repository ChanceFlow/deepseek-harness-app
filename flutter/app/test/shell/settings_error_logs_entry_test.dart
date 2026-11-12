/// The settings page's diagnostics entry: one row in the About card that
/// pushes the native error-log viewer.
library;

import 'dart:io';

import 'package:app/di/providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/local_state/local_state_providers.dart';
import 'package:app/local_state/local_state_store.dart';
import 'package:app/local_state/locale_preference.dart';
import 'package:app/logging/error_log_viewer.dart';
import 'package:app/notifications/notification_channel_health.dart';
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

/// An in-memory [LocalStateStore]: real file IO never settles under fake async.
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

/// A notifier that answers the one ask the settings row makes.
class _FakeNotifier extends SystemNotifier {
  @override
  bool get permissionGranted => true;

  @override
  Future<bool> ensurePermissionRequested() async => true;
}

Widget _app(LocalStateStore store) {
  return ProviderScope(
    overrides: [
      backendRegistryStateProvider.overrideWith(
        (ref) => Stream<BackendRegistryState>.value(
          BackendRegistryState(backends: [_laptop], activeId: 'laptop'),
        ),
      ),
      backendConnectionStateProvider.overrideWith(
        (ref, backendId) => Stream<domain.ConnectionState>.value(
          const domain.ConnectionState(phase: domain.ConnectionPhase.connected),
        ),
      ),
      shellRegistryDispatchProvider.overrideWithValue((BackendAction _) {}),
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
      shellThemeSelectProvider.overrideWithValue((ThemePreference _) async {}),
      shellThemeRefreshProvider.overrideWithValue(() async {}),
      appLocalePreferenceProvider.overrideWith(
        (ref) => Stream<AppLocalePreference>.value(AppLocalePreference.system),
      ),
      shellLocaleSelectProvider.overrideWithValue(
        (AppLocalePreference _) async {},
      ),
      systemNotifierProvider.overrideWithValue(_FakeNotifier()),
      localStateStoreProvider.overrideWith((ref) async => store),
      notificationChannelHealthProvider.overrideWith(
        (ref) => Future<NotificationChannelHealth>.value(
          const NotificationChannelHealth(),
        ),
      ),
      openNotificationSettingsProvider.overrideWithValue(
        ({String? channelId}) async {},
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

void main() {
  setUp(ErrorLogCollector.instance.clear);
  tearDown(ErrorLogCollector.instance.clear);

  testWidgets('the About row names the viewer and pushes it', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_MemoryLocalStateStore()));
    await tester.pumpAndSettle();

    const Key rowKey = ValueKey<String>('settingsErrorLogsRow');
    expect(find.byKey(rowKey), findsOneWidget);
    expect(find.text('Error Logs'), findsOneWidget);
    expect(
      find.text('View and export application error logs'),
      findsOneWidget,
      reason: 'the row carries the description as supporting text',
    );

    await tester.tap(find.byKey(rowKey));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorLogViewerScreen), findsOneWidget);
    expect(find.text('No Error Logs'), findsOneWidget);
  });
}
