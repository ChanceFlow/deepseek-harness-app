import 'dart:async';

import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/attachment.dart';
import 'package:domain/model/command.dart';
import 'package:domain/model/connection_state.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/directory.dart';
import 'package:domain/model/goal.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/permission_select.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/session_window_stats.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/model/skills.dart';
import 'package:domain/model/subagent.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/timeline_window.dart';
import 'package:domain/model/todo.dart';
import 'package:domain/model/workspace.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/chat/chat_controller.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/state_stream.dart';

class SearchTestFakeRepository implements ChatRepository {
  SearchTestFakeRepository({
    List<SessionSummary> initialSessions = const <SessionSummary>[],
    List<WorkspaceSummary> initialWorkspaces = const <WorkspaceSummary>[],
  }) : sessions = AppStateStream<List<SessionSummary>>(initialSessions),
       workspaces = AppStateStream<List<WorkspaceSummary>>(initialWorkspaces);

  final AppStateStream<List<SessionSummary>> sessions;
  final AppStateStream<List<WorkspaceSummary>> workspaces;

  final List<String> searchCalls = <String>[];
  final Map<String, Completer<List<SessionSearchResult>>> pendingSearches =
      <String, Completer<List<SessionSearchResult>>>{};
  Future<List<SessionSearchResult>> Function(String query)? searchHandler;

  @override
  Future<List<SessionSearchResult>> searchSessions(String query) async {
    searchCalls.add(query);
    if (searchHandler != null) {
      return searchHandler!(query);
    }
    final completer = pendingSearches.putIfAbsent(
      query,
      () => Completer<List<SessionSearchResult>>(),
    );
    return completer.future;
  }

  @override
  Stream<List<SessionSummary>> observeSessions() => sessions.stream;

  @override
  Stream<List<WorkspaceSummary>> observeWorkspaces() => workspaces.stream;

  @override
  Stream<ConnectionState> observeConnectionState() =>
      AppStateStream<ConnectionState>(
        const ConnectionState(
          phase: ConnectionPhase.connected,
          hostDescription: HostDescription(version: 'test', cwd: '/tmp'),
        ),
      ).stream;

  @override
  Future<void> refreshSessions() async {}

  @override
  Future<void> refreshWorkspaces() async {}

  @override
  Future<SessionSummary> createSession(CreateSessionRequest request) async =>
      const SessionSummary(id: 'created', blank: false);

  @override
  Future<void> openSession(String sessionId) async {}

  @override
  Future<List<SkillEntry>> listSkills(String sessionId) async =>
      const <SkillEntry>[];

  @override
  Stream<List<TimelineItem>> observeTimeline(String sessionId) =>
      const Stream<List<TimelineItem>>.empty();

  @override
  Future<bool> loadOlderHistory(String sessionId) async => true;

  @override
  Future<void> archiveSession(String sessionId) async {}

  @override
  Future<void> sendMessage(SendMessageRequest request) async {}

  @override
  Future<CommandExecution?> executeCommand(
    String sessionId,
    String line,
    List<PendingImage> images, {
    bool retryOnTransportAbort = false,
  }) async => null;

  @override
  Future<void> cancelTurn(String sessionId) async {}

  @override
  Future<void> respondToApproval(ApprovalAnswer answer) async {}

  @override
  Future<void> answerQuestions(
    String requestId,
    QuestionEvidence evidence,
  ) async {}

  @override
  Future<void> cancelQuestions(String requestId, String sessionId) async {}

  @override
  Future<WorkspaceSummary> createWorkspace(String path) async =>
      WorkspaceSummary(workspaceId: 'w1', path: path, title: path);

  @override
  Future<WorkspaceSummary> renameWorkspace(
    String workspaceId,
    String title,
  ) async =>
      WorkspaceSummary(workspaceId: workspaceId, path: title, title: title);

  @override
  Future<void> deleteWorkspace(String workspaceId) async {}

  @override
  Future<SessionModels> loadModels(String sessionId) async =>
      const SessionModels(
        current: ModelSelection(provider: 'test', model: 'test'),
        routable: true,
      );

  @override
  Future<ModelSelection> selectModel(
    String sessionId,
    ModelSelection selection,
  ) async => selection;

  @override
  Future<String> renameSession(String sessionId, String title) async => title;

  @override
  Future<SessionSummary> forkSession(String sessionId, {int? atSeq}) async =>
      const SessionSummary(id: 'forked', blank: false);

  @override
  Future<void> updateQueue(QueueUpdateRequest request) async {}

  @override
  Future<SubagentCatalog> loadSubagents(String parentSessionId) async =>
      const SubagentCatalog();

  @override
  Future<void> interruptSubagent(
    String parentSessionId,
    String childSessionId,
  ) async {}

  @override
  Future<List<TimelineItem>> loadSubagentHistory(
    String parentSessionId,
    String childSessionId,
    SubagentMode mode,
  ) async => const <TimelineItem>[];

  @override
  Future<String> sendSubagentPrompt(
    String parentSessionId,
    String childSessionId,
    String text,
  ) async => 'msg-1';

  @override
  Stream<GoalProjection?> observeGoal(String sessionId) =>
      AppStateStream<GoalProjection?>(null).stream;

  @override
  Future<GoalRef> createGoal(
    String sessionId,
    String objective, {
    int? maxGoalRounds,
  }) async => const GoalRef(id: 'g1', revision: 1);

  @override
  Future<GoalRef> editGoal(
    String sessionId,
    GoalRef ref,
    String objective,
  ) async => ref;

  @override
  Future<GoalRef> pauseGoal(String sessionId, GoalRef ref) async => ref;

  @override
  Future<GoalRef> resumeGoal(String sessionId, GoalRef ref) async => ref;

  @override
  Future<GoalRef> completeGoal(String sessionId, GoalRef ref) async => ref;

  @override
  Future<void> clearGoal(String sessionId, GoalRef ref) async {}

  @override
  Future<DirectoryListing> listDirectory(String? path) async {
    throw UnsupportedError('listDirectory');
  }

  @override
  Future<String> createDirectory(String parentPath, String name) async {
    throw UnsupportedError('createDirectory');
  }

  @override
  Future<SettingsSnapshot> describeSettings() async {
    throw UnsupportedError('describeSettings');
  }

  @override
  Future<SettingsNamespace> updateSetting(
    String ns,
    String key,
    String jsonValue, {
    int? expectedRevision,
  }) async {
    throw UnsupportedError('updateSetting');
  }

  @override
  Future<SettingsNamespace> replaceSetting(
    String ns,
    String sectionJson, {
    int? expectedRevision,
  }) async {
    throw UnsupportedError('replaceSetting');
  }

  @override
  Future<SettingsNamespace> mutateSetting(
    String ns,
    List<SettingPathOp> ops, {
    int? expectedRevision,
  }) async {
    throw UnsupportedError('mutateSetting');
  }

  @override
  Future<List<CredentialStatus>> describeCredentials(List<String> refs) async {
    throw UnsupportedError('describeCredentials');
  }

  @override
  Future<void> setCredential(String ref, String value) async {
    throw UnsupportedError('setCredential');
  }

  @override
  Future<void> unsetCredential(String ref) async {
    throw UnsupportedError('unsetCredential');
  }

  @override
  Future<AttachmentData> readAttachment(
    String sessionId,
    String attachmentId,
  ) async {
    throw UnsupportedError('readAttachment');
  }

  @override
  Stream<ImageLimits?> observeImageLimits() =>
      AppStateStream<ImageLimits?>(const ImageLimits()).stream;

  @override
  Stream<List<TodoItem>?> observeTodos(String sessionId) => Stream.value(null);

  @override
  Stream<PlanState?> observePlan(String sessionId) =>
      AppStateStream<PlanState?>(null).stream;

  @override
  Stream<ContextPressure?> observeContextPressure(String sessionId) =>
      AppStateStream<ContextPressure?>(null).stream;

  @override
  Stream<ContextBreakdown?> observeContextBreakdown(String sessionId) =>
      AppStateStream<ContextBreakdown?>(null).stream;

  @override
  Stream<SessionWindowStats> observeSessionStats(String sessionId) =>
      AppStateStream<SessionWindowStats>(const SessionWindowStats()).stream;

  @override
  Future<List<String>> moveWorkspace(
    String workspaceId,
    String? beforeWorkspaceId,
  ) async {
    throw UnsupportedError('moveWorkspace');
  }

  @override
  Future<WorkspaceSummary> moveSession(
    String workspaceId,
    String sessionId,
    String? beforeSessionId,
  ) async {
    throw UnsupportedError('moveSession');
  }

  @override
  Stream<Set<String>> observeArchivedSessionIds() =>
      AppStateStream<Set<String>>(const <String>{}).stream;

  @override
  Stream<TimelineWindow> observeTimelineWindow(String sessionId) =>
      AppStateStream<TimelineWindow>(const TimelineWindow()).stream;

  @override
  Future<AgentPresetRoster> listAgentPresets() async =>
      const AgentPresetRoster();

  @override
  Future<String> selectAgentPreset(
    String sessionId,
    String agentPreset,
  ) async => agentPreset;

  @override
  Stream<PermissionSelect?> observePermissions(String sessionId) =>
      const Stream<PermissionSelect?>.empty();
}

void main() {
  test('keystrokes within debounce window dispatch exactly one host call with final query', () {
    fakeAsync((async) {
      final repo = SearchTestFakeRepository(
        initialSessions: [
          const SessionSummary(id: 's1', title: 'Session One', blank: false),
        ],
      );
      final controller = ChatController(repo);
      async.flushMicrotasks();

      controller.onAction(const SearchSessions('f'));
      async.elapse(const Duration(milliseconds: 100));
      controller.onAction(const SearchSessions('fo'));
      async.elapse(const Duration(milliseconds: 100));
      controller.onAction(const SearchSessions('foo'));

      expect(repo.searchCalls, isEmpty);

      async.elapse(const Duration(milliseconds: 250));
      expect(repo.searchCalls, <String>['foo']);

      controller.dispose();
    });
  });

  test('out-of-order host responses: slow older response does not overwrite newer query results', () {
    fakeAsync((async) {
      final repo = SearchTestFakeRepository(
        initialSessions: [
          const SessionSummary(id: 's1', title: 'First Session', blank: false),
          const SessionSummary(id: 's2', title: 'Second Session', blank: false),
        ],
      );
      final controller = ChatController(repo);
      final states = <ChatUiState>[];
      final sub = controller.uiState.listen(states.add);
      async.flushMicrotasks();

      // Query 1 dispatched
      controller.onAction(const SearchSessions('first'));
      async.elapse(const Duration(milliseconds: 250));
      expect(repo.searchCalls, <String>['first']);
      final firstCompleter = repo.pendingSearches['first']!;

      // Query 2 dispatched
      controller.onAction(const SearchSessions('second'));
      async.elapse(const Duration(milliseconds: 250));
      expect(repo.searchCalls, <String>['first', 'second']);
      final secondCompleter = repo.pendingSearches['second']!;

      // Query 2 finishes first
      secondCompleter.complete([
        const SessionSearchResult(sessionId: 's2', snippet: 'second match'),
      ]);
      async.flushMicrotasks();

      expect(states.last.searchResults.map((r) => r.sessionId), contains('s2'));
      expect(
        states.last.searchResults.map((r) => r.sessionId),
        isNot(contains('s1')),
      );

      // Now Query 1 finishes late
      firstCompleter.complete([
        const SessionSearchResult(sessionId: 's1', snippet: 'first match'),
      ]);
      async.flushMicrotasks();

      // Sequence guard must drop query 1's stale response
      expect(states.last.searchResults.map((r) => r.sessionId), contains('s2'));
      expect(
        states.last.searchResults.map((r) => r.sessionId),
        isNot(contains('s1')),
      );

      unawaited(sub.cancel());
      controller.dispose();
    });
  });

  test(
    'local-only queries surface title, workspace, and cwd matches immediately',
    () {
      fakeAsync((async) {
        final repo = SearchTestFakeRepository(
          initialSessions: [
            const SessionSummary(
              id: 's1',
              title: 'Alpha Feature',
              updatedAtEpochMs: 1000,
              blank: false,
            ),
            const SessionSummary(
              id: 's2',
              title: 'Beta Fix',
              updatedAtEpochMs: 2000,
              blank: false,
            ),
            const SessionSummary(
              id: 's3',
              title: 'Alpha Blank',
              updatedAtEpochMs: 3000,
              blank: true,
            ),
            const SessionSummary(
              id: 's4',
              title: 'Alpha Subagent',
              origin: 'subagent',
              updatedAtEpochMs: 4000,
              blank: false,
            ),
            const SessionSummary(
              id: 's5',
              cwd: '/work/gamma-dir',
              updatedAtEpochMs: 1500,
              blank: false,
            ),
          ],
          initialWorkspaces: [
            const WorkspaceSummary(
              workspaceId: 'w1',
              path: '/work/proj',
              title: 'Project Delta',
              sessionIds: ['s2'],
            ),
          ],
        );
        final controller = ChatController(repo);
        final states = <ChatUiState>[];
        final sub = controller.uiState.listen(states.add);
        async.flushMicrotasks();

        // Title match: s1 matches 'alpha'. s3 (blank) and s4 (subagent) are excluded.
        controller.onAction(const SearchSessions('alpha'));
        async.flushMicrotasks();
        expect(states.last.searchResults.map((r) => r.sessionId), <String>[
          's1',
        ]);

        // Workspace title match: s2 belongs to 'Project Delta'
        controller.onAction(const SearchSessions('delta'));
        async.flushMicrotasks();
        expect(states.last.searchResults.map((r) => r.sessionId), <String>[
          's2',
        ]);

        // CWD basename match: s5 cwd is '/work/gamma-dir'
        controller.onAction(const SearchSessions('gamma'));
        async.flushMicrotasks();
        expect(states.last.searchResults.map((r) => r.sessionId), <String>[
          's5',
        ]);

        // Recency ranking: both s1 (updatedAt 1000) and s2 (updatedAt 2000) match 'f'
        controller.onAction(const SearchSessions('f'));
        async.flushMicrotasks();
        expect(states.last.searchResults.map((r) => r.sessionId), <String>[
          's2',
          's1',
        ]);

        unawaited(sub.cancel());
        controller.dispose();
      });
    },
  );

  test(
    'local matches merge ahead of host content results with snippet enrichment',
    () {
      fakeAsync((async) {
        final repo = SearchTestFakeRepository(
          initialSessions: [
            const SessionSummary(
              id: 's1',
              title: 'Flutter Architecture',
              updatedAtEpochMs: 1000,
              blank: false,
            ),
            const SessionSummary(
              id: 's2',
              title: 'General Discussion',
              updatedAtEpochMs: 2000,
              blank: false,
            ),
          ],
        );
        final controller = ChatController(repo);
        final states = <ChatUiState>[];
        final sub = controller.uiState.listen(states.add);
        async.flushMicrotasks();

        controller.onAction(const SearchSessions('flutter'));
        async.flushMicrotasks();
        // Local match surfaces immediately with empty snippet before host responds
        expect(states.last.searchResults, hasLength(1));
        expect(states.last.searchResults.first.sessionId, 's1');
        expect(states.last.searchResults.first.snippet, '');

        // Debounce elapses and host returns content match for both s1 and s2
        async.elapse(const Duration(milliseconds: 250));
        repo.pendingSearches['flutter']!.complete([
          const SessionSearchResult(
            sessionId: 's2',
            snippet: 'Discussion about Flutter',
          ),
          const SessionSearchResult(
            sessionId: 's1',
            snippet: 'Architecture in Flutter',
          ),
        ]);
        async.flushMicrotasks();

        // Merged results: local match (s1) appears first with snippet, then host-only match (s2)
        final results = states.last.searchResults;
        expect(results, hasLength(2));
        expect(results[0].sessionId, 's1');
        expect(results[0].snippet, 'Architecture in Flutter');
        expect(results[1].sessionId, 's2');
        expect(results[1].snippet, 'Discussion about Flutter');

        unawaited(sub.cancel());
        controller.dispose();
      });
    },
  );

  test('empty or whitespace-only query clears search results immediately without host call', () {
    fakeAsync((async) {
      final repo = SearchTestFakeRepository(
        initialSessions: [
          const SessionSummary(id: 's1', title: 'Session One', blank: false),
        ],
      );
      final controller = ChatController(repo);
      final states = <ChatUiState>[];
      final sub = controller.uiState.listen(states.add);
      async.flushMicrotasks();

      controller.onAction(const SearchSessions('session'));
      async.flushMicrotasks();
      expect(states.last.searchResults, isNotEmpty);

      // Empty query clears immediately
      controller.onAction(const SearchSessions('   '));
      async.flushMicrotasks();
      expect(states.last.searchResults, isEmpty);

      // Debounce window passes: no host calls were made
      async.elapse(const Duration(milliseconds: 500));
      expect(repo.searchCalls, isEmpty);

      unawaited(sub.cancel());
      controller.dispose();
    });
  });

  test('query cap and sanitization mirrors reference rules (500 code units, NUL stripping)', () {
    fakeAsync((async) {
      final repo = SearchTestFakeRepository(
        initialSessions: [
          const SessionSummary(id: 's1', title: 'Session One', blank: false),
        ],
      );
      final controller = ChatController(repo);
      async.flushMicrotasks();

      // 1. NUL byte stripping
      controller.onAction(const SearchSessions('foo\x00bar'));
      async.elapse(const Duration(milliseconds: 250));
      expect(repo.searchCalls.last, 'foobar');

      // 2. 500 UTF-16 code unit cap
      final longQuery = 'a' * 600;
      controller.onAction(SearchSessions(longQuery));
      async.elapse(const Duration(milliseconds: 250));
      expect(repo.searchCalls.last, 'a' * 500);

      // 3. Surrogate pair boundary protection at 500 code units
      // 499 'a's + emoji (2 code units) = 501 code units -> cuts at 499 code units to avoid splitting surrogate
      final surrogateQuery = '${'a' * 499}🚀';
      controller.onAction(SearchSessions(surrogateQuery));
      async.elapse(const Duration(milliseconds: 250));
      expect(repo.searchCalls.last, 'a' * 499);

      controller.dispose();
    });
  });
}
