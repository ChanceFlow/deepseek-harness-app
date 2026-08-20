import 'package:domain/model/attachment.dart';
import 'package:domain/model/connection_state.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/permission_select.dart';
import 'package:domain/model/session_window_stats.dart';
import 'package:domain/model/directory.dart';
import 'package:domain/model/goal.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/todo.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/skills.dart';
import 'package:domain/model/subagent.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/timeline_window.dart';
import 'package:domain/model/workspace.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/chat/chat_controller.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/state_stream.dart';

class FakeChatRepository implements ChatRepository {
  FakeChatRepository({
    List<TimelineItem> initialTimeline = const <TimelineItem>[],
    List<SessionSummary> initialSessions = const <SessionSummary>[
      initialSession,
    ],
    List<WorkspaceSummary> initialWorkspaces = const <WorkspaceSummary>[],
  }) : timeline = AppStateStream<List<TimelineItem>>(initialTimeline),
       sessions = AppStateStream<List<SessionSummary>>(initialSessions),
       workspaces = AppStateStream<List<WorkspaceSummary>>(initialWorkspaces),
       baselineSessions = initialSessions,
       baselineWorkspaces = initialWorkspaces;

  static const SessionSummary initialSession = SessionSummary(
    id: 'session-1',
    title: 'Test session',
    blank: false,
  );

  final AppStateStream<List<TimelineItem>> timeline;
  final AppStateStream<List<SessionSummary>> sessions;
  final AppStateStream<List<WorkspaceSummary>> workspaces;

  final List<SessionSummary> baselineSessions;
  final List<WorkspaceSummary> baselineWorkspaces;

  final List<SendMessageRequest> sentMessages = <SendMessageRequest>[];
  final List<String> openedSessionIds = <String>[];
  final List<String> skillListCalls = <String>[];
  final List<ApprovalAnswer> approvalAnswers = <ApprovalAnswer>[];
  final List<CreateSessionRequest> createRequests = <CreateSessionRequest>[];
  final List<String> olderHistorySessionIds = <String>[];
  final List<String> archivedSessionIds = <String>[];
  final List<(String, String)> renamedWorkspaces = <(String, String)>[];
  final List<QueueUpdateRequest> queueUpdates = <QueueUpdateRequest>[];
  final List<(String, QuestionEvidence)> questionAnswers =
      <(String, QuestionEvidence)>[];
  final List<(String, String)> selectedAgentPresets = <(String, String)>[];

  /// Roster served by `listAgentPresets`; null throws (load failure).
  AgentPresetRoster? agentPresetRoster;

  /// Permission projection served per session; null stream = absent key.
  Stream<PermissionSelect?>? Function(String sessionId)? permissionsSource;

  @override
  Future<AgentPresetRoster> listAgentPresets() async {
    final roster = agentPresetRoster;
    if (roster == null) throw UnsupportedError('listAgentPresets');
    return roster;
  }

  @override
  Future<String> selectAgentPreset(String sessionId, String agentPreset) async {
    selectedAgentPresets.add((sessionId, agentPreset));
    return agentPreset;
  }

  @override
  Stream<PermissionSelect?> observePermissions(String sessionId) {
    return permissionsSource?.call(sessionId) ??
        const Stream<PermissionSelect?>.empty();
  }

  @override
  Stream<ConnectionState> observeConnectionState() =>
      AppStateStream<ConnectionState>(
        const ConnectionState(
          phase: ConnectionPhase.connected,
          hostDescription: HostDescription(version: 'test', cwd: '/tmp'),
        ),
      ).stream;

  @override
  Stream<List<SessionSummary>> observeSessions() => sessions.stream;

  @override
  Future<void> refreshSessions() async {
    sessions.value = baselineSessions;
  }

  @override
  Future<SessionSummary> createSession(CreateSessionRequest request) async {
    createRequests.add(request);
    return initialSession;
  }

  @override
  Future<void> openSession(String sessionId) async {
    openedSessionIds.add(sessionId);
    timeline.value = const <TimelineItem>[
      TimelineError(id: 'e1', message: 'offline fixture'),
    ];
  }

  @override
  Future<List<SkillEntry>> listSkills(String sessionId) async {
    skillListCalls.add(sessionId);
    return const <SkillEntry>[
      SkillEntry(name: 'generate-image', description: 'Generate images'),
    ];
  }

  @override
  Stream<List<TimelineItem>> observeTimeline(String sessionId) =>
      timeline.stream;

  @override
  Future<bool> loadOlderHistory(String sessionId) async {
    olderHistorySessionIds.add(sessionId);
    return true;
  }

  @override
  Future<void> archiveSession(String sessionId) async {
    archivedSessionIds.add(sessionId);
  }

  @override
  Future<void> sendMessage(SendMessageRequest request) async {
    sentMessages.add(request);
  }

  @override
  Future<void> cancelTurn(String sessionId) async {}

  @override
  Future<void> respondToApproval(ApprovalAnswer answer) async {
    approvalAnswers.add(answer);
  }

  @override
  Future<void> answerQuestions(
    String requestId,
    QuestionEvidence evidence,
  ) async {
    questionAnswers.add((requestId, evidence));
  }

  @override
  Stream<List<WorkspaceSummary>> observeWorkspaces() => workspaces.stream;

  @override
  Future<void> refreshWorkspaces() async {
    workspaces.value = baselineWorkspaces;
  }

  @override
  Future<WorkspaceSummary> createWorkspace(String path) async {
    return WorkspaceSummary(
      workspaceId: 'workspace-1',
      path: path,
      title: path,
    );
  }

  @override
  Future<WorkspaceSummary> renameWorkspace(
    String workspaceId,
    String title,
  ) async {
    renamedWorkspaces.add((workspaceId, title));
    return WorkspaceSummary(
      workspaceId: workspaceId,
      path: title,
      title: title,
    );
  }

  @override
  Future<void> deleteWorkspace(String workspaceId) async {}

  @override
  Future<SessionModels> loadModels(String sessionId) async {
    return const SessionModels(
      current: ModelSelection(provider: 'test', model: 'test'),
      routable: true,
    );
  }

  @override
  Future<ModelSelection> selectModel(
    String sessionId,
    ModelSelection selection,
  ) async => selection;

  @override
  Future<List<SessionSearchResult>> searchSessions(String query) async =>
      const <SessionSearchResult>[];

  @override
  Future<String> renameSession(String sessionId, String title) async => title;

  @override
  Future<SessionSummary> forkSession(String sessionId, {int? atSeq}) async =>
      initialSession;

  @override
  Future<void> updateQueue(QueueUpdateRequest request) async {
    queueUpdates.add(request);
  }

  @override
  Future<SubagentCatalog> loadSubagents(String parentSessionId) async {
    return const SubagentCatalog();
  }

  @override
  Future<void> interruptSubagent(
    String parentSessionId,
    String childSessionId,
  ) async {}

  @override
  Future<List<TimelineItem>> loadSubagentHistory(
    String parentSessionId,
    String childSessionId,
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
  Stream<TimelineWindow> observeTimelineWindow(String sessionId) {
    return observeTimeline(sessionId)
        .map((items) => TimelineWindow(items: List.unmodifiable(items)));
  }
}

void main() {
  test('init refreshes sessions', () async {
    final repository = FakeChatRepository(
      initialSessions: <SessionSummary>[FakeChatRepository.initialSession],
    );
    ChatController(repository);
    await pumpEventQueue();

    expect(await repository.observeSessions().first, <SessionSummary>[
      FakeChatRepository.initialSession,
    ]);
  });

  test('select session loads timeline', () async {
    final repository = FakeChatRepository(
      initialSessions: <SessionSummary>[FakeChatRepository.initialSession],
    );
    final controller = ChatController(repository);
    await pumpEventQueue();

    controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
    await pumpEventQueue();

    expect(repository.openedSessionIds, <String>[
      FakeChatRepository.initialSession.id,
    ]);
    expect(controller.state.timeline, hasLength(1));
  });

  test('select session loads skill catalog once per session', () async {
    final repository = FakeChatRepository(
      initialSessions: <SessionSummary>[FakeChatRepository.initialSession],
    );
    final controller = ChatController(repository);
    await pumpEventQueue();

    controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
    await pumpEventQueue();
    expect(controller.state.skills, hasLength(1));

    controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
    await pumpEventQueue();

    expect(repository.skillListCalls, hasLength(1));
    expect(
      repository.skillListCalls.single,
      FakeChatRepository.initialSession.id,
    );
  });

  test('send prompt delegates to repository', () async {
    final repository = FakeChatRepository(
      initialSessions: <SessionSummary>[FakeChatRepository.initialSession],
    );
    final controller = ChatController(repository);
    await pumpEventQueue();

    controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
    controller.onAction(const SendPrompt('hello'));
    await pumpEventQueue();

    expect(repository.sentMessages, <SendMessageRequest>[
      SendMessageRequest(
        sessionId: FakeChatRepository.initialSession.id,
        text: 'hello',
      ),
    ]);
  });

  test(
    'send prompt includes pending images and clears them on success',
    () async {
      final repository = FakeChatRepository(
        initialSessions: <SessionSummary>[FakeChatRepository.initialSession],
      );
      final controller = ChatController(repository);
      await pumpEventQueue();

      controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
      const image = PendingImage(
        id: 'content://media/1',
        mediaType: 'image/png',
        base64Data: 'aGk=',
        name: 'shot.png',
        byteSize: 2,
      );
      controller.onAction(const ImagesLoaded(<PendingImage>[image]));
      await pumpEventQueue();
      expect(controller.state.pendingImages, hasLength(1));

      controller.onAction(const SendPrompt('see this'));
      await pumpEventQueue();

      final sent = repository.sentMessages.single;
      expect(sent.text, 'see this');
      expect(sent.images, <PendingImage>[image]);
      expect(controller.state.pendingImages, isEmpty);
    },
  );

  test('send prompt with only images still sends', () async {
    final repository = FakeChatRepository(
      initialSessions: <SessionSummary>[FakeChatRepository.initialSession],
    );
    final controller = ChatController(repository);
    await pumpEventQueue();

    controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
    controller.onAction(
      const ImagesLoaded(<PendingImage>[
        PendingImage(
          id: 'u1',
          mediaType: 'image/jpeg',
          base64Data: 'aGk=',
          byteSize: 2,
        ),
      ]),
    );
    await pumpEventQueue();
    controller.onAction(const SendPrompt(''));
    await pumpEventQueue();

    expect(repository.sentMessages.single.images, hasLength(1));
  });

  test('unsupported image media type is rejected', () async {
    final repository = FakeChatRepository(
      initialSessions: <SessionSummary>[FakeChatRepository.initialSession],
    );
    final controller = ChatController(repository);
    await pumpEventQueue();

    controller.onAction(
      const ImagesLoaded(<PendingImage>[
        PendingImage(
          id: 'u1',
          mediaType: 'image/bmp',
          base64Data: 'aGk=',
          byteSize: 2,
        ),
      ]),
    );
    await pumpEventQueue();

    expect(controller.state.pendingImages, isEmpty);
    expect(controller.state.errorMessage ?? '', contains('image/bmp'));
  });

  test('pending image count is capped at the per-message limit', () async {
    final repository = FakeChatRepository(
      initialSessions: <SessionSummary>[FakeChatRepository.initialSession],
    );
    final controller = ChatController(repository);
    await pumpEventQueue();

    final batch = List<PendingImage>.generate(
      25,
      (index) => PendingImage(
        id: 'u$index',
        mediaType: 'image/png',
        base64Data: 'aGk=',
        byteSize: 2,
      ),
    );
    controller.onAction(ImagesLoaded(batch));
    await pumpEventQueue();

    expect(
      controller.state.pendingImages.length,
      ImageLimits.defaultMaxImagesPerMessage,
    );
    expect(controller.state.errorMessage ?? '', contains('more image'));
  });

  test('remove pending image drops only that image', () async {
    final repository = FakeChatRepository(
      initialSessions: <SessionSummary>[FakeChatRepository.initialSession],
    );
    final controller = ChatController(repository);
    await pumpEventQueue();

    controller.onAction(
      const ImagesLoaded(<PendingImage>[
        PendingImage(
          id: 'u1',
          mediaType: 'image/png',
          base64Data: 'aGk=',
          byteSize: 2,
        ),
        PendingImage(
          id: 'u2',
          mediaType: 'image/png',
          base64Data: 'aGk=',
          byteSize: 2,
        ),
      ]),
    );
    await pumpEventQueue();
    controller.onAction(const RemovePendingImage('u1'));
    await pumpEventQueue();

    expect(
      controller.state.pendingImages.map((image) => image.id).toList(),
      <String>['u2'],
    );
  });

  test('send prompt honours steer delivery mode', () async {
    final repository = FakeChatRepository(
      initialSessions: <SessionSummary>[FakeChatRepository.initialSession],
    );
    final controller = ChatController(repository);
    await pumpEventQueue();

    controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
    controller.onAction(const SendPrompt('take over', mode: PromptMode.steer));
    await pumpEventQueue();

    expect(
      repository.sentMessages.single,
      SendMessageRequest(
        sessionId: FakeChatRepository.initialSession.id,
        text: 'take over',
        mode: PromptMode.steer,
      ),
    );
  });

  test(
    'workspace scoped new session passes workspace request through',
    () async {
      final repository = FakeChatRepository(
        initialSessions: <SessionSummary>[FakeChatRepository.initialSession],
      );
      final controller = ChatController(repository);
      await pumpEventQueue();

      controller.onAction(const CreateSessionInWorkspace('workspace-1'));
      await pumpEventQueue();

      expect(repository.createRequests, <CreateSessionRequest>[
        const CreateSessionRequest(workspaceId: 'workspace-1'),
      ]);
      expect(repository.openedSessionIds, <String>[
        FakeChatRepository.initialSession.id,
      ]);
    },
  );

  test('load older history delegates to repository', () async {
    final repository = FakeChatRepository(
      initialSessions: <SessionSummary>[FakeChatRepository.initialSession],
    );
    final controller = ChatController(repository);
    await pumpEventQueue();

    controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
    controller.onAction(const LoadOlderHistoryAction());
    await pumpEventQueue();

    expect(repository.olderHistorySessionIds, <String>[
      FakeChatRepository.initialSession.id,
    ]);
  });

  test('archive session delegates to repository', () async {
    final repository = FakeChatRepository(
      initialSessions: <SessionSummary>[FakeChatRepository.initialSession],
    );
    final controller = ChatController(repository);
    await pumpEventQueue();

    controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
    controller.onAction(ArchiveSession(FakeChatRepository.initialSession.id));
    await pumpEventQueue();

    expect(repository.archivedSessionIds, <String>[
      FakeChatRepository.initialSession.id,
    ]);
  });

  test('approval action delegates', () async {
    final repository = FakeChatRepository(
      initialSessions: <SessionSummary>[FakeChatRepository.initialSession],
    );
    final controller = ChatController(repository);
    await pumpEventQueue();

    controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
    controller.onAction(
      const RespondApproval(
        requestId: 'rpc-1',
        approvalId: 'approval-1',
        allowed: true,
      ),
    );
    await pumpEventQueue();

    expect(
      repository.approvalAnswers.single,
      ApprovalAnswer(
        requestId: 'rpc-1',
        sessionId: FakeChatRepository.initialSession.id,
        approvalId: 'approval-1',
        allowed: true,
      ),
    );
  });

  test('blank session rows are hidden unless selected', () async {
    const blankSession = SessionSummary(
      id: 'provisional',
      blank: true,
      cwd: '/tmp/provisional',
    );
    final repository = FakeChatRepository(
      initialSessions: <SessionSummary>[
        FakeChatRepository.initialSession,
        blankSession,
      ],
    );
    final controller = ChatController(repository);
    await pumpEventQueue();

    expect(
      controller.state.sessions.map((session) => session.id).toList(),
      <String>[FakeChatRepository.initialSession.id],
    );

    controller.onAction(SelectSession(blankSession.id));
    await pumpEventQueue();

    expect(
      controller.state.sessions.map((session) => session.id).toList(),
      <String>[FakeChatRepository.initialSession.id, blankSession.id],
    );
  });

  test('workspace create reuses the workspace blank session', () async {
    const blankSession = SessionSummary(
      id: 'blank-workspace-session',
      blank: true,
      cwd: '/tmp/reusable-workspace',
    );
    const workspace = WorkspaceSummary(
      workspaceId: 'workspace-1',
      path: '/tmp/reusable-workspace',
      title: 'Workspace',
      sessionIds: <String>['blank-workspace-session'],
    );
    final repository = FakeChatRepository(
      initialSessions: const <SessionSummary>[blankSession],
      initialWorkspaces: const <WorkspaceSummary>[workspace],
    );
    final controller = ChatController(repository);
    await pumpEventQueue();

    controller.onAction(CreateSessionInWorkspace(workspace.workspaceId));
    await pumpEventQueue();

    expect(repository.createRequests, isEmpty);
    expect(repository.openedSessionIds, <String>[blankSession.id]);
    expect(controller.state.selectedSessionId, blankSession.id);
  });

  test('queue edit action delegates edited text', () async {
    final repository = FakeChatRepository(
      initialSessions: <SessionSummary>[FakeChatRepository.initialSession],
    );
    final controller = ChatController(repository);
    await pumpEventQueue();

    controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
    controller.onAction(
      const UpdateQueueAction(
        itemId: 'queued-1',
        kind: QueueUpdateKind.edit,
        text: 'revised prompt',
      ),
    );
    await pumpEventQueue();

    expect(
      repository.queueUpdates.single,
      QueueUpdateRequest(
        sessionId: FakeChatRepository.initialSession.id,
        itemId: 'queued-1',
        kind: QueueUpdateKind.edit,
        text: 'revised prompt',
      ),
    );
  });

  test('blank queue edit is ignored', () async {
    final repository = FakeChatRepository(
      initialSessions: <SessionSummary>[FakeChatRepository.initialSession],
    );
    final controller = ChatController(repository);
    await pumpEventQueue();

    controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
    controller.onAction(
      const UpdateQueueAction(
        itemId: 'queued-1',
        kind: QueueUpdateKind.edit,
        text: '   ',
      ),
    );
    await pumpEventQueue();

    expect(repository.queueUpdates, isEmpty);
  });

  test('skipped question answer delegates empty selections', () async {
    final repository = FakeChatRepository(
      initialSessions: <SessionSummary>[FakeChatRepository.initialSession],
    );
    final controller = ChatController(repository);
    await pumpEventQueue();

    controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
    controller.onAction(
      const AnswerQuestionAction(
        requestId: 'rpc-question',
        answers: <QuestionAnswer>[QuestionAnswer(questionId: 'question-1')],
      ),
    );
    await pumpEventQueue();

    final answered = repository.questionAnswers.single;
    expect(answered.$1, 'rpc-question');
    expect(answered.$2.answers.single.questionId, 'question-1');
    expect(answered.$2.answers.single.selectedOptions, isEmpty);
  });

  test('/goal command creates the goal instead of sending a prompt', () async {
    final repository = _GoalRecordingRepository();
    final controller = ChatController(repository);
    await pumpEventQueue();

    controller.onAction(const SelectSession('s1'));
    await pumpEventQueue();

    controller.onAction(const SendPrompt('/goal Ship the MVP'));
    await pumpEventQueue();

    expect(repository.createdGoals, [('s1', 'Ship the MVP')]);
    expect(repository.sentTexts, isEmpty);

    // Plain prompts still ride the message channel.
    controller.onAction(const SendPrompt('hello'));
    await pumpEventQueue();
    expect(repository.sentTexts, ['hello']);
  });

  test('/goal control words execute as host commands, never create', () async {
    final repository = _GoalRecordingRepository();
    final controller = ChatController(repository);
    await pumpEventQueue();

    controller.onAction(const SelectSession('s1'));
    await pumpEventQueue();

    // clear/pause/resume/edit are the command's own grammar (web
    // parseGoalCommand) — they fall through to the prompt channel.
    for (final text in [
      '/goal clear',
      '/goal pause',
      '/goal resume',
      '/goal edit fix bugs first',
    ]) {
      controller.onAction(SendPrompt(text));
      await pumpEventQueue();
    }
    expect(repository.createdGoals, isEmpty);
    expect(repository.sentTexts, [
      '/goal clear',
      '/goal pause',
      '/goal resume',
      '/goal edit fix bugs first',
    ]);
  });

  test('ClearGoal deletes the goal from any phase', () async {
    final repository = _GoalRecordingRepository();
    final controller = ChatController(repository);
    await pumpEventQueue();
    controller.onAction(const SelectSession('s1'));
    await pumpEventQueue();

    repository.goal.value = const GoalProjection(
      goal: GoalSnapshot(
        id: 'g1',
        revision: 3,
        objective: 'Ship it',
        phase: GoalPhase.active,
        maxGoalRounds: 10,
      ),
      roundsStarted: 1,
      createdAt: 0,
      updatedAt: 0,
    );
    await pumpEventQueue();

    controller.onAction(const ClearGoal());
    await pumpEventQueue();
    expect(repository.clearedRefs, [isNotNull]);
  });

  test(
    'ToggleGoalPause pauses an active goal and resumes a held one',
    () async {
      final repository = _GoalRecordingRepository();
      final controller = ChatController(repository);
      await pumpEventQueue();
      controller.onAction(const SelectSession('s1'));
      await pumpEventQueue();

      repository.goal.value = const GoalProjection(
        goal: GoalSnapshot(
          id: 'g1',
          revision: 3,
          objective: 'Ship it',
          phase: GoalPhase.active,
          maxGoalRounds: 10,
        ),
        roundsStarted: 1,
        createdAt: 0,
        updatedAt: 0,
      );
      await pumpEventQueue();

      controller.onAction(const ToggleGoalPause());
      await pumpEventQueue();
      expect(repository.pausedRefs, isNotEmpty);

      repository.goal.value = const GoalProjection(
        goal: GoalSnapshot(
          id: 'g1',
          revision: 4,
          objective: 'Ship it',
          phase: GoalPhase.paused,
          maxGoalRounds: 10,
        ),
        roundsStarted: 1,
        createdAt: 0,
        updatedAt: 0,
      );
      await pumpEventQueue();

      controller.onAction(const ToggleGoalPause());
      await pumpEventQueue();
      expect(repository.resumedRefs, isNotEmpty);
    },
  );
  test(
    'turn completion fires the hook on running-to-idle transition',
    () async {
      final completed = <String>[];
      final repository = _TurnCompletionRepository();
      final controller = ChatController(
        repository,
        onTurnComplete: completed.add,
      );
      await pumpEventQueue();

      controller.onAction(const SelectSession('s1'));
      await pumpEventQueue();
      expect(completed, isEmpty);

      // Running flips true: no notification yet.
      repository._states.value = [
        const SessionSummary(
          id: 's1',
          title: 'Working session',
          running: true,
          blank: false,
        ),
      ];
      await pumpEventQueue();
      expect(completed, isEmpty);

      // Turn ends: hook fires with the session title.
      repository._states.value = [
        const SessionSummary(
          id: 's1',
          title: 'Working session',
          running: false,
          blank: false,
        ),
      ];
      await pumpEventQueue();
      expect(completed, ['Working session']);

      // Idle → idle does not re-fire.
      repository._states.value = [
        const SessionSummary(
          id: 's1',
          title: 'Working session',
          running: false,
          blank: false,
        ),
      ];
      await pumpEventQueue();
      expect(completed, ['Working session']);
    },
  );

  test('loads the agent-preset roster into uiState', () async {
    const roster = AgentPresetRoster(
      entries: [
        AgentPresetEntry(
          id: 'standard',
          trust: AgentPresetTrust.system,
          isDefault: true,
        ),
      ],
    );
    final repository = FakeChatRepository()..agentPresetRoster = roster;
    final controller = ChatController(repository);
    await pumpEventQueue();

    expect(controller.state.agentPresets, roster);
  });

  test('a roster load failure hides the preset surfaces', () async {
    final repository = FakeChatRepository()..agentPresetRoster = null;
    final controller = ChatController(repository);
    await pumpEventQueue();

    expect(controller.state.agentPresets, isNull);
  });

  test('permissions subscribe per selected session', () async {
    final repository = FakeChatRepository();
    final bySession = <String, AppStateStream<PermissionSelect?>>{};
    AppStateStream<PermissionSelect?> streamFor(String sessionId) =>
        bySession.putIfAbsent(
          sessionId,
          () => AppStateStream<PermissionSelect?>(null),
        );
    repository.permissionsSource = (sessionId) => streamFor(sessionId).stream;
    final controller = ChatController(repository);
    await pumpEventQueue();
    expect(controller.state.permissions, isNull);

    controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
    await pumpEventQueue();
    expect(controller.state.permissions, isNull);

    streamFor(
      FakeChatRepository.initialSession.id,
    ).value = const PermissionSelect(
      options: [PermissionPresetOption(value: 'read-only', name: 'read-only')],
      currentValue: 'read-only',
    );
    await pumpEventQueue();
    expect(controller.state.permissions?.currentValue, 'read-only');

    controller.onAction(const SelectSession('other'));
    await pumpEventQueue();
    // The leaving session's projection does not leak across the switch.
    expect(controller.state.permissions, isNull);
  });

  test('create in workspace carries the staged preset', () async {
    final repository = FakeChatRepository();
    final controller = ChatController(repository);
    await pumpEventQueue();

    controller.onAction(
      const CreateSessionInWorkspace('w1', agentPreset: 'code'),
    );
    await pumpEventQueue();

    expect(repository.createRequests, [
      const CreateSessionRequest(workspaceId: 'w1', agentPreset: 'code'),
    ]);
    expect(repository.selectedAgentPresets, isEmpty);
  });

  test('a reused blank session switches to the staged preset', () async {
    final repository = FakeChatRepository(
      initialSessions: <SessionSummary>[
        const SessionSummary(
          id: 's-blank',
          blank: true,
          cwd: '/tmp/proj',
        ),
      ],
      initialWorkspaces: <WorkspaceSummary>[
        const WorkspaceSummary(
          workspaceId: 'w1',
          path: '/tmp/proj',
          title: 'proj',
          sessionIds: ['s-blank'],
        ),
      ],
    );
    final controller = ChatController(repository);
    await pumpEventQueue();

    controller.onAction(
      const CreateSessionInWorkspace('w1', agentPreset: 'minimal'),
    );
    await pumpEventQueue();

    // Web parity: the blank session is reused, not re-created; the stage
    // reaches it through the blank-session switch.
    expect(repository.createRequests, isEmpty);
    expect(repository.selectedAgentPresets, [('s-blank', 'minimal')]);
  });

  test('select agent preset routes to the repository', () async {
    final repository = FakeChatRepository();
    final controller = ChatController(repository);
    await pumpEventQueue();

    controller.onAction(
      const SelectAgentPreset(sessionId: 's1', agentPreset: 'minimal'),
    );
    await pumpEventQueue();

    expect(repository.selectedAgentPresets, [('s1', 'minimal')]);
  });
}

/// Records goal mutations for the command-interception tests.
class _GoalRecordingRepository extends FakeChatRepository {
  final createdGoals = <(String, String)>[];
  final sentTexts = <String>[];
  final pausedRefs = <GoalRef>[];
  final resumedRefs = <GoalRef>[];
  final clearedRefs = <GoalRef?>[];
  final AppStateStream<GoalProjection?> goal = AppStateStream<GoalProjection?>(
    null,
  );

  @override
  Stream<GoalProjection?> observeGoal(String sessionId) => goal.stream;

  @override
  Future<GoalRef> createGoal(
    String sessionId,
    String objective, {
    int? maxGoalRounds,
  }) async {
    createdGoals.add((sessionId, objective));
    return const GoalRef(id: 'g1', revision: 1);
  }

  @override
  Future<GoalRef> pauseGoal(String sessionId, GoalRef ref) async {
    pausedRefs.add(ref);
    return ref;
  }

  @override
  Future<GoalRef> resumeGoal(String sessionId, GoalRef ref) async {
    resumedRefs.add(ref);
    return ref;
  }

  @override
  Future<void> clearGoal(String sessionId, GoalRef ref) async {
    clearedRefs.add(ref);
  }

  @override
  Future<void> sendMessage(SendMessageRequest request) async {
    sentTexts.add(request.text);
  }
}

class _TurnCompletionRepository extends FakeChatRepository {
  final _states = AppStateStream<List<SessionSummary>>(const <SessionSummary>[
    SessionSummary(id: 's1', title: 'Working session', blank: false),
  ]);

  @override
  Stream<List<SessionSummary>> observeSessions() => _states.stream;
}
