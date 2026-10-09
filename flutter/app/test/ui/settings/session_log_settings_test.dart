/// Session-log settings tests — the Host-entry controller, the row on the real
/// Settings surface, and the gesture reference that stands in for the pin's
/// shortcut editor.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/backends/backend_store.dart';
import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/local_state/local_state_providers.dart';
import 'package:app/local_state/local_state_store.dart';
import 'package:app/ui/settings/gesture_shortcuts_section.dart';
import 'package:app/ui/settings/session_log_settings.dart';
import 'package:app/ui/settings/settings_screen.dart';
import 'package:app/ui/settings/settings_ui_state.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

/// A settings plane the test owns: one namespace, one field, and a write log.
class _FakeSettingsRepository extends ChatRepository {
  _FakeSettingsRepository({
    this.exposed = true,
    this.writable = true,
    this.refuseWrite = false,
  });

  bool exposed;
  bool writable;
  bool refuseWrite;

  /// The accepted value the fake's describe reports.
  bool enabled = true;
  int revision = 7;

  /// `(ns, field, jsonValue, expectedRevision)` per write.
  final List<(String, String, String, int?)> writes =
      <(String, String, String, int?)>[];

  @override
  Future<SettingsSnapshot> describeSettings() async => SettingsSnapshot(
    writable: writable,
    hasDocument: true,
    namespaces: <SettingsNamespace>[
      if (exposed)
        SettingsNamespace(
          ns: kSessionLogSettingsNs,
          applies: SettingsApplies.live,
          revision: revision,
          hasUserLayer: false,
          secretCount: 0,
          value: <String, Object?>{kSessionLogEnabledField: enabled},
        ),
    ],
    credentialRefs: const <String>[],
  );

  @override
  Future<SettingsNamespace> updateSetting(
    String ns,
    String key,
    String jsonValue, {
    int? expectedRevision,
  }) async {
    writes.add((ns, key, jsonValue, expectedRevision));
    if (refuseWrite) throw StateError('the host refused the write');
    enabled = jsonDecode(jsonValue) as bool;
    revision++;
    return (await describeSettings()).namespaces.first;
  }

  /// Only the settings plane is exercised here; every other verb of the
  /// repository is unreachable from this surface.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRpc implements DshRpcClient {
  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async => RpcResult(ok: true, value: <String, Object?>{});

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

class _QuietSocket implements DshEventSocket {
  final StreamController<ServerRequest> _frames =
      StreamController<ServerRequest>.broadcast();

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    onOpen?.call();
    return _frames.stream;
  }
}

File _storeFile() {
  final Directory directory = Directory.systemTemp.createTempSync(
    'session_log_settings_test',
  );
  addTearDown(() => directory.deleteSync(recursive: true));
  return File('${directory.path}/local_state.json');
}

BackendStore _backendStore() {
  final Directory directory = Directory.systemTemp.createTempSync(
    'session_log_backends_test',
  );
  addTearDown(() => directory.deleteSync(recursive: true));
  return BackendStore(
    File('${directory.path}/backends.json'),
    seedBaseUrl: kDshBaseUrl,
  );
}

/// Pumps the real Settings surface over [repository].
Future<void> _pumpSettings(
  WidgetTester tester,
  _FakeSettingsRepository repository, {
  bool openGestures = false,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // The row is per active backend; pin the id so the fake's repository is
        // the one it describes.
        activeBackendIdProvider.overrideWith((Ref ref) async* {
          yield 'default';
        }),
        chatRepositoryProvider('default').overrideWithValue(repository),
        localStateStoreProvider.overrideWith(
          (Ref ref) async => LocalStateStore(_storeFile()),
        ),
        backendStoreProvider.overrideWith((Ref ref) async => _backendStore()),
        dshRpcClientProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_FakeRpc()),
        dshEventSocketProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_QuietSocket()),
      ],
      child: l10nApp(
        home: SettingsScreen(
          uiState: const SettingsUiState(),
          onAction: (SettingsAction _) {},
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  if (openGestures) {
    await tester.tap(find.text('Gestures'));
    await tester.pumpAndSettle();
  }
}

Future<void> _settleDescribe(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('session-log upload row', () {
    testWidgets('is absent when the host does not serve the entry', (
      tester,
    ) async {
      final repository = _FakeSettingsRepository(exposed: false);
      await _pumpSettings(tester, repository);
      await _settleDescribe(tester);

      expect(
        find.text('Upload Session Log when using the official model API'),
        findsNothing,
      );
      expect(repository.writes, isEmpty);
    });

    testWidgets('shows the accepted value and writes the field with its '
        'revision', (tester) async {
      final repository = _FakeSettingsRepository();
      await _pumpSettings(tester, repository);
      await _settleDescribe(tester);

      expect(
        find.text('Upload Session Log when using the official model API'),
        findsOneWidget,
      );
      expect(
        find.text('Help improve DeepSeek models and products.'),
        findsOneWidget,
      );
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await tester.tap(find.byType(Switch));
      await _settleDescribe(tester);

      // The pin's `form.set('enabled', …)` under the described revision
      // (`upload-preference.ts:33-46`, `config-form.ts:139`).
      expect(repository.writes, <(String, String, String, int?)>[
        (kSessionLogSettingsNs, kSessionLogEnabledField, 'false', 7),
      ]);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('a refused write keeps the accepted value and says so', (
      tester,
    ) async {
      final repository = _FakeSettingsRepository(refuseWrite: true);
      await _pumpSettings(tester, repository);
      await _settleDescribe(tester);

      await tester.tap(find.byType(Switch));
      await _settleDescribe(tester);

      expect(repository.writes, hasLength(1));
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(find.text("Couldn't save the preference"), findsOneWidget);
    });

    testWidgets('is inert when the host refuses writes', (tester) async {
      final repository = _FakeSettingsRepository(writable: false);
      await _pumpSettings(tester, repository);
      await _settleDescribe(tester);

      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      await tester.tap(find.byType(Switch));
      await _settleDescribe(tester);
      expect(repository.writes, isEmpty);
    });
  });

  group('gesture reference', () {
    testWidgets('the Settings entry opens the list of real gestures', (
      tester,
    ) async {
      await _pumpSettings(
        tester,
        _FakeSettingsRepository(exposed: false),
        openGestures: true,
      );

      expect(find.byType(SettingsGesturesPage), findsOneWidget);
      // Every row is an interaction this client implements.
      expect(find.text('Long-press a message'), findsOneWidget);
      expect(
        find.text('Copy it, or fork the conversation from it.'),
        findsOneWidget,
      );
      expect(find.text('Long-press a session row'), findsOneWidget);
      expect(find.text('Long-press a project header'), findsOneWidget);
      expect(find.text('Hold the microphone'), findsOneWidget);
      expect(find.text('Scroll to the top of the transcript'), findsOneWidget);
      // And the editor half is stated as absent, not faked.
      expect(
        find.text(
          'Recording or remapping key bindings belongs to the desktop app.',
        ),
        findsOneWidget,
      );
      expect(find.byType(Switch), findsNothing);
    });
  });
}
