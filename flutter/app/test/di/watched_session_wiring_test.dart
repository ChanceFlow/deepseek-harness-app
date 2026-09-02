/// The watched-session fact's provider wiring: the chat controller's
/// selection only while the Chat destination is the active one, reacting
/// to destination switches with no selection change. This is what lets
/// the notification center surface a turn that finished in the selected
/// session while the user reads Workspaces or Settings (the web's
/// conversation pane is always on screen; the phone's destinations are
/// not).
library;

import 'dart:async';
import 'dart:io';

import 'package:app/di/providers.dart';
import 'package:app/local_state/local_state_providers.dart';
import 'package:app/local_state/local_state_store.dart';
import 'package:app/ui/state_stream.dart';
import 'package:app/ui/chat/chat_controller.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/root/app_destination.dart';
import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/attachment.dart';
import 'package:domain/model/connection_state.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/goal.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/permission_select.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/session_window_stats.dart';
import 'package:domain/model/todo.dart';
import 'package:domain/model/timeline_window.dart';
import 'package:domain/model/workspace.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The repository surface [ChatController] touches from construction
/// through a [SelectSession]; everything else answers through [Fake].
class _Repository extends Fake implements ChatRepository {
  _Repository()
    : sessions = AppStateStream<List<SessionSummary>>(<SessionSummary>[
        const SessionSummary(id: 'session-a', title: 'A', blank: false),
      ]),
      workspaces = AppStateStream<List<WorkspaceSummary>>(
        const <WorkspaceSummary>[],
      );

  final AppStateStream<List<SessionSummary>> sessions;
  final AppStateStream<List<WorkspaceSummary>> workspaces;
  final List<String> openedSessionIds = <String>[];

  @override
  Stream<List<SessionSummary>> observeSessions() => sessions.stream;

  @override
  Stream<List<WorkspaceSummary>> observeWorkspaces() => workspaces.stream;

  @override
  Stream<ConnectionState> observeConnectionState() =>
      const Stream<ConnectionState>.empty();

  @override
  Stream<Set<String>> observeArchivedSessionIds() =>
      const Stream<Set<String>>.empty();

  @override
  Stream<ImageLimits?> observeImageLimits() =>
      const Stream<ImageLimits?>.empty();

  @override
  Future<void> refreshSessions() async {}

  @override
  Future<void> refreshWorkspaces() async {}

  @override
  Future<AgentPresetRoster> listAgentPresets() async =>
      const AgentPresetRoster(entries: []);

  @override
  Future<void> openSession(String sessionId) async {
    openedSessionIds.add(sessionId);
  }

  // The selected-session bind (timeline + per-session projections).
  @override
  Stream<TimelineWindow> observeTimelineWindow(String sessionId) =>
      const Stream<TimelineWindow>.empty();

  @override
  Stream<PlanState?> observePlan(String sessionId) =>
      const Stream<PlanState?>.empty();

  @override
  Stream<List<TodoItem>?> observeTodos(String sessionId) =>
      const Stream<List<TodoItem>?>.empty();

  @override
  Stream<ContextPressure?> observeContextPressure(String sessionId) =>
      const Stream<ContextPressure?>.empty();

  @override
  Stream<ContextBreakdown?> observeContextBreakdown(String sessionId) =>
      const Stream<ContextBreakdown?>.empty();

  @override
  Stream<SessionWindowStats> observeSessionStats(String sessionId) =>
      const Stream<SessionWindowStats>.empty();

  @override
  Stream<GoalProjection?> observeGoal(String sessionId) =>
      const Stream<GoalProjection?>.empty();

  @override
  Stream<PermissionSelect?> observePermissions(String sessionId) =>
      const Stream<PermissionSelect?>.empty();

  @override
  Future<SessionModels> loadModels(String sessionId) async =>
      const SessionModels(
        current: ModelSelection(provider: 'deepseek', model: 'test'),
        routable: false,
      );
}

LocalStateStore _store(Directory dir) =>
    LocalStateStore(File('${dir.path}/local_state.json'));

ProviderContainer _container(Directory dir) {
  return ProviderContainer(
    overrides: [
      localStateStoreProvider.overrideWith((ref) async => _store(dir)),
      chatControllerProvider('b').overrideWith((ref) {
        final controller = ChatController(_Repository());
        ref.onDispose(controller.dispose);
        return controller;
      }),
    ],
  );
}

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('watched-session-wiring');
  });
  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  test('a backend with no selection watches nothing anywhere', () {
    final container = _container(dir);
    addTearDown(container.dispose);

    expect(container.read(appDestinationProvider), AppDestination.chat);
    expect(container.read(watchedSessionIdProvider('b')), isNull);
  });

  test('selecting a session is watched only while Chat is active', () async {
    final container = _container(dir);
    addTearDown(container.dispose);

    container
        .read(chatControllerProvider('b'))
        .onAction(const SelectSession('session-a'));
    await container.read(localStateStoreProvider.future);
    expect(container.read(watchedSessionIdProvider('b')), 'session-a');

    // The bottom tab bar owns the destination; drive the provider the way
    // the tab bar does. The selection itself is unchanged.
    container
        .read(appDestinationProvider.notifier)
        .select(AppDestination.workspaces);
    expect(container.read(watchedSessionIdProvider('b')), isNull);

    container.read(appDestinationProvider.notifier).select(AppDestination.chat);
    expect(container.read(watchedSessionIdProvider('b')), 'session-a');
  });
}
