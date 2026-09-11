/// SettingsScreen widget tests — modern grouped section cards layout.
library;

import 'dart:async';
import 'dart:io';

import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/backends/backend_store.dart';
import 'package:app/config.dart';
import 'package:app/di/dsh_reachability.dart';
import 'package:app/di/providers.dart';
import 'package:app/local_state/local_state_providers.dart';
import 'package:app/local_state/local_state_store.dart';
import 'package:app/ui/settings/busy_enter_preference.dart';
import 'package:app/ui/settings/locale_preference.dart';
import 'package:app/ui/settings/settings_controller.dart';
import 'package:app/ui/settings/settings_screen.dart';
import 'package:app/ui/settings/settings_ui_state.dart';
import 'package:app/ui/shared/state_dot.dart';

import '../../l10n_app.dart';

const SettingsSnapshot _snapshot = SettingsSnapshot(
  writable: true,
  hasDocument: true,
  namespaces: <SettingsNamespace>[
    SettingsNamespace(
      ns: 'llm-deepseek',
      applies: SettingsApplies.live,
      revision: 3,
      hasUserLayer: true,
      secretCount: 1,
    ),
    SettingsNamespace(
      ns: 'shell',
      applies: SettingsApplies.restart,
      revision: 0,
      hasUserLayer: false,
      secretCount: 0,
    ),
  ],
  credentialRefs: <String>['DEEPSEEK_API_KEY'],
);

const List<CredentialStatus> _credentials = <CredentialStatus>[
  CredentialStatus(
    ref: 'DEEPSEEK_API_KEY',
    configured: true,
    source: 'file',
    writable: true,
  ),
];

const AgentPresetRoster _roster = AgentPresetRoster(
  entries: <AgentPresetEntry>[
    AgentPresetEntry(
      id: 'standard',
      trust: AgentPresetTrust.system,
      isDefault: true,
      description: 'Full coding agent with file editing, shell, and search.',
    ),
    AgentPresetEntry(id: 'code', trust: AgentPresetTrust.system),
    AgentPresetEntry(id: 'minimal', trust: AgentPresetTrust.system),
    AgentPresetEntry(
      id: 'my-agent',
      trust: AgentPresetTrust.user,
      name: 'My Agent',
      broken: 'agent.cordis.yml not found',
    ),
  ],
);

File _storeFile() {
  final Directory directory = Directory.systemTemp.createTempSync(
    'settings_test',
  );
  addTearDown(() => directory.deleteSync(recursive: true));
  return File('${directory.path}/local_state.json');
}

class _FakeRpc implements DshRpcClient {
  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async {
    return RpcResult(ok: true, value: <String, Object?>{});
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

/// The `$events` registration answer the gateway sends over
/// `/api/remote.mux`
/// (`reference/deepseek-harness/packages/api/gateway/src/stream-protocol.ts`
/// `RemoteEventReadyFrame`); it is the connection generation handshake.
ServerRequest _readyFrame() => ServerRequest(
  rpcId: 'remote-events',
  method: 'item',
  payload: <String, Object?>{
    'type': 'ready',
    'clientId': 'client-1',
    'host': <String, Object?>{'home': '/home/tester'},
  },
);

class _QuietSocket implements DshEventSocket {
  final StreamController<ServerRequest> _frames =
      StreamController<ServerRequest>.broadcast();

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    onOpen?.call();
    // A broadcast controller drops events with no listener; the handshake
    // frame therefore lands after this call's listener attaches.
    scheduleMicrotask(() => _frames.add(_readyFrame()));
    return _frames.stream;
  }
}

/// An RPC stub for the reachability probe: the sheet's "Test connection"
/// never touches a socket in these tests.
class _ProbeRpc implements DshRpcClient {
  _ProbeRpc(this._respond);

  final Future<RpcResult> Function() _respond;

  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) => _respond();

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

DshReachabilityProbe _probeReturning(Future<RpcResult> Function() respond) {
  final _ProbeRpc client = _ProbeRpc(respond);
  return DshReachabilityProbe(
    transportFactory: (Uri baseUri, {required bool trustHostCertificate}) =>
        DshProbeTransport(client),
  );
}

/// The probe most tests get: reports an unreachable host without opening a
/// socket, so only the tests that drive "Test connection" observe anything.
DshReachabilityProbe _unreachableProbe() => _probeReturning(() async {
  throw DshTransportException(
    'transport failure for api/settings/describe',
    const SocketException('Connection refused'),
  );
});

BackendStore _backendStore({String? document}) {
  final Directory dir = Directory.systemTemp.createTempSync(
    'settings_backends_test',
  );
  addTearDown(() async {
    for (int i = 0; i < 50; i++) {
      try {
        dir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  });
  final File file = File('${dir.path}/backends.json');
  if (document != null) {
    file.writeAsStringSync(document);
  }
  return BackendStore(file, seedBaseUrl: kDshBaseUrl);
}

/// Pumps real IO forward until [finder] matches, or fails after [timeout].
///
/// The registry load and every persist are real file IO, which a widget test's
/// fake-async zone does not advance on its own. A fixed delay was the old
/// budget here and it flaked under a loaded runner; waiting on the condition
/// returns as soon as the tree is ready and only fails when it never is.
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('timed out after $timeout waiting for $finder');
}

Future<void> _letRegistryLoad(WidgetTester tester) async {
  // A bounded real-IO pump for the async load. No single finder is present in
  // every configuration, so the interaction helpers wait on their own target
  // (`openHostSheet` on the host label) rather than this gating on one.
  for (int i = 0; i < 40; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
  }
}

Future<LocalStateStore> _pump(
  WidgetTester tester,
  SettingsUiState uiState,
  List<SettingsAction> actions,
) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final LocalStateStore store = LocalStateStore(_storeFile());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStateStoreProvider.overrideWith((Ref ref) async => store),
        backendStoreProvider.overrideWith((Ref ref) async => _backendStore()),
        dshRpcClientProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_FakeRpc()),
        dshEventSocketProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_QuietSocket()),
      ],
      child: l10nApp(
        home: SettingsScreen(uiState: uiState, onAction: actions.add),
      ),
    ),
  );
  await tester.pump();
  return store;
}

class _ControllerHarness extends StatelessWidget {
  const _ControllerHarness({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SettingsUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder: (BuildContext context, AsyncSnapshot<SettingsUiState> snapshot) {
        final SettingsUiState uiState =
            snapshot.data ?? const SettingsUiState();
        return SettingsScreen(uiState: uiState, onAction: controller.onAction);
      },
    );
  }
}

Future<LocalStateStore> _pumpController(
  WidgetTester tester,
  SettingsController controller,
) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final LocalStateStore store = LocalStateStore(_storeFile());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStateStoreProvider.overrideWith((Ref ref) async => store),
        backendStoreProvider.overrideWith((Ref ref) async => _backendStore()),
        dshRpcClientProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_FakeRpc()),
        dshEventSocketProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_QuietSocket()),
      ],
      child: l10nApp(home: _ControllerHarness(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

class _RecordingSettingsRepository implements ChatRepository {
  _RecordingSettingsRepository({required this.snapshot, required this.roster});

  final SettingsSnapshot snapshot;
  final AgentPresetRoster roster;

  final List<(String, String, String, int?)> updateCalls =
      <(String, String, String, int?)>[];

  @override
  Future<SettingsSnapshot> describeSettings() async => snapshot;

  @override
  Future<AgentPresetRoster> listAgentPresets() async => roster;

  @override
  Future<List<CredentialStatus>> describeCredentials(List<String> refs) async =>
      const <CredentialStatus>[];

  @override
  Future<SettingsNamespace> updateSetting(
    String ns,
    String key,
    String jsonValue, {
    int? expectedRevision,
  }) async {
    updateCalls.add((ns, key, jsonValue, expectedRevision));
    return snapshot.namespaces.firstWhere(
      (SettingsNamespace namespace) => namespace.ns == ns,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

void main() {
  testWidgets(
    'renders grouped sections with host, app preferences, chat, models, and plugins',
    (WidgetTester tester) async {
      await _pump(
        tester,
        const SettingsUiState(
          snapshot: _snapshot,
          credentials: _credentials,
          roster: _roster,
        ),
        <SettingsAction>[],
      );

      // Section titles are visible on the unified page
      expect(find.text('Host & connection'), findsOneWidget);
      expect(find.text('App preferences'), findsOneWidget);
      expect(find.text('Chat & agent'), findsOneWidget);
      expect(find.text('Models & credentials'), findsOneWidget);
      expect(find.text('Plugins & advanced'), findsOneWidget);

      // Host & connection section
      expect(find.text('Host writes'), findsOneWidget);
      expect(find.text('Settings document'), findsOneWidget);

      // App preferences section
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Follow system'), findsOneWidget);
      expect(find.text('中文'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);

      // Chat & agent section
      expect(find.text('Enter behavior while busy'), findsOneWidget);
      expect(find.text('Queue'), findsOneWidget);
      expect(find.text('Steer'), findsOneWidget);
      expect(find.text('Agent preset'), findsOneWidget);
      expect(find.text('Standard mode'), findsWidgets);
      expect(find.text('In use'), findsOneWidget);
      expect(find.text('Built-in'), findsOneWidget);
      expect(find.text('Custom'), findsNWidgets(2));

      // Models & credentials section
      expect(find.text('DeepSeek'), findsOneWidget);
      expect(find.text('API key configured'), findsOneWidget);

      // Plugins section
      expect(find.text('llm-deepseek'), findsOneWidget);
      expect(
        find.text('applies: live · revision: 3 · user layer · 1 secret set'),
        findsOneWidget,
      );
    },
  );

  testWidgets('enter behavior row persists through the store', (
    WidgetTester tester,
  ) async {
    final LocalStateStore store = await _pump(
      tester,
      const SettingsUiState(snapshot: _snapshot),
      <SettingsAction>[],
    );

    expect(store.read(kBusyEnterBehaviorKey), isNull);

    await tester.tap(find.text('Steer'));
    await tester.pump();

    expect(store.read(kBusyEnterBehaviorKey), 'steer');
    expect(BusyEnterPreferenceController(store).state, BusyEnterBehavior.steer);

    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('language row persists and seeds the locale controller', (
    WidgetTester tester,
  ) async {
    final LocalStateStore store = await _pump(
      tester,
      const SettingsUiState(snapshot: _snapshot),
      <SettingsAction>[],
    );

    expect(find.text('Follow system'), findsOneWidget);
    expect(find.text('中文'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);

    expect(store.read(kAppLocalePreferenceKey), isNull);

    await tester.tap(find.text('中文'));
    await tester.pump();

    expect(store.read(kAppLocalePreferenceKey), 'zh');

    final LocalePreferenceController controller = LocalePreferenceController(
      store,
    );
    expect(controller.state, AppLocalePreference.zh);
    expect(resolveAppLocale(controller.state), const Locale('zh'));
    expect(resolveAppLocale(AppLocalePreference.system), isNull);
    addTearDown(controller.dispose);

    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets(
    'agent preset row picks from the roster and writes the settings default',
    (WidgetTester tester) async {
      final _RecordingSettingsRepository repository =
          _RecordingSettingsRepository(
            snapshot: const SettingsSnapshot(
              writable: true,
              hasDocument: true,
              namespaces: <SettingsNamespace>[
                SettingsNamespace(
                  ns: 'agent-presets',
                  applies: SettingsApplies.live,
                  revision: 3,
                  hasUserLayer: true,
                  secretCount: 0,
                ),
              ],
              credentialRefs: <String>[],
            ),
            roster: _roster,
          );
      final SettingsController controller = SettingsController(repository);
      addTearDown(controller.dispose);
      await _pumpController(tester, controller);

      expect(find.text('Agent preset'), findsOneWidget);

      await tester.tap(find.text('Agent preset'));
      await tester.pumpAndSettle();

      final Finder sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(of: sheet, matching: find.text('Code mode')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Minimal mode')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('My Agent')),
        findsNothing,
      );

      await tester.tap(
        find.descendant(of: sheet, matching: find.text('Code mode')),
      );
      await tester.pumpAndSettle();

      expect(repository.updateCalls, <(String, String, String, int?)>[
        ('agent-presets', 'default', '"code"', 3),
      ]);
    },
  );

  testWidgets(
    'presets section renders the roster cards and switches the default',
    (WidgetTester tester) async {
      final List<SettingsAction> actions = <SettingsAction>[];
      await _pump(
        tester,
        const SettingsUiState(snapshot: _snapshot, roster: _roster),
        actions,
      );

      expect(find.text('Built-in'), findsOneWidget);
      expect(find.text('Custom'), findsNWidgets(2));
      expect(find.text('In use'), findsOneWidget);
      expect(find.text('My Agent'), findsOneWidget);
      expect(find.text('Failed to load'), findsOneWidget);
      expect(find.text('agent.cordis.yml not found'), findsOneWidget);
      expect(find.text('my-agent'), findsOneWidget);

      await tester.tap(find.text('Minimal mode'));
      await tester.pumpAndSettle();
      expect(
        actions,
        contains(const SelectAgentPresetDefaultAction('minimal')),
      );
    },
  );

  testWidgets('empty roster renders only the presets footnote', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const SettingsUiState(snapshot: _snapshot, roster: AgentPresetRoster()),
      <SettingsAction>[],
    );

    expect(find.text('Agent preset'), findsNothing);
    expect(find.textContaining('authored on the host'), findsOneWidget);
    expect(find.text('Built-in'), findsNothing);
  });

  testWidgets(
    'models section shows the DeepSeek key card and opens the editor',
    (WidgetTester tester) async {
      final List<SettingsAction> actions = <SettingsAction>[];
      await _pump(
        tester,
        const SettingsUiState(snapshot: _snapshot, credentials: _credentials),
        actions,
      );

      expect(find.text('DeepSeek'), findsOneWidget);
      expect(find.text('API key configured'), findsOneWidget);
      expect(find.text('Configured'), findsOneWidget);
      expect(
        find.textContaining('the Providers section below'),
        findsOneWidget,
      );

      await tester.tap(find.text('DeepSeek'));
      await tester.pumpAndSettle();
      expect(find.text('Store DEEPSEEK_API_KEY'), findsOneWidget);
    },
  );

  testWidgets('error shows the loopback hint and dismisses', (
    WidgetTester tester,
  ) async {
    final List<SettingsAction> actions = <SettingsAction>[];
    await _pump(
      tester,
      const SettingsUiState(errorMessage: 'describe failed'),
      actions,
    );
    expect(find.text('describe failed'), findsOneWidget);
    expect(find.textContaining('loopback-only'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(actions, contains(const DismissSettingsError()));
  });

  testWidgets('key patch form dispatches UpdateSettingAction', (
    WidgetTester tester,
  ) async {
    final List<SettingsAction> actions = <SettingsAction>[];
    await _pump(tester, const SettingsUiState(snapshot: _snapshot), actions);

    await tester.tap(find.text('llm-deepseek'));
    await tester.pumpAndSettle();

    expect(find.text('Patch key'), findsOneWidget);
    expect(find.text('Replace section'), findsOneWidget);
    expect(find.textContaining('CAS revision 3'), findsOneWidget);

    final Finder keyField = find.byWidgetPredicate(
      (Widget w) => w is TextField && w.decoration?.hintText == null,
    );
    final Finder valueField = find.byWidgetPredicate(
      (Widget w) =>
          w is TextField &&
          w.decoration?.hintText == 'true / 42 / "text" / {…}',
    );
    await tester.enterText(keyField, 'model');
    await tester.enterText(valueField, '"glm-x"');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      actions,
      contains(
        const UpdateSettingAction(
          ns: 'llm-deepseek',
          key: 'model',
          jsonValue: '"glm-x"',
          expectedRevision: 3,
        ),
      ),
    );
  });

  testWidgets('replace-section mode dispatches ReplaceSettingAction', (
    WidgetTester tester,
  ) async {
    final List<SettingsAction> actions = <SettingsAction>[];
    await _pump(tester, const SettingsUiState(snapshot: _snapshot), actions);

    await tester.tap(find.text('llm-deepseek'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace section'));
    await tester.pump();
    expect(find.text('Patch key'), findsOneWidget);

    final Finder replaceField = find.byWidgetPredicate(
      (Widget w) =>
          w is TextField && w.decoration?.hintText == '{ "key": value }',
    );
    await tester.enterText(replaceField, '{ "model": "glm-x" }');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      actions,
      contains(
        const ReplaceSettingAction(
          ns: 'llm-deepseek',
          sectionJson: '{ "model": "glm-x" }',
          expectedRevision: 3,
        ),
      ),
    );
  });

  testWidgets('credential sheet set/unset dispatch', (
    WidgetTester tester,
  ) async {
    final List<SettingsAction> actions = <SettingsAction>[];
    await _pump(
      tester,
      const SettingsUiState(snapshot: _snapshot, credentials: _credentials),
      actions,
    );

    await tester.tap(find.text('DeepSeek'));
    await tester.pumpAndSettle();
    expect(find.text('Store DEEPSEEK_API_KEY'), findsOneWidget);

    final Finder secretField = find.byWidgetPredicate(
      (Widget w) => w is TextField && w.decoration?.hintText == 'secret value',
    );
    await tester.enterText(secretField, 'sk-test');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      actions,
      contains(const SetCredentialAction('DEEPSEEK_API_KEY', 'sk-test')),
    );

    actions.clear();
    await tester.tap(find.text('DeepSeek'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unset'));
    await tester.pump();
    expect(actions, contains(const UnsetCredentialAction('DEEPSEEK_API_KEY')));
  });

  testWidgets('read-only snapshot hides edit affordances', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const SettingsUiState(
        snapshot: SettingsSnapshot(
          writable: false,
          hasDocument: false,
          namespaces: <SettingsNamespace>[
            SettingsNamespace(
              ns: 'shell',
              applies: SettingsApplies.restart,
              revision: 0,
              hasUserLayer: false,
              secretCount: 0,
            ),
          ],
          credentialRefs: <String>[],
        ),
        roster: _roster,
      ),
      <SettingsAction>[],
    );

    expect(find.text('Read-only'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);

    await tester.tap(find.text('Agent preset'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);

    await tester.tap(find.text('shell'));
    await tester.pumpAndSettle();
    expect(find.text('Patch key'), findsNothing);
    expect(
      find.text(
        'Host is read-only on this connection; namespace edits are unavailable.',
      ),
      findsOneWidget,
    );

    expect(
      find.text('The settings document is read-only in this deployment.'),
      findsOneWidget,
    );

    expect(find.text('No credentials referenced.'), findsOneWidget);
  });

  const String twoBackendsDoc =
      '{"backends": ['
      '{"id": "default", "label": "Laptop", "baseUrl": "http://10.0.2.2:3080"},'
      '{"id": "b1", "label": "Build box", "baseUrl": "http://10.0.2.2:3081"}'
      '], "activeId": "default"}';

  Future<void> pumpHostSettings(
    WidgetTester tester, {
    String document = twoBackendsDoc,
    SettingsUiState uiState = const SettingsUiState(snapshot: _snapshot),
    Locale? locale,
    DshReachabilityProbe? probe,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendStoreProvider.overrideWith(
            (Ref ref) async => _backendStore(document: document),
          ),
          dshReachabilityProbeProvider.overrideWithValue(
            probe ?? _unreachableProbe(),
          ),
          for (final Uri uri in <Uri>[
            Uri.parse(kDshBaseUrl),
            Uri.parse('http://10.0.2.2:3080'),
            Uri.parse('http://10.0.2.2:3081'),
            Uri.parse('http://10.0.2.2:3082'),
          ]) ...[
            dshRpcClientProvider(uri).overrideWithValue(_FakeRpc()),
            dshEventSocketProvider(uri).overrideWithValue(_QuietSocket()),
          ],
          localStateStoreProvider.overrideWith(
            (Ref ref) async => LocalStateStore(_storeFile()),
          ),
        ],
        child: l10nApp(
          locale: locale,
          home: SettingsScreen(
            uiState: uiState,
            onAction: (SettingsAction _) {},
          ),
        ),
      ),
    );
    await _letRegistryLoad(tester);
    await tester.pumpAndSettle();
  }

  Future<void> openHostSheet(WidgetTester tester, String barLabel) async {
    await _pumpUntil(tester, find.text(barLabel).hitTestable());
    await tester.tap(find.text(barLabel).hitTestable().first);
    await tester.pumpAndSettle();
  }

  testWidgets('host sheet lists hosts and switches the chat-active one', (
    WidgetTester tester,
  ) async {
    await pumpHostSettings(tester);
    expect(find.text('Laptop').hitTestable(), findsOneWidget);
    await openHostSheet(tester, 'Laptop');

    final Finder sheet = find.byType(BottomSheet);
    expect(
      find.descendant(of: sheet, matching: find.text('Choose a host')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Build box')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Add host')),
      findsOneWidget,
    );
    // No pinned route publishes a host version, so the row subtitle is the
    // endpoint alone — never a fabricated version.
    expect(
      find.descendant(of: sheet, matching: find.text('10.0.2.2:3080')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('10.0.2.2:3081')),
      findsOneWidget,
    );

    final Finder laptopRow = find.ancestor(
      of: find.descendant(of: sheet, matching: find.text('Laptop')),
      matching: find.byType(InkWell),
    );
    expect(
      find.descendant(of: laptopRow, matching: find.text('Active')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: laptopRow, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Edit host').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set as chat host'));
    await tester.pumpAndSettle();

    final Finder buildBoxRow = find.ancestor(
      of: find.descendant(of: sheet, matching: find.text('Build box')),
      matching: find.byType(InkWell),
    );
    expect(
      find.descendant(of: buildBoxRow, matching: find.text('Active')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: laptopRow, matching: find.text('Active')),
      findsNothing,
    );
  });

  testWidgets('host sheet pins a scope independent of the chat-active host', (
    WidgetTester tester,
  ) async {
    await pumpHostSettings(tester);
    await openHostSheet(tester, 'Laptop');

    expect(find.text('Follow the active host'), findsNothing);

    await tester.tap(find.text('Build box').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Build box').hitTestable(), findsOneWidget);
    expect(find.text('Laptop').hitTestable(), findsNothing);

    await openHostSheet(tester, 'Build box');
    await tester.tap(find.byTooltip('Edit host').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set as chat host'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit host').at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set as chat host'));
    await tester.pumpAndSettle();

    final Finder laptopRow = find.ancestor(
      of: find.text('Laptop'),
      matching: find.byType(InkWell),
    );
    expect(
      find.descendant(of: laptopRow, matching: find.text('Active')),
      findsOneWidget,
    );
    final Finder buildBoxRow = find.ancestor(
      of: find.text('Build box'),
      matching: find.byType(InkWell),
    );
    expect(
      find.descendant(of: buildBoxRow, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: laptopRow, matching: find.byIcon(Icons.check)),
      findsNothing,
    );

    expect(find.text('Follow the active host'), findsOneWidget);
    await tester.tap(find.text('Follow the active host'));
    await tester.pumpAndSettle();
    expect(find.text('Laptop').hitTestable(), findsOneWidget);
  });

  testWidgets('a single configured host keeps the bar and sheet minimal', (
    WidgetTester tester,
  ) async {
    await pumpHostSettings(
      tester,
      document:
          '{"backends": [{"id": "default", "label": "Laptop", '
          '"baseUrl": "http://10.0.2.2:3080"}], "activeId": "default"}',
    );

    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.textContaining('10.0.2.2:3080'), findsOneWidget);

    await openHostSheet(tester, 'Laptop');
    expect(find.text('Choose a host'), findsOneWidget);
    expect(find.text('Follow the active host'), findsNothing);
    expect(find.text('Add host'), findsOneWidget);
  });

  testWidgets('SettingsRoute rebinds the described host to the scoped host', (
    WidgetTester tester,
  ) async {
    final _RecordingSettingsRepository laptop = _RecordingSettingsRepository(
      snapshot: _snapshot,
      roster: _roster,
    );
    final _RecordingSettingsRepository buildBox = _RecordingSettingsRepository(
      snapshot: const SettingsSnapshot(
        writable: false,
        hasDocument: false,
        namespaces: <SettingsNamespace>[],
        credentialRefs: <String>[],
      ),
      roster: const AgentPresetRoster(),
    );
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendStoreProvider.overrideWith(
            (Ref ref) async => _backendStore(document: twoBackendsDoc),
          ),
          chatRepositoryProvider('default').overrideWithValue(laptop),
          chatRepositoryProvider('b1').overrideWithValue(buildBox),
          for (final Uri uri in <Uri>[
            Uri.parse('http://10.0.2.2:3080'),
            Uri.parse('http://10.0.2.2:3081'),
          ]) ...[
            dshRpcClientProvider(uri).overrideWithValue(_FakeRpc()),
            dshEventSocketProvider(uri).overrideWithValue(_QuietSocket()),
          ],
          localStateStoreProvider.overrideWith(
            (Ref ref) async => LocalStateStore(_storeFile()),
          ),
        ],
        child: l10nApp(home: const SettingsRoute()),
      ),
    );
    await _letRegistryLoad(tester);
    await tester.pumpAndSettle();

    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Writable'), findsOneWidget);

    await tester.tap(find.text('Laptop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build box').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Build box'), findsOneWidget);
    expect(find.text('Read-only'), findsOneWidget);
    expect(find.text('Writable'), findsNothing);

    await tester.tap(find.text('Build box'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Follow the active host'));
    await tester.pumpAndSettle();
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Writable'), findsOneWidget);
  });

  testWidgets('add host flow appends through the registry', (
    WidgetTester tester,
  ) async {
    await pumpHostSettings(tester);
    await openHostSheet(tester, 'Laptop');

    await tester.tap(find.text('Add host').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Label'), findsOneWidget);
    expect(find.text('Base URL'), findsOneWidget);

    final Finder fields = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'CI host');
    await tester.pump();
    await tester.enterText(fields.at(1), 'http://10.0.2.2:3082');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Label'), findsNothing);
    expect(find.text('CI host'), findsOneWidget);
    expect(find.textContaining('10.0.2.2:3082'), findsOneWidget);
  });

  testWidgets('edit sheet repoints a host and states removal guards', (
    WidgetTester tester,
  ) async {
    await pumpHostSettings(tester);
    await openHostSheet(tester, 'Laptop');

    await tester.tap(find.byTooltip('Edit host').at(1));
    await tester.pumpAndSettle();
    expect(find.text('Edit host'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);

    final Finder fields = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(1), 'http://10.0.2.2:3082');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('10.0.2.2:3082'), findsOneWidget);
    expect(find.textContaining('10.0.2.2:3081'), findsNothing);

    await tester.tap(find.byTooltip('Edit host').at(0));
    await tester.pumpAndSettle();
    expect(find.text('Remove'), findsNothing);
    expect(find.textContaining('Switch away before removing'), findsOneWidget);
  });

  testWidgets('trusting a host certificate is an explicit edit-sheet opt-in', (
    WidgetTester tester,
  ) async {
    await pumpHostSettings(tester);
    await openHostSheet(tester, 'Laptop');

    await tester.tap(find.byTooltip('Edit host').at(1));
    await tester.pumpAndSettle();

    final Finder trustSwitch = find.widgetWithText(
      SwitchListTile,
      "Trust this host's certificate",
    );
    expect(trustSwitch, findsOneWidget);
    expect(tester.widget<SwitchListTile>(trustSwitch).value, isFalse);
    expect(find.textContaining('could impersonate it'), findsOneWidget);

    await tester.tap(trustSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(trustSwitch).value, isTrue);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // The opt-in persists through the registry, so reopening the sheet
    // shows it already on.
    await tester.tap(find.byTooltip('Edit host').at(1));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(
              SwitchListTile,
              "Trust this host's certificate",
            ),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('host sheet tests a connection: in progress, then classified', (
    WidgetTester tester,
  ) async {
    final Completer<RpcResult> pending = Completer<RpcResult>();
    await pumpHostSettings(
      tester,
      probe: _probeReturning(() => pending.future),
    );
    await openHostSheet(tester, 'Laptop');

    await tester.tap(find.byTooltip('Edit host').at(1));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Test connection'));
    await tester.pump();

    // Bounded in-progress state while the probe is in flight.
    expect(find.text('Testing connection…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete(RpcResult(ok: true, value: <String, Object?>{}));
    await tester.pumpAndSettle();

    expect(find.text('Testing connection…'), findsNothing);
    expect(
      find.text('Reachable. The host answered the dsh contract.'),
      findsOneWidget,
    );
  });

  testWidgets('a failed connection test does not block saving the host', (
    WidgetTester tester,
  ) async {
    await pumpHostSettings(tester);
    await openHostSheet(tester, 'Laptop');

    await tester.tap(find.byTooltip('Edit host').at(1));
    await tester.pumpAndSettle();

    final Finder fields = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(1), 'http://10.0.2.2:3082');
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Test connection'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No dsh answered at this address'),
      findsOneWidget,
    );
    expect(find.textContaining('Saving is not blocked'), findsOneWidget);

    // The failed probe never gates the save.
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('10.0.2.2:3082'), findsOneWidget);
    expect(find.text('Base URL'), findsNothing);
  });

  testWidgets('editing the address clears a stale reachability outcome', (
    WidgetTester tester,
  ) async {
    await pumpHostSettings(tester);
    await openHostSheet(tester, 'Laptop');

    await tester.tap(find.byTooltip('Edit host').at(1));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Test connection'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No dsh answered at this address'),
      findsOneWidget,
    );

    // A different address must not keep showing the old address's verdict.
    final Finder fields = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(1), 'http://10.0.2.2:3099');
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No dsh answered at this address'),
      findsNothing,
    );
  });

  testWidgets('unreachable host card opens the host sheet', (
    WidgetTester tester,
  ) async {
    await pumpHostSettings(tester, uiState: const SettingsUiState());

    expect(find.text('Host settings unavailable'), findsOneWidget);
    expect(find.textContaining('The host did not answer'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Host'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a host'), findsOneWidget);
    expect(find.text('Add host').hitTestable(), findsOneWidget);
  });

  testWidgets('settings screen app preferences section includes ASR entry', (
    WidgetTester tester,
  ) async {
    await pumpHostSettings(tester);

    expect(find.text('ASR Models'), findsOneWidget);
    expect(
      find.textContaining(
        'Download and manage on-device speech recognition models',
      ),
      findsOneWidget,
    );
  });

  testWidgets('host switch disables the active host and relocates Active', (
    WidgetTester tester,
  ) async {
    await pumpHostSettings(tester);
    await openHostSheet(tester, 'Laptop');

    final Finder sheet = find.byType(BottomSheet);
    final Finder switches = find.descendant(
      of: sheet,
      matching: find.byType(Switch),
    );
    expect(switches, findsNWidgets(2));
    expect(tester.widget<Switch>(switches.at(0)).value, isTrue);

    // Switch the active (Laptop) row off: its connection verb lands on
    // the build box, its row states the disabled badge without an
    // error, and no registry refusal rides the sheet.
    await tester.tap(switches.at(0));
    await tester.pumpAndSettle();

    final Finder laptopRow = find.ancestor(
      of: find.descendant(of: sheet, matching: find.text('Laptop')),
      matching: find.byType(InkWell),
    );
    final Finder buildBoxRow = find.ancestor(
      of: find.descendant(of: sheet, matching: find.text('Build box')),
      matching: find.byType(InkWell),
    );
    expect(
      find.descendant(of: laptopRow, matching: find.text('Disabled')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: laptopRow, matching: find.text('Active')),
      findsNothing,
    );
    expect(
      find.descendant(of: buildBoxRow, matching: find.text('Active')),
      findsOneWidget,
    );
    expect(tester.widget<Switch>(switches.at(0)).value, isFalse);
    expect(
      find.descendant(of: sheet, matching: find.byIcon(Icons.error_outline)),
      findsNothing,
    );
    // The disabled row's dot is the neutral "off by choice" state.
    expect(
      find.descendant(
        of: laptopRow,
        matching: find.byWidgetPredicate(
          (Widget w) => w is StateDot && w.state == StateDotState.disabled,
        ),
      ),
      findsOneWidget,
    );
    // The edit verbs stay in place: both rows keep their pencil.
    expect(find.byTooltip('Edit host'), findsNWidgets(2));

    // Re-enabling does not steal the active seat back.
    await tester.tap(switches.at(0));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.at(0)).value, isTrue);
    expect(
      find.descendant(of: buildBoxRow, matching: find.text('Active')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: laptopRow, matching: find.text('Active')),
      findsNothing,
    );
  });

  testWidgets(
    'a disabled host is inert to scope taps and hides Set as chat host',
    (WidgetTester tester) async {
      await pumpHostSettings(tester);
      await openHostSheet(tester, 'Laptop');

      final Finder sheet = find.byType(BottomSheet);
      final Finder switches = find.descendant(
        of: sheet,
        matching: find.byType(Switch),
      );
      // Disable the standby (Build box) row; Laptop keeps active and
      // scope.
      await tester.tap(switches.at(1));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(of: sheet, matching: find.text('Build box')),
      );
      await tester.pumpAndSettle();
      // The disabled row cannot pin the settings scope: the sheet is
      // still open and the check stays on the Laptop row.
      expect(find.byType(BottomSheet), findsOneWidget);
      final Finder laptopRow = find.ancestor(
        of: find.descendant(of: sheet, matching: find.text('Laptop')),
        matching: find.byType(InkWell),
      );
      expect(
        find.descendant(of: laptopRow, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );

      // Its edit sheet offers removal but never the chat-host switch.
      await tester.tap(find.byTooltip('Edit host').at(1));
      await tester.pumpAndSettle();
      expect(find.text('Set as chat host'), findsNothing);
      expect(find.text('Remove'), findsOneWidget);
    },
  );

  testWidgets('disabling every host leaves the manage sheet reachable from the '
      'fallback card', (WidgetTester tester) async {
    final _RecordingSettingsRepository laptop = _RecordingSettingsRepository(
      snapshot: _snapshot,
      roster: _roster,
    );
    final _RecordingSettingsRepository buildBox = _RecordingSettingsRepository(
      snapshot: const SettingsSnapshot(
        writable: false,
        hasDocument: false,
        namespaces: <SettingsNamespace>[],
        credentialRefs: <String>[],
      ),
      roster: const AgentPresetRoster(),
    );
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendStoreProvider.overrideWith(
            (Ref ref) async => _backendStore(document: twoBackendsDoc),
          ),
          chatRepositoryProvider('default').overrideWithValue(laptop),
          chatRepositoryProvider('b1').overrideWithValue(buildBox),
          for (final Uri uri in <Uri>[
            Uri.parse('http://10.0.2.2:3080'),
            Uri.parse('http://10.0.2.2:3081'),
          ]) ...[
            dshRpcClientProvider(uri).overrideWithValue(_FakeRpc()),
            dshEventSocketProvider(uri).overrideWithValue(_QuietSocket()),
          ],
          localStateStoreProvider.overrideWith(
            (Ref ref) async => LocalStateStore(_storeFile()),
          ),
        ],
        child: l10nApp(home: const SettingsRoute()),
      ),
    );
    await _letRegistryLoad(tester);
    await tester.pumpAndSettle();

    // Switch both hosts off from the manage sheet.
    await tester.tap(find.text('Laptop').hitTestable());
    await tester.pumpAndSettle();
    final Finder switches = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Switch),
    );
    await tester.tap(switches.at(0));
    await tester.pumpAndSettle();
    await tester.tap(switches.at(1));
    await tester.pumpAndSettle();

    // Close the sheet: the tab shows the host card, not a dead-end
    // spinner (no active backend exists).
    await tester.tapAt(const Offset(400, 10));
    await tester.pumpAndSettle();
    expect(find.text('Host settings unavailable'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // The same card opens the manage sheet, which lists the disabled
    // hosts for re-enabling.
    await tester.tap(find.widgetWithText(FilledButton, 'Host'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a host'), findsOneWidget);
    expect(find.text('Disabled'), findsNWidgets(2));

    await tester.tap(
      find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Switch),
          )
          .at(0),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.at(0)).value, isTrue);
    await tester.tapAt(const Offset(400, 10));
    await tester.pumpAndSettle();
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Writable'), findsOneWidget);
  });

  testWidgets(
    'corrupt store document surfaces localized English error in host sheet',
    (WidgetTester tester) async {
      await pumpHostSettings(tester, document: '{"backends": [');
      await openHostSheet(tester, '127.0.0.1:3080');

      expect(
        find.text('Host configuration file contains invalid JSON.'),
        findsOneWidget,
      );
      expect(find.textContaining('backends.json'), findsNothing);
    },
  );

  testWidgets(
    'corrupt store document surfaces localized Chinese error in host sheet',
    (WidgetTester tester) async {
      await pumpHostSettings(
        tester,
        document: '{"backends": [',
        locale: const Locale('zh'),
      );
      await openHostSheet(tester, '127.0.0.1:3080');

      expect(find.text('主机配置文件包含无效的 JSON。'), findsOneWidget);
      expect(find.textContaining('backends.json'), findsNothing);
    },
  );
}
