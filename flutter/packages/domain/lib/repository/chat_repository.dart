/// Domain-owned repository contract.
///
/// Implementations live behind the harness adapter package. UI and
/// controller code must never import a dsh-specific implementation or type.
library;

import 'dart:async';

import '../model/attachment.dart';
import '../model/connection_state.dart';
import '../model/context_pressure.dart';
import '../model/directory.dart';
import '../model/goal.dart';
import '../model/model_catalog.dart';
import '../model/plan.dart';
import '../model/prompt.dart';
import '../model/session.dart';
import '../model/settings.dart';
import '../model/skills.dart';
import '../model/subagent.dart';
import '../model/timeline_item.dart';
import '../model/timeline_window.dart';
import '../model/workspace.dart';

Never _unsupported(String operation) => throw UnsupportedError(
  '$operation is not supported by this repository double',
);

abstract class ChatRepository {
  Stream<ConnectionState> observeConnectionState();

  Stream<List<SessionSummary>> observeSessions();

  Future<void> refreshSessions();

  Future<SessionSummary> createSession(CreateSessionRequest request);

  /// List one host-directory level; a null path lists the host home.
  Future<DirectoryListing> listDirectory(String? path) =>
      _unsupported('listDirectory');

  /// Create one child directory inside [parentPath].
  Future<String> createDirectory(String parentPath, String name) =>
      _unsupported('createDirectory');

  /// Read-only settings overview. The host pins this verb to loopback
  /// connections; other sources receive a transport error.
  Future<SettingsSnapshot> describeSettings() =>
      _unsupported('describeSettings');

  /// Patch one top-level key of a settings namespace. [jsonValue] is raw
  /// JSON validated by the adapter; [expectedRevision] is the CAS guard
  /// from the last describe. Returns the updated namespace row.
  Future<SettingsNamespace> updateSetting(
    String ns,
    String key,
    String jsonValue, {
    int? expectedRevision,
  }) => _unsupported('updateSetting');

  /// Replace the whole user-layer section of one namespace.
  Future<SettingsNamespace> replaceSetting(
    String ns,
    String sectionJson, {
    int? expectedRevision,
  }) => _unsupported('replaceSetting');

  /// Apply path-addressed set/unset ops to one namespace.
  Future<SettingsNamespace> mutateSetting(
    String ns,
    List<SettingPathOp> ops, {
    int? expectedRevision,
  }) => _unsupported('mutateSetting');

  /// Read-only probe of credential references. Like settings describe, the
  /// host only serves it to loopback-trusted callers.
  Future<List<CredentialStatus>> describeCredentials(List<String> refs) =>
      _unsupported('describeCredentials');

  /// Store one credential value; loopback-trusted connections only.
  Future<void> setCredential(String ref, String value) =>
      _unsupported('setCredential');

  /// Clear one stored credential; loopback-trusted connections only.
  Future<void> unsetCredential(String ref) => _unsupported('unsetCredential');

  Future<void> openSession(String sessionId);

  Stream<List<TimelineItem>> observeTimeline(String sessionId);

  /// Pagination-aware timeline window. The default derives from
  /// [observeTimeline] so legacy fakes keep working untouched; the harness
  /// adapter overrides this with a journal-backed state machine.
  Stream<TimelineWindow> observeTimelineWindow(String sessionId) {
    return observeTimeline(sessionId)
        .map((items) => TimelineWindow(items: List.unmodifiable(items)));
  }

  /// Load the previous history page. Returns true when an older page was
  /// accepted and folded, false when there is no more history or loading
  /// is already in flight. The default no-op keeps old test doubles valid.
  Future<bool> loadOlderHistory(String sessionId) async => false;

  Future<void> sendMessage(SendMessageRequest request);

  /// Download one durable image; bytes are session-authorized.
  Future<AttachmentData> readAttachment(
    String sessionId,
    String attachmentId,
  ) => _unsupported('readAttachment');

  /// Session-scoped user-invocable skill catalog for the `/` composer
  /// source.
  Future<List<SkillEntry>> listSkills(String sessionId) =>
      _unsupported('listSkills');

  /// Host image admission limits from the `imageLimits` session projection.
  Stream<ImageLimits?> observeImageLimits() => Stream.value(null);

  Future<void> cancelTurn(String sessionId);

  Future<void> respondToApproval(ApprovalAnswer answer);

  Future<void> answerQuestions(String requestId, QuestionEvidence evidence);

  Stream<List<WorkspaceSummary>> observeWorkspaces();

  /// Registry-global archive set mirrored from `workspace.list` and host
  /// frames.
  Stream<Set<String>> observeArchivedSessionIds() =>
      Stream.value(const <String>{});

  Future<void> refreshWorkspaces();

  /// Archive a session without deleting its log or workspace accounting
  /// slot.
  Future<void> archiveSession(String sessionId) =>
      _unsupported('archiveSession');

  Future<WorkspaceSummary> createWorkspace(String path);

  /// Rename a registered workspace. Production adapters override this with
  /// the dsh `workspace.rename` call. Test doubles may leave the default
  /// implementation and only stub the operations their scenario exercises.
  Future<WorkspaceSummary> renameWorkspace(String workspaceId, String title) =>
      _unsupported('renameWorkspace');

  Future<void> deleteWorkspace(String workspaceId);

  /// Move one workspace in the durable display order; a null anchor appends
  /// to the end. Returns the complete order after the move.
  Future<List<String>> moveWorkspace(
    String workspaceId,
    String? beforeWorkspaceId,
  ) => _unsupported('moveWorkspace');

  /// Move one session inside its workspace's durable order; a null anchor
  /// appends to the end. Returns the owning workspace summary.
  Future<WorkspaceSummary> moveSession(
    String workspaceId,
    String sessionId,
    String? beforeSessionId,
  ) => _unsupported('moveSession');

  Future<SessionModels> loadModels(String sessionId);

  Future<ModelSelection> selectModel(
    String sessionId,
    ModelSelection selection,
  );

  Future<List<SessionSearchResult>> searchSessions(String query);

  Future<String> renameSession(String sessionId, String title);

  Future<SessionSummary> forkSession(String sessionId, {int? atSeq});

  Future<void> updateQueue(QueueUpdateRequest request);

  Future<SubagentCatalog> loadSubagents(String parentSessionId);

  Future<void> interruptSubagent(String parentSessionId, String childSessionId);

  Future<List<TimelineItem>> loadSubagentHistory(
    String parentSessionId,
    String childSessionId,
  );

  Future<String> sendSubagentPrompt(
    String parentSessionId,
    String childSessionId,
    String text,
  );

  Stream<GoalProjection?> observeGoal(String sessionId);

  /// Plan collaboration state; null while the host composes no plan mode.
  Stream<PlanState?> observePlan(String sessionId) => Stream.value(null);

  /// Context-occupancy projection for the selected session (pressure +
  /// route capacity); empty until usage records exist.
  Stream<ContextPressure?> observeContextPressure(String sessionId) =>
      const Stream<ContextPressure?>.empty();

  /// Heuristic composition of the context (system / tools / conversation);
  /// empty until any component is priced.
  Stream<ContextBreakdown?> observeContextBreakdown(String sessionId) =>
      const Stream<ContextBreakdown?>.empty();

  Future<GoalRef> createGoal(
    String sessionId,
    String objective, {
    int? maxGoalRounds,
  });

  /// Replaces the current goal's objective without changing its phase.
  /// Test doubles may use the default unsupported implementation unless
  /// their scenario explicitly exercises the Web GoalBar edit verb.
  Future<GoalRef> editGoal(String sessionId, GoalRef ref, String objective) =>
      _unsupported('editGoal');

  Future<GoalRef> pauseGoal(String sessionId, GoalRef ref);

  Future<GoalRef> resumeGoal(String sessionId, GoalRef ref);

  Future<GoalRef> completeGoal(String sessionId, GoalRef ref);

  Future<void> clearGoal(String sessionId, GoalRef ref);
}

final class QuestionEvidence {
  const QuestionEvidence({required this.sessionId, required this.answers});

  final String sessionId;
  final List<QuestionAnswer> answers;
}
