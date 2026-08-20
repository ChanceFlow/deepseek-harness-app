/// SettingsScreen widget parity tests — the sectioned panel port.
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
import 'package:app/di/providers.dart';
import 'package:app/local_state/local_state_providers.dart';
import 'package:app/local_state/local_state_store.dart';
import 'package:app/ui/settings/busy_enter_preference.dart';
import 'package:app/ui/settings/settings_controller.dart';
import 'package:app/ui/settings/settings_screen.dart';
import 'package:app/ui/settings/settings_ui_state.dart';

const _snapshot = SettingsSnapshot(
  writable: true,
  hasDocument: true,
  namespaces: [
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
  credentialRefs: ['DEEPSEEK_API_KEY'],
);

const _credentials = [
  CredentialStatus(
    ref: 'DEEPSEEK_API_KEY',
    configured: true,
    source: 'file',
    writable: true,
  ),
];

/// Roster mirroring the web section's mixed states: shipped presets
/// (display names resolve through the shared helper), a broken
/// user-authored preset, one of them default.
const _roster = AgentPresetRoster(
  entries: [
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

/// One temp-backed store file per pump; the same instance backs the
/// cache assertions.
File _storeFile() {
  final directory = Directory.systemTemp.createTempSync('settings_test');
  addTearDown(() => directory.deleteSync(recursive: true));
  return File('${directory.path}/local_state.json');
}

/// The connection-manager fake pair: host.describe answers a valid
/// description and both downlinks open and stay open, so every
/// generation reaches CONNECTED and the retry loop sits quiescent (no
/// backoff timers for pumpAndSettle to trip over).
class _FakeRpc implements DshRpcClient {
  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload,
  ) async {
    if (endpoint == 'host.describe') {
      return RpcResult(ok: true, value: <String, Object?>{
        'version': 'test',
        'cwd': '/tmp',
        'provider': 'deepseek',
        'model': 'test-model',
        'attachedSessions': 0,
        'canOpenPath': true,
      });
    }
    return RpcResult(ok: true, value: <String, Object?>{});
  }

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

/// In-memory-backed backend registry (path_provider has no plugin in
/// tests). An optional document seeds more than the one default
/// backend; the registry's real controller + real store decode it.
BackendStore _backendStore({String? document}) {
  final dir = Directory.systemTemp.createTempSync('settings_backends_test');
  // The registry persists unawaited; the atomic write's temp+rename can
  // race a plain recursive delete (errno 39) — retry until it lands.
  addTearDown(() async {
    for (var i = 0; i < 50; i++) {
      try {
        dir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  });
  final file = File('${dir.path}/backends.json');
  if (document != null) {
    file.writeAsStringSync(document);
  }
  return BackendStore(file, seedBaseUrl: kDshBaseUrl);
}

/// Lets the registry's real dart:io chain (exists → readAsString →
/// decode → publish) and the connection handshake complete: each
/// runAsync round turns the real event loop once, each pump flushes
/// the fake-zone microtasks the completions scheduled. A seeded
/// document needs several rounds; a fresh store settles in the first.
Future<void> _letRegistryLoad(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
  }
}

/// The horizontal capsule nav. Six capsules overflow the phone-width
/// viewport in the test font (every glyph renders at its full em), so
/// the trailing section reveals on scroll.
final _navScrollable = find.byWidgetPredicate(
  (widget) =>
      widget is SingleChildScrollView &&
      widget.scrollDirection == Axis.horizontal,
);

Future<void> _revealCapsule(WidgetTester tester, String label) async {
  final capsule = find.descendant(
    of: _navScrollable,
    matching: find.text(label),
  );
  if (capsule.hitTestable().evaluate().isNotEmpty) return;
  // Off the right edge drags left; clipped on the left drags right.
  final box = tester.renderObject<RenderBox>(capsule);
  final dx = box.localToGlobal(Offset.zero).dx;
  final viewportWidth =
      tester.view.physicalSize.width / tester.view.devicePixelRatio;
  await tester.drag(
    _navScrollable,
    Offset(dx > viewportWidth ? -600.0 : 600.0, 0),
  );
  await tester.pumpAndSettle();
  expect(capsule.hitTestable(), findsOneWidget);
}

/// Pumps the screen with the shared-store provider overridden to one
/// temp-backed [LocalStateStore]. The store stays unloaded — real
/// dart:io never completes inside a testWidgets fake-async zone, and an
/// unloaded store is the correct pre-cache default (every read null),
/// with disk round-trips owned by the store's own unit tests.
Future<LocalStateStore> _pump(
  WidgetTester tester,
  SettingsUiState uiState,
  List<SettingsAction> actions,
) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = LocalStateStore(_storeFile());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStateStoreProvider.overrideWith((ref) async => store),
        backendStoreProvider.overrideWith(
          (ref) async => _backendStore(),
        ),
        dshRpcClientProvider(
          Uri.parse(kDshBaseUrl),
        ).overrideWithValue(_FakeRpc()),
        dshEventSocketProvider(
          Uri.parse(kDshBaseUrl),
        ).overrideWithValue(_QuietSocket()),
      ],
      child: MaterialApp(
        home: SettingsScreen(uiState: uiState, onAction: actions.add),
      ),
    ),
  );
  await tester.pump();
  return store;
}

/// Harness mirroring SettingsRoute's wiring below the provider layer:
/// the real controller's UDF stream driving the real screen, so the
/// fake repository is the only seam.
class _ControllerHarness extends StatelessWidget {
  const _ControllerHarness({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SettingsUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder: (context, snapshot) {
        final uiState = snapshot.data ?? const SettingsUiState();
        return SettingsScreen(uiState: uiState, onAction: controller.onAction);
      },
    );
  }
}

Future<LocalStateStore> _pumpController(
  WidgetTester tester,
  SettingsController controller,
) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = LocalStateStore(_storeFile());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStateStoreProvider.overrideWith((ref) async => store),
        backendStoreProvider.overrideWith(
          (ref) async => _backendStore(),
        ),
        dshRpcClientProvider(
          Uri.parse(kDshBaseUrl),
        ).overrideWithValue(_FakeRpc()),
        dshEventSocketProvider(
          Uri.parse(kDshBaseUrl),
        ).overrideWithValue(_QuietSocket()),
      ],
      child: MaterialApp(home: _ControllerHarness(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

/// Repository double recording the settings write path; everything the
/// screen never calls throws through [noSuchMethod].
class _RecordingSettingsRepository implements ChatRepository {
  _RecordingSettingsRepository({
    required this.snapshot,
    required this.roster,
  });

  final SettingsSnapshot snapshot;
  final AgentPresetRoster roster;

  final List<(String, String, String, int?)> updateCalls =
      <(String, String, String, int?)>[];

  @override
  Future<SettingsSnapshot> describeSettings() async => snapshot;

  @override
  Future<AgentPresetRoster> listAgentPresets() async => roster;

  @override
  Future<List<CredentialStatus>> describeCredentials(
    List<String> refs,
  ) async => const <CredentialStatus>[];

  @override
  Future<SettingsNamespace> updateSetting(
    String ns,
    String key,
    String jsonValue, {
    int? expectedRevision,
  }) async {
    updateCalls.add((ns, key, jsonValue, expectedRevision));
    return snapshot.namespaces.firstWhere((namespace) => namespace.ns == ns);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

void main() {
  testWidgets('nav switches the section pages', (tester) async {
    await _pump(
      tester,
      const SettingsUiState(
        snapshot: _snapshot,
        credentials: _credentials,
        roster: _roster,
      ),
      [],
    );

    // The panel nav (web nav rail) collapsed to capsules, in the web
    // nav order with the mobile-only Credentials page last. Six
    // capsules overflow the phone width in the test font, so the nav
    // scrolls: the first five sit in the viewport, Credentials reveals
    // on scroll. The active section's page header repeats its title,
    // so presence (not count) is the assertion.
    for (final label in [
      'Backends',
      'General',
      'Models',
      'Plugins',
      'Agent presets',
    ]) {
      expect(find.text(label).hitTestable(), findsWidgets);
    }
    await _revealCapsule(tester, 'Credentials');
    expect(find.text('Credentials').hitTestable(), findsWidgets);
    // Back to the leading capsules for the page assertions below.
    await _revealCapsule(tester, 'Backends');

    // General page: the interactive rows over the connection facts.
    expect(
      find.text('Enter behavior while busy').hitTestable(),
      findsOneWidget,
    );
    expect(find.text('Agent preset').hitTestable(), findsOneWidget);
    expect(find.text('Standard mode').hitTestable(), findsOneWidget);
    expect(find.text('Host writes').hitTestable(), findsOneWidget);
    expect(find.text('Settings document').hitTestable(), findsOneWidget);

    // The other pages stay mounted behind the nav (IndexedStack) but
    // are not visible: their content is not hit-testable.
    expect(find.text('llm-deepseek').hitTestable(), findsNothing);

    await tester.tap(find.text('Plugins').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('llm-deepseek').hitTestable(), findsOneWidget);
    expect(
      find.text('applies: live · revision: 3 · user layer · 1 secrets set')
          .hitTestable(),
      findsOneWidget,
    );
    // General went behind the nav.
    expect(find.text('Host writes').hitTestable(), findsNothing);

    await _revealCapsule(tester, 'Credentials');
    await tester.tap(find.text('Credentials').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('DEEPSEEK_API_KEY').hitTestable(), findsOneWidget);
    expect(
      find.text('configured · source: file · writable').hitTestable(),
      findsOneWidget,
    );

    await tester.tap(find.text('General').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Host writes').hitTestable(), findsOneWidget);
  });

  testWidgets('enter behavior row persists through the store', (tester) async {
    final store = await _pump(
      tester,
      const SettingsUiState(snapshot: _snapshot),
      [],
    );

    // Pre-cache default: an unloaded store reads null for every key.
    expect(store.read(kBusyEnterBehaviorKey), isNull);

    await tester.tap(find.text('Steer'));
    await tester.pump();

    // The write reached the shared store's cache synchronously — the
    // same instance the composer's busy-send path reads.
    expect(store.read(kBusyEnterBehaviorKey), 'steer');

    // A fresh preference controller over the same store (the read path
    // the provider seeds) resolves the stored behavior.
    expect(
      BusyEnterPreferenceController(store).state,
      BusyEnterBehavior.steer,
    );

    // Walk past the store's 500ms write debounce so no store timer
    // outlives the test.
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets(
    'agent preset row picks from the roster and writes the settings default',
    (tester) async {
      final repository = _RecordingSettingsRepository(
        snapshot: const SettingsSnapshot(
          writable: true,
          hasDocument: true,
          namespaces: [
            SettingsNamespace(
              ns: 'agent-presets',
              applies: SettingsApplies.live,
              revision: 3,
              hasUserLayer: true,
              secretCount: 0,
            ),
          ],
          credentialRefs: [],
        ),
        roster: _roster,
      );
      final controller = SettingsController(repository);
      addTearDown(controller.dispose);
      await _pumpController(tester, controller);

      // The row shows the roster's default through the display helper.
      expect(find.text('Agent preset').hitTestable(), findsOneWidget);
      expect(find.text('Standard mode').hitTestable(), findsOneWidget);

      await tester.tap(find.text('Agent preset').hitTestable());
      await tester.pumpAndSettle();

      // The picker lists the healthy presets only (web presetOptions).
      expect(find.text('Standard mode').hitTestable(), findsOneWidget);
      expect(find.text('Code mode').hitTestable(), findsOneWidget);
      expect(find.text('Minimal mode').hitTestable(), findsOneWidget);
      expect(find.text('My Agent').hitTestable(), findsNothing);

      await tester.tap(find.text('Code mode').hitTestable());
      await tester.pumpAndSettle();

      // The write is the web writeDefaultPreset shape: a one-key patch
      // of the agent-presets namespace's default field, CAS-guarded by
      // the described revision.
      expect(repository.updateCalls, [
        ('agent-presets', 'default', '"code"', 3),
      ]);
    },
  );

  testWidgets(
    'presets section renders the roster cards and switches the default',
    (tester) async {
      final actions = <SettingsAction>[];
      await _pump(
        tester,
        const SettingsUiState(snapshot: _snapshot, roster: _roster),
        actions,
      );

      await tester.tap(find.text('Agent presets').hitTestable());
      await tester.pumpAndSettle();

      // Groups (web builtInGroup/customGroup), the default card reading
      // selected ('In use'), the broken card marked with its reason.
      expect(find.text('BUILT-IN').hitTestable(), findsOneWidget);
      expect(find.text('CUSTOM').hitTestable(), findsOneWidget);
      expect(find.text('Standard mode').hitTestable(), findsOneWidget);
      expect(find.text('In use').hitTestable(), findsOneWidget);
      expect(find.text('My Agent').hitTestable(), findsOneWidget);
      expect(find.text('Failed to load').hitTestable(), findsOneWidget);
      expect(
        find.text('agent.cordis.yml not found').hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Custom').hitTestable(), findsOneWidget);
      expect(find.text('my-agent').hitTestable(), findsOneWidget);

      // Tapping a healthy non-default card makes it the default (same
      // write as the General row).
      await tester.tap(find.text('Minimal mode').hitTestable());
      await tester.pumpAndSettle();
      expect(
        actions,
        contains(const SelectAgentPresetDefaultAction('minimal')),
      );
    },
  );

  testWidgets('empty roster renders only the presets footnote', (tester) async {
    await _pump(
      tester,
      const SettingsUiState(
        snapshot: _snapshot,
        roster: AgentPresetRoster(),
      ),
      [],
    );

    // A deployment that composes no presets has nothing to manage; the
    // General picker row does not exist either.
    expect(find.text('Agent preset').hitTestable(), findsNothing);

    await tester.tap(find.text('Agent presets').hitTestable());
    await tester.pumpAndSettle();
    expect(
      find.textContaining('authored on the host').hitTestable(),
      findsOneWidget,
    );
    expect(find.text('BUILT-IN'), findsNothing);
    expect(find.text('Standard mode'), findsNothing);
  });

  testWidgets(
    'models page shows the DeepSeek key card and opens the editor',
    (tester) async {
      final actions = <SettingsAction>[];
      await _pump(
        tester,
        const SettingsUiState(
          snapshot: _snapshot,
          credentials: _credentials,
        ),
        actions,
      );

      await tester.tap(find.text('Models').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('DeepSeek').hitTestable(), findsOneWidget);
      expect(find.text('API key configured').hitTestable(), findsOneWidget);
      expect(find.text('Configured').hitTestable(), findsOneWidget);
      expect(
        find.textContaining('Custom providers are managed on the host')
            .hitTestable(),
        findsOneWidget,
      );

      await tester.tap(find.text('DeepSeek').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Store DEEPSEEK_API_KEY'), findsOneWidget);
    },
  );

  testWidgets('error shows the loopback hint and dismisses', (tester) async {
    final actions = <SettingsAction>[];
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

  testWidgets('key patch form dispatches UpdateSettingAction', (tester) async {
    final actions = <SettingsAction>[];
    await _pump(tester, const SettingsUiState(snapshot: _snapshot), actions);

    // The namespace editors live on the Plugins page.
    await tester.tap(find.text('Plugins').hitTestable());
    await tester.pumpAndSettle();

    // Expanding the namespace card reveals the staged patch form.
    await tester.tap(find.text('llm-deepseek'));
    await tester.pumpAndSettle();

    expect(find.text('Patch key'), findsOneWidget);
    expect(find.text('Replace section'), findsOneWidget);
    expect(find.textContaining('CAS revision 3'), findsOneWidget);

    final keyField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == null,
    );
    final valueField = find.byWidgetPredicate(
      (w) =>
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
    tester,
  ) async {
    final actions = <SettingsAction>[];
    await _pump(tester, const SettingsUiState(snapshot: _snapshot), actions);

    await tester.tap(find.text('Plugins').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('llm-deepseek'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace section'));
    await tester.pump();
    expect(find.text('Patch key'), findsOneWidget);

    final replaceField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '{ "key": value }',
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

  testWidgets('credential sheet set/unset dispatch', (tester) async {
    final actions = <SettingsAction>[];
    await _pump(
      tester,
      const SettingsUiState(snapshot: _snapshot, credentials: _credentials),
      actions,
    );

    // Tapping the credential row opens the editor sheet.
    await _revealCapsule(tester, 'Credentials');
    await tester.tap(find.text('Credentials').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('DEEPSEEK_API_KEY'));
    await tester.pumpAndSettle();
    expect(find.text('Store DEEPSEEK_API_KEY'), findsOneWidget);

    final secretField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'secret value',
    );
    await tester.enterText(secretField, 'sk-test');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      actions,
      contains(const SetCredentialAction('DEEPSEEK_API_KEY', 'sk-test')),
    );

    // The destructive unset rides the same sheet footer.
    actions.clear();
    await tester.tap(find.text('DEEPSEEK_API_KEY'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unset'));
    await tester.pump();
    expect(actions, contains(const UnsetCredentialAction('DEEPSEEK_API_KEY')));
  });

  testWidgets('read-only snapshot hides edit affordances', (tester) async {
    await _pump(
      tester,
      const SettingsUiState(
        snapshot: SettingsSnapshot(
          writable: false,
          hasDocument: false,
          namespaces: [
            SettingsNamespace(
              ns: 'shell',
              applies: SettingsApplies.restart,
              revision: 0,
              hasUserLayer: false,
              secretCount: 0,
            ),
          ],
          credentialRefs: [],
        ),
        roster: _roster,
      ),
      [],
    );

    expect(find.text('Read-only'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);

    // The agent-preset picker stays closed on a read-only host (the
    // write would be refused); the row still shows the default.
    expect(find.text('Standard mode').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Agent preset').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Code mode').hitTestable(), findsNothing);

    // Expanding a read-only card shows the notice, not the patch form.
    await tester.tap(find.text('Plugins').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('shell'));
    await tester.pumpAndSettle();
    expect(find.text('Patch key'), findsNothing);
    expect(find.textContaining('read-only'), findsOneWidget);

    // The Models page carries the web read-only notice.
    await tester.tap(find.text('Models').hitTestable());
    await tester.pumpAndSettle();
    expect(
      find.text('The settings document is read-only in this deployment.')
          .hitTestable(),
      findsOneWidget,
    );

    await _revealCapsule(tester, 'Credentials');
    await tester.tap(find.text('Credentials').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('No credentials referenced.'), findsOneWidget);
  });

  // The Backends section: device-local registry surface. The registry
  // runs its real controller over a temp-file store seeded with two
  // hosts; both endpoints ride the quiet transport fakes (a second
  // port on the emulator-loopback host).
  const twoBackendsDoc =
      '{"backends": ['
      '{"id": "default", "label": "Laptop", "baseUrl": "http://10.0.2.2:3080"},'
      '{"id": "b1", "label": "Build box", "baseUrl": "http://10.0.2.2:3081"}'
      '], "activeId": "default"}';

  Future<void> pumpBackends(
    WidgetTester tester, {
    String document = twoBackendsDoc,
    SettingsUiState uiState = const SettingsUiState(snapshot: _snapshot),
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendStoreProvider.overrideWith(
            (ref) async => _backendStore(document: document),
          ),
          for (final uri in [
            Uri.parse(kDshBaseUrl),
            Uri.parse('http://10.0.2.2:3081'),
            Uri.parse('http://10.0.2.2:3082'),
          ]) ...[
            dshRpcClientProvider(uri).overrideWithValue(_FakeRpc()),
            dshEventSocketProvider(uri).overrideWithValue(_QuietSocket()),
          ],
          localStateStoreProvider.overrideWith(
            (ref) async => LocalStateStore(_storeFile()),
          ),
        ],
        child: MaterialApp(
          home: SettingsScreen(uiState: uiState, onAction: (_) {}),
        ),
      ),
    );
    await _letRegistryLoad(tester);
    // The nav capsule is the first 'Backends' text in the column (the
    // unreachable-host gate's shortcut button may render below it).
    await tester.tap(find.text('Backends').hitTestable().first);
    await tester.pumpAndSettle();
  }

  testWidgets('backends section lists rows and switches the active one', (
    tester,
  ) async {
    await pumpBackends(tester);

    // Both configured rows with their endpoints; the active one badged.
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Build box'), findsOneWidget);
    expect(find.text('10.0.2.2:3080'), findsOneWidget);
    expect(find.text('10.0.2.2:3081'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Standby'), findsOneWidget);
    expect(find.text('Add backend'), findsOneWidget);

    // Tapping the standby row selects it: the badges swap (the chat
    // surface follows the registry's active id).
    await tester.tap(find.text('Build box'));
    await tester.pumpAndSettle();
    final buildBoxRow = find.ancestor(
      of: find.text('Build box'),
      matching: find.byType(InkWell),
    );
    expect(
      find.descendant(of: buildBoxRow, matching: find.text('Active')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Laptop'),
          matching: find.byType(InkWell),
        ),
        matching: find.text('Standby'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('add backend flow appends through the registry', (tester) async {
    await pumpBackends(tester);

    await tester.tap(find.text('Add backend').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Label'), findsOneWidget);
    expect(find.text('Base URL'), findsOneWidget);

    final fields = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'CI host');
    await tester.pump();
    await tester.enterText(fields.at(1), 'http://10.0.2.2:3082');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    // The sheet closed and the new row renders.
    expect(find.text('Label'), findsNothing);
    expect(find.text('CI host'), findsOneWidget);
    expect(find.text('10.0.2.2:3082'), findsOneWidget);
  });

  testWidgets('edit sheet repoints a backend and states removal guards', (
    tester,
  ) async {
    await pumpBackends(tester);

    // The standby backend's editor: prefilled fields, removable.
    await tester.tap(find.byTooltip('Edit backend').at(1));
    await tester.pumpAndSettle();
    expect(find.text('Edit backend'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);

    // Repoint the URL; the row's endpoint line follows.
    final fields = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(1), 'http://10.0.2.2:3082');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('10.0.2.2:3082'), findsOneWidget);
    expect(find.text('10.0.2.2:3081'), findsNothing);

    // The active backend's editor states the guard instead of a dead
    // remove control.
    await tester.tap(find.byTooltip('Edit backend').at(0));
    await tester.pumpAndSettle();
    expect(find.text('Remove'), findsNothing);
    expect(
      find.textContaining('Switch away before removing'),
      findsOneWidget,
    );
  });

  testWidgets('unreachable host page routes to the backends section', (
    tester,
  ) async {
    // No snapshot and not loading: the host pages state the dead end;
    // the Backends page (device-local) is the way out.
    await pumpBackends(tester, uiState: const SettingsUiState());

    await tester.tap(find.text('General').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Host settings unavailable'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Backends'));
    await tester.pumpAndSettle();
    expect(find.text('Add backend').hitTestable(), findsOneWidget);
    expect(find.text('Host settings unavailable'), findsNothing);
  });
}
