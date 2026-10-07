/// Domain-owned repository contract.
///
/// Implementations live behind the harness adapter package. UI and
/// controller code must never import a dsh-specific implementation or type.
library;

import 'dart:async';

import '../model/agent_preset.dart';
import '../model/agent_team.dart';
import '../model/attachment.dart';
import '../model/command.dart';
import '../model/connection_state.dart';
import '../model/context_pressure.dart';
import '../model/cordis.dart';
import '../model/session_window_stats.dart';
import '../model/directory.dart';
import '../model/permission_select.dart';
import '../model/goal.dart';
import '../model/jobs.dart';
import '../model/llm_provider.dart';
import '../model/model_catalog.dart';
import '../model/plan.dart';
import '../model/plugin_inventory.dart';
import '../model/plugin_management.dart';
import '../model/prompt.dart';
import '../model/repository_failure.dart';
import '../model/sandbox.dart';
import '../model/schedule.dart';
import '../model/session.dart';
import '../model/session_archive.dart';
import '../model/settings.dart';
import '../model/terminal.dart';
import '../model/skills.dart';
import '../model/subagent.dart';
import '../model/timeline_item.dart';
import '../model/timeline_window.dart';
import '../model/todo.dart';
import '../model/user_question.dart';
import '../model/workspace.dart';
import '../model/workspace_file.dart';

Never _unsupported(String operation) => throw UnsupportedError(
  '$operation is not supported by this repository double',
);

abstract class ChatRepository {
  Stream<ConnectionState> observeConnectionState();

  /// Every root session the host reports, archived ones included and marked
  /// through [SessionSummary.archived]. Visibility is the browsing
  /// surfaces' own decision (the reference filters in its tree, not in its
  /// session store), and the notification folds skip archived rows
  /// explicitly.
  Stream<List<SessionSummary>> observeSessions();

  Future<void> refreshSessions();

  /// Mint a session (or reuse the request's explicit id). A Host refusal
  /// throws [RepositoryFailure] carrying the stable code and the Host's
  /// message, the shape the "new session failed" notice quotes.
  Future<SessionSummary> createSession(CreateSessionRequest request);

  /// The agent-preset roster the host composes sessions from
  /// (`agentPreset.list`; not loopback-pinned). Roster management verbs
  /// (read/copy/openDocument/remove) are loopback-pinned and stay
  /// uncovered — see docs/spec.md wire coverage.
  Future<AgentPresetRoster> listAgentPresets() =>
      _unsupported('listAgentPresets');

  /// Switch a blank session's agent preset (`agentPreset.select`). The
  /// host rejects a session that already ran (`agent-preset-locked`);
  /// the error surfaces to the caller. Returns the echoed preset id.
  Future<String> selectAgentPreset(String sessionId, String agentPreset) =>
      _unsupported('selectAgentPreset');

  /// Read one preset's declared composition (dsh `agentPresets/read`).
  ///
  /// A view, not a write: the content is the declaration rendered as YAML.
  /// An unknown preset is a Host refusal ([RepositoryFailure], code
  /// `agent-preset/not-found`).
  Future<AgentPresetDocument> readAgentPreset(String agentPreset) =>
      _unsupported('readAgentPreset');

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

  /// The deployment's permission-preset catalog (dsh
  /// `permissionPresets/catalog`): every preset the host composes, the subset
  /// a new session may default to, and the effective default.
  ///
  /// A host that composes no permission service answers with an error rather
  /// than an empty catalog; the caller hides the row instead of offering a
  /// choice that cannot land.
  Future<PermissionPresetCatalog> loadPermissionPresetCatalog() =>
      _unsupported('loadPermissionPresetCatalog');

  /// Read-only probe of credential references. Like settings describe, the
  /// host only serves it to loopback-trusted callers.
  Future<List<CredentialStatus>> describeCredentials(List<String> refs) =>
      _unsupported('describeCredentials');

  /// Store one credential value; loopback-trusted connections only.
  Future<void> setCredential(String ref, String value) =>
      _unsupported('setCredential');

  /// Clear one stored credential; loopback-trusted connections only.
  Future<void> unsetCredential(String ref) => _unsupported('unsetCredential');

  /// Every provider route the harness currently serves
  /// (`llm/listProviders`). The list is the live half of the provider
  /// directory a configuration surface renders; a route the configurable
  /// directory does not declare has no settings address.
  Future<List<LlmProvider>> listLlmProviders() =>
      _unsupported('listLlmProviders');

  /// Every provider route an adapter plugin can activate through
  /// configuration (`llm/listConfigurableProviders`), registered or dormant.
  /// Joining this with [listLlmProviders] yields the live/dormant state a
  /// provider list shows.
  Future<List<LlmConfigurableProvider>> listConfigurableProviders() =>
      _unsupported('listConfigurableProviders');

  /// Interrogate one provider endpoint for the models it advertises
  /// (`llm/discoverModels`). [settingsNs] is the namespace whose registered
  /// model discovery serves the draft; a namespace with no registered
  /// discovery answers `llm/model-discovery-rejected`.
  Future<List<LlmDiscoveredModel>> discoverModels(
    String settingsNs,
    LlmModelDiscoveryRequest request,
  ) => _unsupported('discoverModels');

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

  /// Executes one host slash-command line through the command registry
  /// (`commands/execute`): the line never reaches the model. The images
  /// ride the same admission the host applies to prompts — a command
  /// that does not declare image acceptance settles as an error result.
  /// Returns the settled execution, or null when the host reports no
  /// registered command for the line (an unmatched name is not an
  /// error — the caller falls back to the ordinary prompt channel, the
  /// web live-directory miss).
  ///
  /// When [retryOnTransportAbort] is set, a transport-level socket drop
  /// before any response bytes re-dispatches the line once on a fresh
  /// connection. The host aborts a command the moment its HTTP request
  /// dies — an in-flight drop leaves no settled result — so a retry is a
  /// clean re-run, not a duplicate. Only callers executing a benign,
  /// re-runnable command (the detached bare commands) may set it; a
  /// command that already had side effects would double-apply them.
  Future<CommandExecution?> executeCommand(
    String sessionId,
    String line,
    List<PendingImage> images, {
    bool retryOnTransportAbort = false,
  });

  /// The live slash-command roster for one agent (`commands/list`), in the
  /// host's name-sorted order. [sessionId] is the addressed agent: the host
  /// resolves an Agent identity to its session, and a subagent-owned child
  /// is refused (`session/agent-busy`). Each descriptor carries the input
  /// hint that decides bare-only versus arg-taking dispatch and the
  /// attachment flag the composer's admission uses.
  Future<List<CommandDescriptor>> listCommands(String sessionId) =>
      _unsupported('listCommands');

  /// A tick whenever the host's command registry changed
  /// (`commands/change`): a surface re-pulls [listCommands] for every open
  /// session, the web live directory's `invalidateAll`.
  Stream<void> observeCommandRosterChanges() => const Stream<void>.empty();

  /// The session's effective sandbox-mode fact, folded from its
  /// `sandbox/mode` events (`packages/sandbox/sandbox-policy`). Null until
  /// the session logged a switch, which means the deployment default
  /// applies.
  Stream<SandboxModeFact?> observeSandboxMode(String sessionId) =>
      Stream<SandboxModeFact?>.value(null);

  /// The session's active durable reminders, folded from its versioned
  /// `schedule/change` stream (`packages/schedule/schedule`).
  Stream<List<ScheduleReminder>> observeSchedules(String sessionId) =>
      const Stream<List<ScheduleReminder>>.empty();

  /// One session's active host reminders, read without activating it
  /// (`schedule/list`).
  Future<List<ScheduleRecord>> listSchedules(String sessionId) =>
      _unsupported('listSchedules');

  /// Every host reminder, active and inactive, with its original session
  /// binding (`schedule/catalog`). This is the only cross-session read, and
  /// the surface's feature probe: a deployment that patches the schedule row
  /// out answers `gateway/invocation-unavailable`.
  Future<List<ScheduleCatalogEntry>> scheduleCatalog() =>
      _unsupported('scheduleCatalog');

  /// One task's saved deliveries, newest first (`schedule/history`).
  Future<ScheduleHistoryResult> scheduleHistory({
    required String sessionId,
    required String id,
    required int limit,
    String? before,
  }) => _unsupported('scheduleHistory');

  /// Replace a task's name, instruction, and/or timing under a
  /// compare-and-update against the record the caller observed
  /// (`schedule/update`).
  ///
  /// A stale `expected` answers a miss rather than overwriting a change made
  /// elsewhere; nothing is mutated on a miss.
  Future<ScheduleUpdateResult> updateSchedule({
    required String sessionId,
    required String id,
    required ScheduleRecord expected,
    String? title,
    String? prompt,
    ScheduleTimingChange? change,
  }) => _unsupported('updateSchedule');

  /// Delete one task and its saved deliveries (`schedule/delete`).
  Future<ScheduleDeleteResult> deleteSchedule({
    required String sessionId,
    required String id,
  }) => _unsupported('deleteSchedule');

  /// The Lead Session's durable team state (`agentTeam` Session projection).
  ///
  /// Null means this Session carries no Team — the experimental Agent Teams
  /// package is not mounted, or the projection has not arrived. An empty team
  /// and an absent one must not look the same to the caller, so absence stays
  /// null rather than defaulting to an empty roster.
  Stream<AgentTeam?> observeAgentTeam(String sessionId) =>
      const Stream<AgentTeam?>.empty();

  /// Non-activating read of one Session's `agentTeam` projection
  /// (`session/projections`), for the cold seed a stream cannot give.
  ///
  /// Null means the Session exists but publishes no `agentTeam` value.
  Future<AgentTeam?> loadAgentTeam(String sessionId) =>
      _unsupported('loadAgentTeam');

  /// One background job's retained output, observed from an absolute byte
  /// offset (`job/follow`).
  ///
  /// The stream opens with a [JobOutputOpened] anchor and closes after the
  /// terminal [JobOutputStatus]; [resumeFrom] continues a previous generation
  /// at a [JobOutputChunks.next] offset, and omitting it anchors at the job's
  /// oldest retained byte. A job this client cannot see answers no frames.
  Stream<JobOutputFrame> observeJobOutput(
    String sessionId,
    String jobId, {
    int? resumeFrom,
  }) => const Stream<JobOutputFrame>.empty();

  /// Stop one background job on the human's behalf (`job/kill`).
  ///
  /// The registry's owner fence is the only access rule, and the kill is not
  /// the model's own, so the owning agent still receives the standard
  /// completion notice. A job that already settled is a success, not an
  /// error; an id this session's list does not carry throws
  /// `job/not-found` (`packages/api/job-controller/src/index.ts`).
  Future<void> killJob(String sessionId, String jobId) =>
      _unsupported('killJob');

  /// Pending dynamic-Cordis plugin approval requests (`cordis/request-run`
  /// forwarded events). An empty list is the settled state.
  Stream<List<CordisRunRequest>> observeCordisRunRequests() =>
      const Stream<List<CordisRunRequest>>.empty();

  /// Answer one pending Cordis activation request
  /// (`dynamicCordisRunner/resolveRequestRun`). The request id is the one
  /// [observeCordisRunRequests] published.
  Future<void> resolveCordisRunRequest(
    String requestId,
    CordisRunResolution resolution,
  ) => _unsupported('resolveCordisRunRequest');

  /// Read-only plugin inventory (`pluginInventory/list`): the Cordis
  /// Loader's current non-group entries and, when a roster is composed,
  /// each agent preset's plugin composition.
  Future<PluginInventorySnapshot> listPluginInventory() =>
      _unsupported('listPluginInventory');

  /// The host's bundle roster (`pluginManager/listBundles`): installed
  /// bundles and the optional ones a profile may add. Available only when
  /// [PluginInventorySnapshot.managementAvailable] is true.
  Future<List<PluginBundle>> listPluginBundles() =>
      _unsupported('listPluginBundles');

  /// The loaded plugin entries with their patch targets
  /// (`pluginManager/listPlugins`).
  Future<List<PluginInfo>> listPlugins() => _unsupported('listPlugins');

  /// The registries an installation will ask, in order
  /// (`pluginManager/registries`).
  Future<PluginRegistries> pluginRegistries() =>
      _unsupported('pluginRegistries');

  /// Resolve one spec without installing it (`pluginManager/inspect`).
  ///
  /// A refusal is a value ([PluginSpecRefused]), not an exception.
  Future<PluginSpecInspection> inspectPluginSpec(
    String spec, {
    String? registry,
  }) => _unsupported('inspectPluginSpec');

  /// Install one bundle spec on the host (`pluginManager/installBundle`).
  ///
  /// [requestId] is the client-minted id that makes the host emit progress
  /// and log events for this attempt; the unary reply settles the attempt, and
  /// [waitForPluginInstall] only reconciles a lost one. Activation is always
  /// deferred — the caller enables the bundle afterwards.
  Future<PluginChangeResult> installPluginBundle(
    String spec, {
    String? requestId,
    String? registry,
    List<String> approvedBuilds = const <String>[],
  }) => _unsupported('installPluginBundle');

  /// Reconcile one installation whose unary reply was lost
  /// (`pluginManager/waitForInstall`). Null means the host has no record of
  /// that request.
  Future<PluginChangeResult?> waitForPluginInstall(String requestId) =>
      _unsupported('waitForPluginInstall');

  /// Ask the host to stop an in-flight installation
  /// (`pluginManager/cancelInstall`).
  Future<PluginInstallCancellation> cancelPluginInstall(String requestId) =>
      _unsupported('cancelPluginInstall');

  /// Enable or disable one installed bundle
  /// (`pluginManager/setBundleEnabled`).
  Future<PluginChangeResult> setPluginBundleEnabled(
    String name,
    bool enabled,
  ) => _unsupported('setPluginBundleEnabled');

  /// Enable or disable one plugin entry (`pluginManager/setPluginEnabled`).
  Future<PluginChangeResult> setPluginEnabled(String id, bool enabled) =>
      _unsupported('setPluginEnabled');

  /// Uninstall one bundle (`pluginManager/removeBundle`). The only
  /// destructive manager operation.
  Future<PluginChangeResult> removePluginBundle(String name) =>
      _unsupported('removePluginBundle');

  /// The saved plugin-version exemptions
  /// (`pluginManager/listVersionExemptions`).
  Future<PluginVersionExemptions> listPluginVersionExemptions() =>
      _unsupported('listPluginVersionExemptions');

  /// Grant or revoke one exact plugin/runtime exemption
  /// (`pluginManager/setVersionExemption`).
  ///
  /// A grant needs the exact current runtime version and an explicit
  /// risk acceptance: it permits a package the running DSH version rejects.
  Future<PluginChangeResult> setPluginVersionExemption({
    required String packageVersion,
    required String runtimeVersion,
    required bool enabled,
    bool acceptRisk = false,
  }) => _unsupported('setPluginVersionExemption');

  /// Race the public registries and answer the first one that responds
  /// (`pluginRegistryProbe/fastest`). Null when none does or probing is off.
  Future<String?> fastestPluginRegistry() =>
      _unsupported('fastestPluginRegistry');

  /// Installation progress pushed by `plugin-manager/install-state` events.
  Stream<PluginInstallProgress> observePluginInstallProgress() =>
      const Stream<PluginInstallProgress>.empty();

  /// Package-run output pushed by `plugin-manager/install-log` events.
  Stream<PluginInstallLogChunk> observePluginInstallLog() =>
      const Stream<PluginInstallLogChunk>.empty();

  /// The profile's composition changed (`plugin-manager/changed`), so every
  /// roster read is stale.
  Stream<void> observePluginChanges() => const Stream<void>.empty();

  /// The session's terminal environment: its working directory and the input
  /// and dimension limits every new or restored terminal shares
  /// (`terminal/environment`).
  Future<TerminalEnvironment> terminalEnvironment(String sessionId) =>
      _unsupported('terminalEnvironment');

  /// The shells the host verified in its own execution environment
  /// (`terminal/shells`). Discovery allocates nothing.
  Future<List<TerminalShell>> terminalShells(String sessionId) =>
      _unsupported('terminalShells');

  /// Every terminal this session owns, including restored ones
  /// (`terminal/list`). This and [retainTerminal] are the only terminal calls
  /// that need no live Agent.
  Future<List<TerminalInfo>> listTerminals(String sessionId) =>
      _unsupported('listTerminals');

  /// Allocate one terminal, or return the existing one for the same
  /// caller-chosen [id] (`terminal/create`).
  ///
  /// The identity is minted by the client and stable across reconnects;
  /// creation is idempotent for an open identity.
  Future<TerminalInfo> createTerminal(
    String sessionId, {
    required String id,
    required int cols,
    required int rows,
    String? shellPath,
  }) => _unsupported('createTerminal');

  /// Attach to one terminal and observe its screen (`terminal/follow`).
  ///
  /// [attachmentId] is a fresh client-minted identity per generation; the
  /// first attachment to follow a running terminal owns input control. The
  /// stream opens with a [TerminalSnapshot] and stays live until the
  /// attachment is cancelled or the host ends it.
  Stream<TerminalFrame> observeTerminal(
    String sessionId,
    String terminalId,
    String attachmentId,
  ) => const Stream<TerminalFrame>.empty();

  /// Hold one terminal open for a window without taking input control
  /// (`terminal/retain`). The single frame is the hold acknowledgement; the
  /// stream stays open while the hold lives.
  Stream<void> retainTerminal(String sessionId, String terminalId) =>
      const Stream<void>.empty();

  /// Send input to the attached terminal (`terminal/write`). Input travels as
  /// UTF-8 text, control characters included; the host refuses it once this
  /// attachment no longer owns control.
  Future<void> writeTerminal(
    String sessionId,
    String terminalId,
    String attachmentId,
    String data,
  ) => _unsupported('writeTerminal');

  /// Resize the terminal's pseudo-terminal and recovery screen
  /// (`terminal/resize`).
  Future<void> resizeTerminal(
    String sessionId,
    String terminalId,
    String attachmentId,
    int cols,
    int rows,
  ) => _unsupported('resizeTerminal');

  /// Rename one terminal without touching its shell (`terminal/rename`).
  Future<void> renameTerminal(
    String sessionId,
    String terminalId,
    String title,
  ) => _unsupported('renameTerminal');

  /// Close one terminal and kill its process range (`terminal/close`).
  ///
  /// Repeated closes succeed. Cleanup failures leave the terminal in place for
  /// a later retry.
  Future<void> closeTerminal(String sessionId, String terminalId) =>
      _unsupported('closeTerminal');

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

  /// Timed `ask_user_question` calls this Session still holds, from the
  /// `userQuestions` session projection. An [UserQuestionState.open] row is
  /// settled by the ordinary waterfall answer; a
  /// [UserQuestionState.continued] row is not.
  Stream<List<PendingUserQuestion>> observePendingUserQuestions(
    String sessionId,
  ) => Stream.value(const <PendingUserQuestion>[]);

  /// Answer a question whose foreground wait already ended: the host steers
  /// the reply into the agent as a new turn instead of settling the original
  /// call (`userQuestions/answer`).
  Future<void> answerContinuedQuestion(
    String sessionId,
    String callId,
    QuestionEvidence evidence,
  ) => _unsupported('answerContinuedQuestion');

  /// Dismiss a pending question request without answering; the host resolves
  /// the asker's call as cancelled.
  Future<void> cancelQuestions(String requestId, String sessionId) =>
      _unsupported('cancelQuestions');

  Stream<List<WorkspaceSummary>> observeWorkspaces();

  /// Observe live session models (the host model catalog combined with the
  /// session's durable `modelSelection` projection); updates live when any
  /// client selects a model or when the host catalog updates.
  Stream<SessionModels?> observeSessionModels(String sessionId) =>
      const Stream<SessionModels?>.empty();

  /// Registry-global archive set mirrored from the `workspace/follow`
  /// stream's baseline and increment frames — the pinned contract's only
  /// workspace source (there is no unary workspace list).
  Stream<Set<String>> observeArchivedSessionIds() =>
      Stream.value(const <String>{});

  /// Registry-global pin set mirrored from the same stream, most recently
  /// pinned first. Pinned sessions lead their group and the flat list; the
  /// order is the user's own, not the session list's.
  Stream<List<String>> observePinnedSessionIds() =>
      Stream.value(const <String>[]);

  /// A no-op on the pinned contract: the workspace roster is push-only, so
  /// there is nothing to pull. Kept on the interface so a caller's refresh
  /// gesture stays a valid call instead of a compile error.
  Future<void> refreshWorkspaces();

  /// Archive a session without deleting its log or workspace accounting
  /// slot.
  ///
  /// Without [stopActivity] the Host refuses a session that still has
  /// running work by throwing [SessionArchiveRefused], whose activity names
  /// what must stop first; the archive is not written on that path. With
  /// [stopActivity] the Host writes the archive first and then asks its
  /// providers to stop that work, so a stop can never undo the archive, and
  /// the stopped work does not resume on its own. Any other failure throws
  /// as itself — [RepositoryFailure] for a Host refusal, the transport error
  /// otherwise.
  Future<void> archiveSession(String sessionId, {bool stopActivity = false}) =>
      _unsupported('archiveSession');

  /// Restore an archived session (dsh `workspace.unarchiveSession`): the row
  /// returns to every grouping surface in its stored position, and its log
  /// and accounting slot were never lost. Restoring is not notice-worthy —
  /// the row reappearing is the feedback.
  Future<void> unarchiveSession(String sessionId) =>
      _unsupported('unarchiveSession');

  /// Pin a session (dsh `workspace.pinSession`): the row leads its group and
  /// the flat list, at the head of the pinned block, until it is unpinned.
  /// The Host refuses an archived or unknown session with a
  /// [RepositoryFailure]; the pin set is unchanged on that path.
  Future<void> pinSession(String sessionId) => _unsupported('pinSession');

  /// Drop a session's pin (dsh `workspace.unpinSession`): the row returns to
  /// its own saved order. Unpinning a session that is not pinned is not an
  /// error — the call is idempotent, so a lost race resolves as a no-op.
  Future<void> unpinSession(String sessionId) => _unsupported('unpinSession');

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

  /// Stop one running continuable child (`subagent.interrupt`). The verb
  /// exists only for [SubagentMode.continuable] rows — the host pins the
  /// request to that mode and rejects an address that does not own the live
  /// target as `subagent/unauthorized`.
  Future<void> interruptSubagent(String parentSessionId, String childSessionId);

  /// Open one subagent child as a resident, followed transcript.
  ///
  /// [mode] is the addressed row's own catalog mode: a child's address
  /// repeats it and the host rejects a mismatch as `subagent/unauthorized`,
  /// so a one-shot row never opens under the continuable mode (and vice
  /// versa); a child the catalog no longer lists answers `subagent/not-found`.
  ///
  /// After this call the child behaves like any session window —
  /// [observeTimelineWindow], [observeTimeline], [loadOlderHistory] and the
  /// live follow all address it through the same id, so a running child keeps
  /// updating without a reload.
  Future<void> openSubagentSession(
    String parentSessionId,
    String childSessionId,
    SubagentMode mode,
  ) => _unsupported('openSubagentSession');

  /// Follow up with one continuable child (`subagent.prompt`). The verb
  /// exists only for [SubagentMode.continuable] rows — the host pins the
  /// request to that mode and rejects a misaddressed row as
  /// `subagent/unauthorized`.
  Future<String> sendSubagentPrompt(
    String parentSessionId,
    String childSessionId,
    String text,
  );

  Stream<GoalProjection?> observeGoal(String sessionId);

  /// Plan collaboration state; null while the host composes no plan mode.
  Stream<PlanState?> observePlan(String sessionId) => Stream.value(null);

  /// Standing todo list (the `todos` projection: the latest whole
  /// `todo/write` list, cleared at the next `turn/start`); empty stream
  /// while the host composes no todo unit.
  Stream<List<TodoItem>?> observeTodos(String sessionId) =>
      const Stream<List<TodoItem>?>.empty();

  /// Context-occupancy projection for the selected session (pressure +
  /// route capacity); empty until usage records exist.
  Stream<ContextPressure?> observeContextPressure(String sessionId) =>
      const Stream<ContextPressure?>.empty();

  /// Heuristic composition of the context (system / tools / conversation);
  /// empty until any component is priced.
  Stream<ContextBreakdown?> observeContextBreakdown(String sessionId) =>
      const Stream<ContextBreakdown?>.empty();

  /// The session's permission-preset select (the `permissions` session
  /// projection); empty while the host composes no permission service —
  /// surfaces hide their access controls.
  Stream<PermissionSelect?> observePermissions(String sessionId) =>
      const Stream<PermissionSelect?>.empty();

  /// Window-scoped stats for the composer stats line (fallback semantics:
  /// "what is on screen").
  Stream<SessionWindowStats> observeSessionStats(String sessionId) =>
      const Stream<SessionWindowStats>.empty();

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

  /// Read a window of text from a regular file in the session's workspace
  /// (`workspaceFiles/read`).
  Future<WorkspaceFileContent> readWorkspaceFile(
    String sessionId,
    String path, {
    int offset = 1,
    int? limit,
  }) => _unsupported('readWorkspaceFile');

  /// Read a complete file's raw bytes, or one byte window of it
  /// (`workspaceFiles/readBytes`).
  ///
  /// Omitting both [offset] and [length] reads the complete file under the
  /// host's full-file byte cap; supplying either sends a byte range whose first
  /// byte is 0-based. [baseFile] resolves [path] from that file's own
  /// directory, and the host refuses an absolute or scheme-qualified [path]
  /// when [baseFile] is present
  /// (`reference/deepseek-harness/packages/api/workspace-files/src/index.ts:344-348`).
  /// The result's `eof` is the host's answer: true for a whole-file read and
  /// when the window includes the file's last byte.
  Future<WorkspaceFileBytes> readWorkspaceFileBytes(
    String sessionId,
    String path, {
    int? offset,
    int? length,
    String? baseFile,
  }) => _unsupported('readWorkspaceFileBytes');

  /// Inspect a regular file's metadata (`workspaceFiles/stat`).
  Future<WorkspaceFileStat> statWorkspaceFile(String sessionId, String path) =>
      _unsupported('statWorkspaceFile');

  /// List entries in a directory inside the session's workspace
  /// (`workspaceFiles/list`).
  ///
  /// [path] is a workspace path: absolute, or relative to the workspace root,
  /// which `'.'` names — the host refuses an empty string. A listed entry's
  /// path is the listing's own `path` joined with its `name` by `/`.
  Future<WorkspaceDirectoryListing> listWorkspaceDirectory(
    String sessionId,
    String path,
  ) => _unsupported('listWorkspaceDirectory');
}

final class QuestionEvidence {
  const QuestionEvidence({required this.sessionId, required this.answers});

  final String sessionId;
  final List<QuestionAnswer> answers;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QuestionEvidence &&
          other.sessionId == sessionId &&
          _listEquals(other.answers, answers));

  @override
  int get hashCode => Object.hash(sessionId, Object.hashAll(answers));
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
