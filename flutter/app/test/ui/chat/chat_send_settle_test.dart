/// Send-settlement tests — the controller side of the draft-safety
/// contract: a [SendPrompt] dispatch calls its settle notice exactly
/// once, with the host's verdict, on every route (prompt, host command,
/// command-error, unmatched-command fallback). The composer clears its
/// draft only on acceptance, so the widget half of this test drives a
/// real [ChatScreen] on a real [ChatController] with a failing RPC.
library;

import 'package:domain/model/attachment.dart';
import 'package:domain/model/command.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/goal.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/permission_select.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/session_window_stats.dart';
import 'package:domain/model/timeline_window.dart';
import 'package:domain/model/todo.dart';
import 'package:domain/model/workspace.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/chat/chat_controller.dart';
import 'package:app/ui/chat/chat_local_state.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/state_stream.dart';

import '../../l10n_app.dart';
import 'chat_local_state_fake.dart';

/// The repository surface [ChatController] touches from init through a
/// session select and a send; everything else answers through [Fake].
class _SettleRepository extends Fake implements ChatRepository {
  static const SessionSummary session = SessionSummary(
    id: 's1',
    title: 'Settle session',
    blank: false,
  );

  final AppStateStream<List<SessionSummary>> sessions =
      AppStateStream<List<SessionSummary>>(<SessionSummary>[session]);
  final List<SendMessageRequest> sentMessages = <SendMessageRequest>[];
  final List<String> executedCommands = <String>[];

  /// When true, `sendMessage` and any command dispatch fail.
  bool failSend = false;

  /// The answer `executeCommand` gives while [failSend] is false; null
  /// answers the unmatched miss (the caller falls back to a prompt send).
  CommandExecution? commandExecution;

  @override
  Future<void> refreshSessions() async {}

  @override
  Future<void> refreshWorkspaces() async {}

  @override
  Stream<List<SessionSummary>> observeSessions() => sessions.stream;

  @override
  Stream<List<WorkspaceSummary>> observeWorkspaces() =>
      Stream.value(const <WorkspaceSummary>[]);

  @override
  Stream<ImageLimits?> observeImageLimits() => Stream.value(null);

  @override
  Future<void> openSession(String sessionId) async {}

  @override
  Stream<TimelineWindow> observeTimelineWindow(String sessionId) =>
      Stream.value(const TimelineWindow());

  @override
  Stream<PlanState?> observePlan(String sessionId) => Stream.value(null);

  @override
  Stream<List<TodoItem>?> observeTodos(String sessionId) =>
      Stream.value(const <TodoItem>[]);

  @override
  Stream<ContextPressure?> observeContextPressure(String sessionId) =>
      Stream.value(null);

  @override
  Stream<ContextBreakdown?> observeContextBreakdown(String sessionId) =>
      Stream.value(null);

  @override
  Stream<SessionWindowStats> observeSessionStats(String sessionId) =>
      Stream.value(const SessionWindowStats());

  @override
  Stream<GoalProjection?> observeGoal(String sessionId) => Stream.value(null);

  @override
  Stream<PermissionSelect?> observePermissions(String sessionId) =>
      Stream.value(null);

  @override
  Future<SessionModels> loadModels(String sessionId) async =>
      const SessionModels(
        current: ModelSelection(provider: 'deepseek', model: 'glm-x'),
        routable: false,
      );

  @override
  Future<void> sendMessage(SendMessageRequest request) async {
    if (failSend) throw StateError('transport aborted');
    sentMessages.add(request);
  }

  @override
  Future<CommandExecution?> executeCommand(
    String sessionId,
    String line,
    List<PendingImage> images, {
    bool retryOnTransportAbort = false,
  }) async {
    if (failSend) throw StateError('transport aborted');
    executedCommands.add(line);
    return commandExecution;
  }
}

/// Advance the fake clock past the controller's publish window and land
/// the resulting rebuilds (microtask-only chains settle in the pumps).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(kUiPublishWindow + const Duration(milliseconds: 16));
  await tester.pump();
}

void main() {
  group('controller settle notices', () {
    test('an accepted prompt settles true', () async {
      final repository = _SettleRepository();
      final controller = ChatController(repository);
      await pumpEventQueue();
      controller.onAction(const SelectSession('s1'));
      await pumpEventQueue();

      final settled = <bool>[];
      controller.onAction(SendPrompt('hello', onSettled: settled.add));
      await pumpEventQueue();

      expect(settled, <bool>[true]);
      expect(repository.sentMessages.single.text, 'hello');
      expect(controller.state.errorMessage, isNull);
      controller.dispose();
    });

    test('a failed prompt settles false and keeps the error strip', () async {
      final repository = _SettleRepository()..failSend = true;
      final controller = ChatController(repository);
      await pumpEventQueue();
      controller.onAction(const SelectSession('s1'));
      await pumpEventQueue();

      final settled = <bool>[];
      controller.onAction(SendPrompt('hello', onSettled: settled.add));
      await pumpEventQueue();

      expect(settled, <bool>[false]);
      expect(controller.state.errorMessage, contains('transport aborted'));
      expect(controller.state.isSending, isFalse);
      controller.dispose();
    });

    test('a host command error result settles false', () async {
      final repository = _SettleRepository()
        ..commandExecution = const CommandExecution(
          commandId: 'c1',
          kind: CommandOutcomeKind.error,
          text: 'plan mode is off',
        );
      final controller = ChatController(repository);
      await pumpEventQueue();
      controller.onAction(const SelectSession('s1'));
      await pumpEventQueue();

      final settled = <bool>[];
      controller.onAction(SendPrompt('/plan off', onSettled: settled.add));
      await pumpEventQueue();

      expect(settled, <bool>[false]);
      expect(controller.state.errorMessage, 'plan mode is off');
      controller.dispose();
    });

    test('a settled host command settles true', () async {
      final repository = _SettleRepository()
        ..commandExecution = const CommandExecution(
          commandId: 'c1',
          kind: CommandOutcomeKind.success,
        );
      final controller = ChatController(repository);
      await pumpEventQueue();
      controller.onAction(const SelectSession('s1'));
      await pumpEventQueue();

      final settled = <bool>[];
      controller.onAction(SendPrompt('/plan off', onSettled: settled.add));
      await pumpEventQueue();

      expect(settled, <bool>[true]);
      expect(repository.sentMessages, isEmpty);
      controller.dispose();
    });

    test('an unmatched command line falls back to the prompt send', () async {
      // commandExecution null: the live-directory miss; the line rides
      // the prompt channel and the settle follows that send's verdict.
      final repository = _SettleRepository();
      final controller = ChatController(repository);
      await pumpEventQueue();
      controller.onAction(const SelectSession('s1'));
      await pumpEventQueue();

      final settled = <bool>[];
      controller.onAction(SendPrompt('/feedback hi', onSettled: settled.add));
      await pumpEventQueue();

      expect(settled, <bool>[true]);
      controller.dispose();
    });

    test('a dispatch without a session settles false', () async {
      final repository = _SettleRepository();
      final controller = ChatController(repository);
      await pumpEventQueue();

      final settled = <bool>[];
      controller.onAction(SendPrompt('hello', onSettled: settled.add));
      await pumpEventQueue();

      expect(settled, <bool>[false]);
      controller.dispose();
    });
  });

  group('composer draft safety (real screen, real controller)', () {
    late _SettleRepository repository;
    late FakeChatLocalState localState;
    late ChatController controller;

    Future<void> pump(WidgetTester tester) async {
      repository = _SettleRepository();
      localState = FakeChatLocalState();
      controller = ChatController(repository);
      await tester.pumpWidget(
        ProviderScope(
          child: l10nApp(
            home: StreamBuilder<ChatUiState>(
              stream: controller.uiState,
              builder: (context, snapshot) => ChatScreen(
                uiState: snapshot.data ?? const ChatUiState(),
                onAction: controller.onAction,
                localState: localState,
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      controller.onAction(const SelectSession('s1'));
      await _settle(tester);
    }

    String fieldText(WidgetTester tester) =>
        tester.widget<EditableText>(find.byType(EditableText)).controller.text;

    testWidgets('a failed send keeps the draft on screen and on disk', (
      tester,
    ) async {
      await pump(tester);
      repository.failSend = true;

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      expect(localState.values[chatDraftKey('s1')], 'hello');

      await tester.tap(find.byTooltip('Send'));
      await _settle(tester);

      // The failure banner speaks; the reader's words stay put.
      expect(find.textContaining('transport aborted'), findsOneWidget);
      expect(fieldText(tester), 'hello');
      expect(localState.values[chatDraftKey('s1')], 'hello');
      controller.dispose();
    });

    testWidgets('a resent draft clears the field on acceptance', (
      tester,
    ) async {
      await pump(tester);
      repository.failSend = true;
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await _settle(tester);
      expect(fieldText(tester), 'hello');

      // The transport recovers; the reader taps send again on the kept
      // draft — one submit per tap, and this one lands.
      repository.failSend = false;
      await tester.tap(find.byTooltip('Send'));
      await _settle(tester);

      expect(fieldText(tester), '');
      // One submit per tap: the failed first attempt never reached the
      // host (nothing recorded), the accepted second one did — no silent
      // client-side replay of the first.
      expect(repository.sentMessages.map((message) => message.text), <String>[
        'hello',
      ]);
      // The cleared marker: the consumed draft does not resurrect.
      expect(localState.values.containsKey(chatDraftKey('s1')), isFalse);
      controller.dispose();
    });

    testWidgets('an accepted send clears the field; images settle too', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await _settle(tester);

      expect(fieldText(tester), '');
      expect(repository.sentMessages.single.text, 'hello');
      expect(localState.values.containsKey(chatDraftKey('s1')), isFalse);
      controller.dispose();
    });

    testWidgets(
      'picking /compact from the plus menu executes detached and leaves draft intact',
      (tester) async {
        await pump(tester);
        repository.commandExecution = const CommandExecution(
          commandId: 'cmd-c1',
          kind: CommandOutcomeKind.success,
        );

        await tester.enterText(find.byType(TextField), 'working draft');
        await tester.pump();
        expect(localState.values[chatDraftKey('s1')], 'working draft');

        // Open plus menu and pick /compact
        await tester.tap(find.byTooltip('Commands'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('/compact'));
        await _settle(tester);

        // The draft remains completely intact on screen and on disk.
        expect(fieldText(tester), 'working draft');
        expect(localState.values[chatDraftKey('s1')], 'working draft');
        // The command execution was dispatched to the repository.
        expect(repository.executedCommands, <String>['/compact']);
        expect(repository.sentMessages, isEmpty);
        controller.dispose();
      },
    );
  });
}
