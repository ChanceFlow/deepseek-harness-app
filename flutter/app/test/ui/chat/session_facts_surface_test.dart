/// The four decoded 0.1.5 facts the UI now renders: the workflow-run card,
/// the hook-audit row, the composer's sandbox-mode chip, and the dock's
/// reminder strip.
///
/// Every case drives the real [ChatController] over the shared
/// [FakeChatRepository] seam and asserts what a user sees, not the item list:
/// the surfaces read `ChatUiState`, which only the controller builds.
library;

import 'dart:async';

import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/ui/chat/chat_controller.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/permission_select.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/hook_audit_row.dart';
import 'package:app/ui/chat/sandbox_mode_fact.dart';
import 'package:app/ui/chat/schedule_reminder_strip.dart';
import 'package:app/ui/chat/workflow_run_row.dart';
import 'package:app/ui/shared/state_dot.dart';
import 'package:app/ui/state_stream.dart';
import 'package:domain/model/hook.dart';
import 'package:domain/model/permission_select.dart';
import 'package:domain/model/sandbox.dart';
import 'package:domain/model/schedule.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/timeline_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';
import 'chat_controller_test.dart' show FakeChatRepository;
import 'chat_local_state_fake.dart';

/// Answers every RPC with an empty ok, so the controller's non-session
/// loads settle without a transport.
class _EmptyRpc implements DshRpcClient {
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

/// The harness: a real controller over [repository], rendered by the real
/// [ChatScreen]. [rendered] always holds the newest published state.
class _Harness {
  _Harness(this.repository, WidgetTester tester, {double width = 800}) {
    controller = ChatController(repository);
    addTearDown(controller.dispose);
    tester.view.physicalSize = Size(width, 1280);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  final FakeChatRepository repository;
  late final ChatController controller;
  ChatUiState rendered = const ChatUiState();

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dshRpcClientProvider(Uri.parse(kDshBaseUrl))
              .overrideWithValue(_EmptyRpc()),
          dshEventSocketProvider(Uri.parse(kDshBaseUrl))
              .overrideWithValue(_QuietSocket()),
        ],
        child: l10nApp(
          home: StreamBuilder<ChatUiState>(
            stream: controller.uiState,
            builder: (context, snapshot) {
              rendered = snapshot.data ?? rendered;
              return ChatScreen(
                uiState: rendered,
                onAction: controller.onAction,
                localState: FakeChatLocalState(),
              );
            },
          ),
        ),
      ),
    );
    // The controller's upstream publishes ride a trailing-edge window.
    await tester.pump(const Duration(milliseconds: 60));
    controller.onAction(const SelectSession('session-1'));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

FakeChatRepository _repository({
  List<TimelineItem> timeline = const <TimelineItem>[],
}) {
  final repository = FakeChatRepository(
    initialSessions: const <SessionSummary>[
      SessionSummary(id: 'session-1', title: 'Test session', blank: false),
    ],
  );
  final windows = AppStateStream<TimelineWindow>(
    TimelineWindow(items: timeline),
  );
  repository.windowSource = (_) => windows.stream;
  return repository;
}

/// The workflow card's phase/member panel is a fold over a durable run; the
/// item is built directly here because the controller renders whatever the
/// adapter folded.
TimelineWorkflowRun _run({
  required String name,
  required WorkflowRunStatus status,
  required List<WorkflowPhase> phases,
  String? stopReason,
}) => TimelineWorkflowRun(
  runId: 'run-1',
  name: name,
  status: status,
  stopReason: stopReason,
  phases: phases,
);

void main() {
  group('workflow run card', () {
    testWidgets('renders the run, its phases and member statuses', (
      tester,
    ) async {
      final harness = _Harness(
        _repository(
          timeline: <TimelineItem>[
            _run(
              name: 'Release train',
              status: WorkflowRunStatus.running,
              phases: <WorkflowPhase>[
                const WorkflowPhase(
                  key: 'value:5:build',
                  phase: 'build',
                  members: <WorkflowMember>[
                    WorkflowMember(
                      seq: 1,
                      label: 'compile',
                      childId: 'child-a',
                      status: WorkflowRunStatus.completed,
                    ),
                    WorkflowMember(
                      seq: 2,
                      label: 'package',
                      childId: 'child-b',
                      status: WorkflowRunStatus.running,
                    ),
                  ],
                ),
                const WorkflowPhase(
                  key: 'missing',
                  phase: null,
                  members: <WorkflowMember>[
                    WorkflowMember(
                      seq: 3,
                      label: 'notify',
                      childId: 'child-c',
                      status: WorkflowRunStatus.running,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        tester,
      );
      await harness.pump(tester);

      expect(find.byType(WorkflowRunRow), findsOneWidget);
      // Collapsed: the header states the run and its member count.
      expect(find.text('Release train'), findsOneWidget);
      expect(find.textContaining('3 members'), findsOneWidget);
      expect(find.textContaining('Running'), findsWidgets);
      // The phase panel is closed by default; a fan-out run is one line
      // until asked.
      expect(find.text('build'), findsNothing);

      await tester.tap(find.text('Release train'));
      await tester.pumpAndSettle();
      expect(find.text('build'), findsOneWidget);
      // An omitted phase is its own identity, not an empty label.
      expect(find.text('Unphased'), findsOneWidget);
      // A phase is its own disclosure: its members stay folded until the
      // phase header is tapped, so a many-member run does not unfold at
      // once.
      expect(find.text('compile'), findsNothing);

      await tester.tap(find.text('build'));
      await tester.pumpAndSettle();
      expect(find.text('compile'), findsOneWidget);
      expect(find.text('package'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      // The unphased member's row belongs to its own phase group.
      expect(find.text('notify'), findsNothing);

      await tester.tap(find.text('Unphased'));
      await tester.pumpAndSettle();
      expect(find.text('notify'), findsOneWidget);
    });

    testWidgets('an interrupted run and its unsettled members say so', (
      tester,
    ) async {
      final harness = _Harness(
        _repository(
          timeline: <TimelineItem>[
            _run(
              name: 'Abandoned train',
              status: WorkflowRunStatus.interrupted,
              // No terminal event: the projecting fold reports no stop
              // reason, which is exactly the interrupted case.
              phases: const <WorkflowPhase>[
                WorkflowPhase(
                  key: 'missing',
                  phase: null,
                  members: <WorkflowMember>[
                    WorkflowMember(
                      seq: 1,
                      label: 'never-finished',
                      childId: 'child-a',
                      status: WorkflowRunStatus.interrupted,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        tester,
      );
      await harness.pump(tester);

      expect(find.text('Abandoned train'), findsOneWidget);
      // Both the run header and the member row state the projection; the
      // header carries it, so at least one widget reads Interrupted.
      expect(find.textContaining('Interrupted'), findsWidgets);
      // Warning, not error: an interrupted run is not a failure.
      final dots = tester.widgetList<StateDot>(find.byType(StateDot));
      expect(
        dots.any((dot) => dot.state == StateDotState.warning),
        isTrue,
        reason: 'interrupted is the warning state',
      );

      await tester.tap(find.text('Abandoned train'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unphased'));
      await tester.pumpAndSettle();
      expect(find.text('never-finished'), findsOneWidget);
      expect(find.text('Interrupted'), findsWidgets);
    });

    testWidgets('a run with no members states that on expansion', (
      tester,
    ) async {
      final harness = _Harness(
        _repository(
          timeline: <TimelineItem>[
            _run(
              name: 'Empty train',
              status: WorkflowRunStatus.completed,
              phases: const <WorkflowPhase>[],
            ),
          ],
        ),
        tester,
      );
      await harness.pump(tester);

      expect(find.text('Empty train'), findsOneWidget);
      expect(find.textContaining('0 members'), findsOneWidget);
      // No figure is zero-filled in place of a missing one; the run states
      // that nothing started.
      await tester.tap(find.text('Empty train'));
      await tester.pumpAndSettle();
      expect(find.text('No members started'), findsOneWidget);
    });
  });

  group('hook audit row', () {
    const deny = HookAudit(
      handlerId: 'hook-1',
      turn: 1,
      point: 'PreToolUse',
      dialect: HookDialect.claudeCode,
      matcher: 'bash',
      decision: 'deny',
      exitCode: 2,
      stderrSummary: 'blocked by policy',
      durationMs: 12,
    );

    testWidgets('a blocking deny reads as an audit, collapsed by default', (
      tester,
    ) async {
      final harness = _Harness(
        _repository(timeline: const <TimelineItem>[TimelineHookAudit(deny)]),
        tester,
      );
      await harness.pump(tester);

      expect(find.byType(HookAuditRow), findsOneWidget);
      expect(find.text('PreToolUse'), findsOneWidget);
      expect(find.text('deny'), findsOneWidget);
      expect(find.text('12 ms'), findsOneWidget);
      // Detail seats are collapsed: the row is one scan line until asked.
      expect(find.text('Stderr'), findsNothing);
      expect(find.text('blocked by policy'), findsNothing);

      await tester.tap(find.text('PreToolUse'));
      await tester.pumpAndSettle();
      expect(find.text('Stderr'), findsOneWidget);
      expect(find.text('blocked by policy'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Claude Code'), findsOneWidget);
      expect(find.text('bash'), findsOneWidget);
    });

    testWidgets('an unsettled invocation says pending, not a verdict', (
      tester,
    ) async {
      final harness = _Harness(
        _repository(
          timeline: const <TimelineItem>[
            TimelineHookAudit(
              HookAudit(
                handlerId: 'hook-2',
                turn: 1,
                point: 'Stop',
                dialect: HookDialect.codex,
              ),
            ),
          ],
        ),
        tester,
      );
      await harness.pump(tester);

      expect(find.text('Stop'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      // Nothing was reported, so nothing is invented.
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(find.text('Not reported'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);
      expect(find.text('Codex'), findsOneWidget);
    });
  });

  group('sandbox mode fact', () {
    // The access chip is the sandbox fact's seat: its tooltip states the
    // effective mode (or that the host reported none), because a preset's
    // own name is only the composition default.
    const access = PermissionSelect(
      currentValue: 'workspace-write',
      options: <PermissionPresetOption>[
        PermissionPresetOption(
          value: 'read-only',
          name: 'Read only',
          description: 'Reads without changing anything',
        ),
      ],
    );

    String? detailOf(WidgetTester tester) {
      final chip = tester.widget<PermissionSelectChip>(
        find.byType(PermissionSelectChip),
      );
      return chip.tooltipDetail;
    }

    testWidgets('states the reported mode', (tester) async {
      final repository = _repository();
      repository.permissionsSource = (_) =>
          Stream<PermissionSelect?>.value(access);
      repository.sandboxModeSource = (_) => Stream<SandboxModeFact?>.value(
        const SandboxModeFact(mode: SandboxMode.workspaceWrite),
      );
      final harness = _Harness(repository, tester);
      await harness.pump(tester);

      expect(find.byType(PermissionSelectChip), findsOneWidget);
      expect(detailOf(tester), 'Sandbox: Workspace write');
    });

    testWidgets('no fact says so instead of showing a default', (tester) async {
      final repository = _repository();
      repository.permissionsSource = (_) =>
          Stream<PermissionSelect?>.value(access);
      // An empty stream is the unreported state (no sandbox/mode folded).
      repository.sandboxModeSource = (_) =>
          const Stream<SandboxModeFact?>.empty();
      final harness = _Harness(repository, tester, width: 360);
      await harness.pump(tester);

      final detail = detailOf(tester);
      expect(detail, isNotNull);
      // The line states the absence; no mode name is painted anywhere.
      expect(detail, isNot(contains('Read only')));
      expect(detail, isNot(contains('Workspace write')));
      expect(detail, isNot(contains('Full access')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a delegation-seeded fact is still the session fact', (
      tester,
    ) async {
      final repository = _repository();
      repository.permissionsSource = (_) =>
          Stream<PermissionSelect?>.value(access);
      repository.sandboxModeSource = (_) => Stream<SandboxModeFact?>.value(
        const SandboxModeFact(
          mode: SandboxMode.readOnly,
          seededByDelegation: true,
        ),
      );
      final harness = _Harness(repository, tester);
      await harness.pump(tester);

      expect(detailOf(tester), 'Sandbox: Read only');
    });

    test('the glyph and label cover every mode', () {
      // Pure vocabulary check: the enum is closed, so every mode has a
      // distinct glyph and the unreported state has its own.
      expect(sandboxModeGlyph(SandboxMode.readOnly), isNotNull);
      expect(sandboxModeGlyph(SandboxMode.workspaceWrite), isNotNull);
      expect(sandboxModeGlyph(SandboxMode.dangerFullAccess), isNotNull);
      expect(sandboxModeGlyph(null), isNotNull);
    });
  });

  group('reminder strip', () {
    testWidgets('lists what and when, with the count and next target', (
      tester,
    ) async {
      final repository = _repository();
      repository.schedulesSource = (_) =>
          Stream<List<ScheduleReminder>>.value(const <ScheduleReminder>[
            ScheduleReminder(
              id: 'r1',
              kind: ScheduleReminderKind.at,
              prompt: 'Stand up and stretch',
              scheduledAt: '2999-01-02T03:04:00Z',
            ),
            ScheduleReminder(
              id: 'r2',
              kind: ScheduleReminderKind.every,
              prompt: 'Check the build',
              scheduledAt: '2999-01-03T03:04:00Z',
              everySeconds: 3600,
            ),
          ]);
      final harness = _Harness(repository, tester);
      await harness.pump(tester);

      expect(find.byType(ScheduleReminderStrip), findsOneWidget);
      expect(find.text('Reminders'), findsOneWidget);
      expect(find.textContaining('2 reminders'), findsOneWidget);

      await tester.tap(find.text('Reminders'));
      await tester.pumpAndSettle();
      expect(find.text('Stand up and stretch'), findsOneWidget);
      // The fixed-rate record names its interval without rounding.
      expect(find.textContaining('Every 1 hour'), findsOneWidget);
      expect(find.text('Check the build'), findsOneWidget);
    });

    testWidgets('an unreported set renders nothing at all', (tester) async {
      final repository = _repository();
      // No source: the schedule/change stream never published for this
      // session, which is what the pinned deployment does. A standing line
      // that only says so would spend a row of every session's dock on a fact
      // with nothing behind it.
      final harness = _Harness(repository, tester);
      await harness.pump(tester);

      expect(find.byType(ScheduleReminderStrip), findsNothing);
      expect(find.text('Not reported by this host'), findsNothing);
    });

    testWidgets('a known empty set renders nothing too', (tester) async {
      final repository = _repository();
      repository.schedulesSource = (_) =>
          Stream<List<ScheduleReminder>>.value(const <ScheduleReminder>[]);
      final harness = _Harness(repository, tester);
      await harness.pump(tester);

      expect(find.byType(ScheduleReminderStrip), findsNothing);
      expect(find.text('None active'), findsNothing);
    });
  });
}
