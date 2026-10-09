/// Agent loop page: the host `agent-loop` read/write and the page the settings
/// tree routes to.
///
/// The pin's section is one namespace with one field
/// (`ui-settings-agent-loop/src/client/agent-loop-card-controller.ts:15`,
/// `:25`), so the two behaviours worth pinning are the revision fence on the
/// write and the absent rendering of a namespace the host does not publish.
library;

import 'dart:async';
import 'dart:convert';

import 'package:app/di/providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/settings/settings_agent_loop_page.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

const String _backendId = 'default';

class _FakeAgentLoopRepository implements ChatRepository {
  _FakeAgentLoopRepository({
    this.namespacePresent = true,
    this.stored = 4,
    this.failWrites = false,
    this.fieldPresent = true,
  });

  int? stored;
  int revision = 7;
  bool namespacePresent;
  bool writable = true;
  bool failWrites;

  /// Whether the namespace's value carries the field at all. A namespace the
  /// host publishes without the field is still unpublished for this page.
  bool fieldPresent;

  /// When set, a write waits on it before settling, so a test chooses whether
  /// the refusal lands while the reader still holds the field.
  Completer<void>? writeGate;

  final List<(String, String, String, int?)> writes =
      <(String, String, String, int?)>[];

  @override
  Future<SettingsSnapshot> describeSettings() async => SettingsSnapshot(
    writable: writable,
    hasDocument: true,
    namespaces: namespacePresent
        ? <SettingsNamespace>[
            SettingsNamespace(
              ns: kAgentLoopNamespace,
              applies: SettingsApplies.live,
              revision: revision,
              hasUserLayer: true,
              secretCount: 0,
              value: fieldPresent
                  ? <String, Object?>{kMaxParallelToolCallsField: stored}
                  : <String, Object?>{},
            ),
          ]
        : const <SettingsNamespace>[],
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
    if (writeGate != null) await writeGate!.future;
    if (failWrites) throw StateError('write refused');
    stored = jsonDecode(jsonValue) as int;
    revision += 1;
    return (await describeSettings()).namespaces.first;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

Future<void> _pump(
  WidgetTester tester, {
  required ChatRepository repository,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatRepositoryProvider(_backendId).overrideWithValue(repository),
      ],
      // The page takes the backend its route resolved, the way its sibling
      // pages do.
      child: l10nApp(home: const SettingsAgentLoopPage(backendId: _backendId)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('reads the stored cap with the namespace revision', () async {
    final repository = _FakeAgentLoopRepository(stored: 4);
    final controller = AgentLoopController(repository);
    addTearDown(controller.dispose);

    await controller.refresh();

    expect(controller.state.maxParallelToolCalls, 4);
    expect(controller.state.exposed, isTrue);
    expect(controller.state.writable, isTrue);
    expect(controller.state.revision, 7);
  });

  test('a write carries the revision the describe reported', () async {
    final repository = _FakeAgentLoopRepository(stored: 4);
    final controller = AgentLoopController(repository);
    addTearDown(controller.dispose);
    await controller.refresh();

    await controller.setMaxParallelToolCalls(6);

    // The CAS fence is the described revision, and the field rides its own
    // namespace — the pin's `agent-loop` (`agent-loop-card-controller.ts:15`,
    // :25).
    expect(repository.writes, <(String, String, String, int?)>[
      ('agent-loop', 'maxParallelToolCalls', '6', 7),
    ]);
    // The refresh after the write adopts the host's new revision.
    expect(controller.state.maxParallelToolCalls, 6);
    expect(controller.state.revision, 8);
  });

  test('a refused write reverts the optimistic value', () async {
    final repository = _FakeAgentLoopRepository(stored: 4, failWrites: true);
    final controller = AgentLoopController(repository);
    addTearDown(controller.dispose);
    await controller.refresh();

    await controller.setMaxParallelToolCalls(9);

    expect(controller.state.maxParallelToolCalls, 4);
    expect(controller.state.failed, isTrue);
  });

  testWidgets('an unpublished namespace renders absent, not a default', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeAgentLoopRepository(namespacePresent: false),
    );

    expect(find.text(_l10n.settingsAgentLoopUnpublished), findsOneWidget);
    // No invented number: the page offers no field the reader could mistake for
    // a stored value the host never held.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a published namespace renders the stored cap', (tester) async {
    await _pump(tester, repository: _FakeAgentLoopRepository(stored: 4));

    expect(find.text(_l10n.settingsAgentLoopUnpublished), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '4');
  });

  testWidgets('a namespace without the field is unpublished too', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeAgentLoopRepository(fieldPresent: false),
    );

    expect(find.text(_l10n.settingsAgentLoopUnpublished), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    // No number anywhere: the namespace's presence alone invents no cap.
    expect(find.text('4'), findsNothing);
  });

  testWidgets('a typed write carries the described revision', (tester) async {
    final repository = _FakeAgentLoopRepository(stored: 4);
    await _pump(tester, repository: repository);

    await tester.enterText(find.byType(TextField), '6');
    await tester.pumpAndSettle();

    expect(repository.writes, <(String, String, String, int?)>[
      ('agent-loop', 'maxParallelToolCalls', '6', 7),
    ]);
    expect(repository.stored, 6);
    expect(find.text(_l10n.settingsAgentLoopSaveFailed), findsNothing);
  });

  testWidgets('a refused typed write states the failure', (tester) async {
    final repository = _FakeAgentLoopRepository(stored: 4, failWrites: true);
    await _pump(tester, repository: repository);

    await tester.enterText(find.byType(TextField), '9');
    await tester.pumpAndSettle();

    expect(repository.writes, <(String, String, String, int?)>[
      ('agent-loop', 'maxParallelToolCalls', '9', 7),
    ]);
    expect(find.text(_l10n.settingsAgentLoopSaveFailed), findsOneWidget);
    // Nothing reached the host.
    expect(repository.stored, 4);
    // The shown value does NOT revert while the field holds focus: the page
    // syncs the reverted cap into the field only when `!_fieldFocus.hasFocus`
    // (`settings_agent_loop_page.dart:186`), and the refusal is the last
    // emission. Pinned as the behaviour in force — the reader keeps looking at
    // the number the host refused.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '9',
    );
  });

  testWidgets('the reverted cap reaches a field the reader has left', (
    tester,
  ) async {
    final repository = _FakeAgentLoopRepository(stored: 4, failWrites: true);
    final gate = Completer<void>();
    repository.writeGate = gate;
    await _pump(tester, repository: repository);

    await tester.enterText(find.byType(TextField), '9');
    await tester.pump();

    // Leave the field while the write is still in flight, then let the host
    // refuse it: the failure's emission lands with the field unfocused.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text(_l10n.settingsAgentLoopSaveFailed), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '4');
  });
}

AppLocalizations get _l10n => lookupAppLocalizations(const Locale('en'));
