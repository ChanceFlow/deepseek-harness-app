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
import 'package:app/ui/settings/locale_preference.dart';
import 'package:app/ui/settings/settings_controller.dart';
import 'package:app/ui/settings/settings_screen.dart';
import 'package:app/ui/settings/settings_ui_state.dart';

import '../../l10n_app.dart';

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
      return RpcResult(
        ok: true,
        value: <String, Object?>{
          'version': 'test',
          'cwd': '/tmp',
          'provider': 'deepseek',
          'model': 'test-model',
          'attachedSessions': 0,
          'canOpenPath': true,
        },
      );
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

/// The horizontal capsule nav. The section nav's capsules overflow the
/// phone-width viewport in the test font (every glyph renders at its
/// full em), so the trailing section reveals on scroll. Scoped to the
/// scrollable that carries the section capsules — the category row
/// above it rides its own horizontal scroll view.
final _navScrollable = find.byWidgetPredicate(
  (widget) =>
      widget is SingleChildScrollView &&
      widget.scrollDirection == Axis.horizontal,
);
final _sectionNavScrollable = find.ancestor(
  of: find.text('General'),
  matching: _navScrollable,
);

Future<void> _revealCapsule(WidgetTester tester, String label) async {
  final capsule = find.descendant(
    of: _sectionNavScrollable,
    matching: find.text(label),
  );
  if (capsule.hitTestable().evaluate().isNotEmpty) return;
  // Clipped on the right drags left; clipped on the left drags right.
  // The right-edge test covers a capsule whose left edge already sits
  // inside the viewport but whose body is cut off.
  final box = tester.renderObject<RenderBox>(capsule);
  final left = box.localToGlobal(Offset.zero).dx;
  final right = left + box.size.width;
  final viewportWidth =
      tester.view.physicalSize.width / tester.view.devicePixelRatio;
  await tester.drag(
    _sectionNavScrollable,
    Offset(right > viewportWidth ? -600.0 : 600.0, 0),
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
        backendStoreProvider.overrideWith((ref) async => _backendStore()),
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
        backendStoreProvider.overrideWith((ref) async => _backendStore()),
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

/// Repository double recording the settings write path; everything the
/// screen never calls throws through [noSuchMethod].
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

    // The two category capsules carry the tab's split: App
    // (device-local) and Host; Host is the initial category.
    expect(find.text('App').hitTestable(), findsOneWidget);
    expect(find.text('Host').hitTestable(), findsOneWidget);

    // The host bar names the configured host; the registry itself
    // lives behind the bar's sheet, not on the section nav.
    expect(find.text('Laptop').hitTestable(), findsNothing);

    // The panel nav (web nav rail) collapsed to capsules, in the web
    // nav order with the mobile-only Credentials page last. Five
    // capsules overflow the phone width in the test font, so the nav
    // scrolls: the first four sit in the viewport, Credentials reveals
    // on scroll. The active section's page header repeats its title,
    // so presence (not count) is the assertion.
    for (final label in ['General', 'Models', 'Plugins', 'Agent presets']) {
      expect(find.text(label).hitTestable(), findsWidgets);
    }
    await _revealCapsule(tester, 'Credentials');
    expect(find.text('Credentials').hitTestable(), findsWidgets);
    // Back to the leading capsules for the page assertions below.
    await _revealCapsule(tester, 'General');

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
      find
          .text('applies: live · revision: 3 · user layer · 1 secret set')
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

    // The category switch keeps both halves mounted (IndexedStack):
    // the App page renders its own rows while the host pages keep
    // their state behind it.
    await tester.tap(find.text('App').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Language').hitTestable(), findsOneWidget);
    expect(
      find.text('Enter behavior while busy').hitTestable(),
      findsNothing,
    );
    expect(find.text('Host writes').hitTestable(), findsNothing);

    // Back to the host pages: the section stack resumes where it was.
    await tester.tap(find.text('Host').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Host writes').hitTestable(), findsOneWidget);
  });

  testWidgets('enter behavior row persists through the store', (tester) async {
    final store = await _pump(
      tester,
      const SettingsUiState(snapshot: _snapshot),
      [],
    );

    // The row lives on the General page (host settings); its value
    // persists device-local (the composer reads the shared store).
    // Pre-cache default: an unloaded store reads null for every key.
    expect(store.read(kBusyEnterBehaviorKey), isNull);

    await tester.tap(find.text('Steer'));
    await tester.pump();

    // The write reached the shared store's cache synchronously — the
    // same instance the composer's busy-send path reads.
    expect(store.read(kBusyEnterBehaviorKey), 'steer');

    // A fresh preference controller over the same store (the read path
    // the provider seeds) resolves the stored behavior.
    expect(BusyEnterPreferenceController(store).state, BusyEnterBehavior.steer);

    // Walk past the store's 500ms write debounce so no store timer
    // outlives the test.
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('language row persists and seeds the locale controller', (
    tester,
  ) async {
    final store = await _pump(
      tester,
      const SettingsUiState(snapshot: _snapshot),
      [],
    );

    await tester.tap(find.text('App').hitTestable());
    await tester.pumpAndSettle();

    // The row offers the system default plus the two display names
    // (each in its own language, the web locale vocabulary).
    expect(find.text('Follow system').hitTestable(), findsOneWidget);
    expect(find.text('中文').hitTestable(), findsOneWidget);
    expect(find.text('English').hitTestable(), findsOneWidget);

    // Pre-cache default: no stored preference.
    expect(store.read(kAppLocalePreferenceKey), isNull);

    await tester.tap(find.text('中文'));
    await tester.pump();

    // The write reached the shared store's cache synchronously — the
    // same instance DshApp's locale resolution reads.
    expect(store.read(kAppLocalePreferenceKey), 'zh');

    // A fresh controller over the same store (the read path the
    // provider seeds) resolves the stored preference, and the
    // MaterialApp mapping follows it.
    final controller = LocalePreferenceController(store);
    expect(controller.state, AppLocalePreference.zh);
    expect(resolveAppLocale(controller.state), const Locale('zh'));
    expect(resolveAppLocale(AppLocalePreference.system), isNull);
    addTearDown(controller.dispose);

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
      expect(find.text('Built-in').hitTestable(), findsOneWidget);
      expect(find.text('Custom').hitTestable(), findsNWidgets(2));
      expect(find.text('Standard mode').hitTestable(), findsOneWidget);
      expect(find.text('In use').hitTestable(), findsOneWidget);
      expect(find.text('My Agent').hitTestable(), findsOneWidget);
      expect(find.text('Failed to load').hitTestable(), findsOneWidget);
      expect(
        find.text('agent.cordis.yml not found').hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Custom').hitTestable(), findsNWidgets(2));
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
      const SettingsUiState(snapshot: _snapshot, roster: AgentPresetRoster()),
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
    expect(find.text('Built-in'), findsNothing);
    expect(find.text('Standard mode'), findsNothing);
  });

  testWidgets('models page shows the DeepSeek key card and opens the editor', (
    tester,
  ) async {
    final actions = <SettingsAction>[];
    await _pump(
      tester,
      const SettingsUiState(snapshot: _snapshot, credentials: _credentials),
      actions,
    );

    await tester.tap(find.text('Models').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('DeepSeek').hitTestable(), findsOneWidget);
    expect(find.text('API key configured').hitTestable(), findsOneWidget);
    expect(find.text('Configured').hitTestable(), findsOneWidget);
    expect(
      find
          .textContaining('Custom providers are managed on the host')
          .hitTestable(),
      findsOneWidget,
    );

    await tester.tap(find.text('DeepSeek').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Store DEEPSEEK_API_KEY'), findsOneWidget);
  });

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
      find
          .text('The settings document is read-only in this deployment.')
          .hitTestable(),
      findsOneWidget,
    );

    await _revealCapsule(tester, 'Credentials');
    await tester.tap(find.text('Credentials').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('No credentials referenced.'), findsOneWidget);
  });

  // The Hosts section: device-local registry surface. The registry
  // runs its real controller over a temp-file store seeded with two
  // hosts; both endpoints ride the quiet transport fakes (a second
  // port on the emulator-loopback host).
  const twoBackendsDoc =
      '{"backends": ['
      '{"id": "default", "label": "Laptop", "baseUrl": "http://10.0.2.2:3080"},'
      '{"id": "b1", "label": "Build box", "baseUrl": "http://10.0.2.2:3081"}'
      '], "activeId": "default"}';

  Future<void> pumpHostSettings(
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
            Uri.parse('http://10.0.2.2:3080'),
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
        child: l10nApp(
          home: SettingsScreen(uiState: uiState, onAction: (_) {}),
        ),
      ),
    );
    await _letRegistryLoad(tester);
    await tester.pumpAndSettle();
  }

  /// Opens the host sheet through the host bar (the scoped host's
  /// label is the bar's title).
  Future<void> openHostSheet(WidgetTester tester, String barLabel) async {
    await tester.tap(find.text(barLabel).hitTestable());
    await tester.pumpAndSettle();
  }

  testWidgets('host sheet lists hosts and switches the chat-active one', (
    tester,
  ) async {
    await pumpHostSettings(tester);
    // The host bar names the scoped host; its sheet owns the registry.
    expect(find.text('Laptop').hitTestable(), findsOneWidget);
    await openHostSheet(tester, 'Laptop');

    // Both configured rows with their endpoints; the sheet's title
    // states the choice.
    final sheet = find.byType(BottomSheet);
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
    // The connected hosts' versions ride the endpoint lines (the fake
    // host.describe answers version 'test').
    expect(
      find.descendant(
        of: sheet,
        matching: find.text('10.0.2.2:3080 · vtest'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: sheet,
        matching: find.text('10.0.2.2:3081 · vtest'),
      ),
      findsOneWidget,
    );
    // Laptop is scoped (check) and chat-active (badge).
    final laptopRow = find.ancestor(
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

    // The chat-active switch rides the edit sheet.
    await tester.tap(find.byTooltip('Edit host').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set as chat host'));
    await tester.pumpAndSettle();

    // Back on the host sheet: the Active badge moved to Build box.
    final buildBoxRow = find.ancestor(
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
    tester,
  ) async {
    await pumpHostSettings(tester);
    await openHostSheet(tester, 'Laptop');

    // Following the chat-active host: the sheet has no follow entry
    // while nothing is pinned.
    expect(find.text('Follow the active host'), findsNothing);

    // Pin Build box: the sheet closes and the bar follows the pin, not
    // the chat-active id.
    await tester.tap(find.text('Build box').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Build box').hitTestable(), findsOneWidget);
    expect(find.text('Laptop').hitTestable(), findsNothing);

    // Chat-active switches do not move the pinned scope: make Build
    // box the chat host, then switch back to Laptop — the scope check
    // stays on Build box throughout.
    await openHostSheet(tester, 'Build box');
    await tester.tap(find.byTooltip('Edit host').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set as chat host'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit host').at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set as chat host'));
    await tester.pumpAndSettle();

    // Laptop is the chat host again; the scope stayed pinned to
    // Build box (it keeps the check).
    final laptopRow = find.ancestor(
      of: find.text('Laptop'),
      matching: find.byType(InkWell),
    );
    expect(
      find.descendant(of: laptopRow, matching: find.text('Active')),
      findsOneWidget,
    );
    final buildBoxRow = find.ancestor(
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

    // While pinned the sheet offers follow-active; choosing it snaps
    // the scope back to the chat-active host (Laptop now).
    expect(find.text('Follow the active host'), findsOneWidget);
    await tester.tap(find.text('Follow the active host'));
    await tester.pumpAndSettle();
    expect(find.text('Laptop').hitTestable(), findsOneWidget);
  });

  testWidgets('a single configured host keeps the bar and sheet minimal', (
    tester,
  ) async {
    await pumpHostSettings(
      tester,
      document:
          '{"backends": [{"id": "default", "label": "Laptop", '
          '"baseUrl": "http://10.0.2.2:3080"}], "activeId": "default"}',
    );

    // The bar always renders: the single host's identity and state.
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.textContaining('10.0.2.2:3080'), findsOneWidget);

    // Its sheet: one row, no follow entry, adding stays reachable.
    await openHostSheet(tester, 'Laptop');
    expect(find.text('Choose a host'), findsOneWidget);
    expect(find.text('Follow the active host'), findsNothing);
    expect(find.text('Add host'), findsOneWidget);
  });

  testWidgets('SettingsRoute rebinds the described host to the scoped host', (
    tester,
  ) async {
    // The route rides the real registry chain; only the repositories
    // are faked, each host describing a different writability so the
    // rebind is observable on the General page.
    final laptop = _RecordingSettingsRepository(
      snapshot: _snapshot,
      roster: _roster,
    );
    final buildBox = _RecordingSettingsRepository(
      snapshot: const SettingsSnapshot(
        writable: false,
        hasDocument: false,
        namespaces: [],
        credentialRefs: [],
      ),
      roster: const AgentPresetRoster(),
    );
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendStoreProvider.overrideWith(
            (ref) async => _backendStore(document: twoBackendsDoc),
          ),
          chatRepositoryProvider('default').overrideWithValue(laptop),
          chatRepositoryProvider('b1').overrideWithValue(buildBox),
          for (final uri in [
            Uri.parse('http://10.0.2.2:3080'),
            Uri.parse('http://10.0.2.2:3081'),
          ]) ...[
            dshRpcClientProvider(uri).overrideWithValue(_FakeRpc()),
            dshEventSocketProvider(uri).overrideWithValue(_QuietSocket()),
          ],
          localStateStoreProvider.overrideWith(
            (ref) async => LocalStateStore(_storeFile()),
          ),
        ],
        child: l10nApp(home: const SettingsRoute()),
      ),
    );
    await _letRegistryLoad(tester);
    await tester.pumpAndSettle();

    // Following the chat-active host: Laptop's snapshot drives the
    // host pages.
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Writable'), findsOneWidget);

    // Pin Build box through the host sheet: the host pages rebind to
    // its snapshot (read-only), independent of the chat-active host.
    await tester.tap(find.text('Laptop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build box').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Build box'), findsOneWidget);
    expect(find.text('Read-only'), findsOneWidget);
    expect(find.text('Writable'), findsNothing);

    // Re-follow: the pages describe the chat-active host again.
    await tester.tap(find.text('Build box'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Follow the active host'));
    await tester.pumpAndSettle();
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Writable'), findsOneWidget);
  });

  testWidgets('add host flow appends through the registry', (tester) async {
    await pumpHostSettings(tester);
    await openHostSheet(tester, 'Laptop');

    await tester.tap(find.text('Add host').hitTestable());
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

    // The add sheet popped back onto the host sheet: the new row
    // renders in it (the endpoint line may or may not carry the
    // connected version yet — it appears once the new host's
    // handshake completes).
    expect(find.text('Label'), findsNothing);
    expect(find.text('CI host'), findsOneWidget);
    expect(find.textContaining('10.0.2.2:3082'), findsOneWidget);
  });

  testWidgets('edit sheet repoints a host and states removal guards', (
    tester,
  ) async {
    await pumpHostSettings(tester);
    await openHostSheet(tester, 'Laptop');

    // The standby host's editor: prefilled fields, removable.
    await tester.tap(find.byTooltip('Edit host').at(1));
    await tester.pumpAndSettle();
    expect(find.text('Edit host'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);

    // Repoint the URL; the row's endpoint line follows on the sheet.
    final fields = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(1), 'http://10.0.2.2:3082');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('10.0.2.2:3082'), findsOneWidget);
    expect(find.textContaining('10.0.2.2:3081'), findsNothing);

    // The active host's editor states the guard instead of a dead
    // remove control.
    await tester.tap(find.byTooltip('Edit host').at(0));
    await tester.pumpAndSettle();
    expect(find.text('Remove'), findsNothing);
    expect(find.textContaining('Switch away before removing'), findsOneWidget);
  });

  testWidgets('unreachable host page opens the host sheet', (
    tester,
  ) async {
    // No snapshot and not loading: the host pages state the dead end;
    // the host sheet (device-local) is the way out.
    await pumpHostSettings(tester, uiState: const SettingsUiState());

    await tester.tap(find.text('General').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Host settings unavailable'), findsOneWidget);
    expect(
      find.textContaining('Repoint it, or choose another host'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Host'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a host'), findsOneWidget);
    expect(find.text('Add host').hitTestable(), findsOneWidget);
  });
}
