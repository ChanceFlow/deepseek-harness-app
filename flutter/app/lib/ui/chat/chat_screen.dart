/// Chat screen — Flutter port of the legacy Compose `ChatScreen.kt`.
///
/// Stateless rows stay stateless; interactive rows (queue editing,
/// question drafts, composer, attachments) own their local state, exactly
/// like the Compose `remember` blocks they replace.
library;

import 'dart:async';
import 'dart:convert';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/attachment.dart';
import 'package:domain/model/agent_team.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/command.dart';
import 'package:domain/model/cordis.dart';
import 'package:domain/model/file_reference.dart';
import 'package:domain/model/file_upload.dart';
import 'package:domain/model/goal.dart';
import 'package:domain/model/jobs.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/open_in_app.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/permission_select.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/sandbox.dart';
import 'package:domain/model/todo.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/session_reference.dart';
import 'package:domain/model/skills.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/token_usage.dart';
import 'package:domain/model/user_question.dart';
import 'package:domain/model/workspace_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../di/providers.dart';
import '../../local_state/local_state_providers.dart';
import '../../platform/document_picker.dart';
import '../shared/error_banner.dart';
import 'card_detail.dart';
import 'chat_error_banner.dart';
import 'chat_ui_state.dart';
import 'chat_local_state.dart';
import 'command_roster.dart';
import 'diff_line_list.dart';
import 'file_reference_picker.dart';
import 'host_unreachable_banner.dart';
import 'file_preview_sheet.dart';
import 'markdown/markdown_text.dart';
import 'markdown/plain_text.dart';
import 'plan_detail_surface.dart';
import 'tool_detail_surface.dart';
import 'job_list_action.dart';
import 'message_icon_actions.dart';
import 'message_run_metrics.dart';
import 'model_select.dart';
import 'permission_select.dart';
import 'presented_files_row.dart';
import 'produced_files_row.dart';
import 'session_log_export_action.dart';
import 'session_panel.dart';
import 'tool_images.dart';
import 'turn_files.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../subagents/subagent_controller.dart';
import 'approval_panel.dart';
import 'cordis_request_panel.dart';
import '../subagents/subagent_route.dart';

import 'activity_dot.dart';
import 'context_ring.dart';
import 'hook_audit_row.dart';
import 'sandbox_mode_fact.dart';
import 'schedule_reminder_strip.dart';
import 'stats_line.dart';
import '../shared/dock_anchor.dart';
import '../shared/error_view.dart';
import '../shared/menu_sheet.dart';
import '../shared/tappable_feedback.dart';
import 'empty_hero.dart';
import 'preset_seat.dart';
import 'reasoning_row.dart';
import 'sweep_highlight.dart';
import '../teams/team_action.dart';
import '../terminal/terminal_screen.dart';
import '../trajectory/trajectory_entry.dart';
import 'timeline_folding.dart';
import 'timeline_grouping.dart';
import 'todo_panel.dart';
import 'process_activity.dart';
import 'run_duration.dart';
import 'disclosure_row.dart';
import '../shared/menu_material.dart';
import 'process_disclosure.dart';
import 'transcript_view_mode.dart';
import 'turn_process.dart';
import 'tool_row_model.dart';
import 'running_status_row.dart';
import 'workflow_run_row.dart';
import '../theme/theme.dart';

// The sidebar widget lives in session_panel.dart; re-exported so existing
// importers of this library keep resolving `SessionPanel` unchanged.
export 'session_panel.dart';
export 'timeline_folding.dart'
    show TimelineActivityGroup, foldTimelineActivities;

/// Decodes one durable attachment lazily; returns null on any failure.
typedef AttachmentLoader = Future<Uint8List?> Function(
  String sessionId,
  AttachmentRef ref,
);

/// The serving desktop's registered applications for one workspace path
/// (dsh `session/workspacePathApplications`), read when the Open workspace
/// verb is used. A failure propagates: the verb then falls back to the
/// operating system's own default association.
typedef WorkspacePathApplicationsLoader =
    Future<List<WorkspacePathApplication>> Function(String path);

/// Bare pumps own no host: with no registered applications the verb still
/// opens through the operating system default, which is what a bare pump
/// asserting the verb's presence needs.
Future<List<WorkspacePathApplication>> _noWorkspacePathApplications(
  String path,
) async => const <WorkspacePathApplication>[];

/// Bare pumps own no repository: a durable image stays a placeholder frame.
Future<Uint8List?> _noAttachmentBytes(String sessionId, AttachmentRef ref) =>
    Future<Uint8List?>.value();

/// Bare pumps own no jobs: an expanded row reports no output rather than
/// reaching for a connection the test never wired.
Stream<JobOutputFrame> _noJobOutput(
  String sessionId,
  String jobId, {
  int? resumeFrom,
}) => const Stream<JobOutputFrame>.empty();

Future<bool> _noJobKill(String sessionId, String jobId) async => false;

/// Bare pumps own no team: a member row is inert.
void _noTeamMember(String leadSessionId, TeamMember member) {}

class ChatRoute extends ConsumerWidget {
  const ChatRoute({super.key, this.backendId});

  /// The backend this surface presents; null uses the active backend
  /// (the tab's default).
  final String? backendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watching the keep-alive here pins every configured backend's
    // connection for the app's lifetime.
    ref.watch(allBackendConnectionsProvider);
    final resolved = backendId ?? ref.watch(activeBackendIdProvider).value;
    if (resolved == null || resolved.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final controller = ref.watch(chatControllerProvider(resolved));
    // Every configured backend's browsing slice. The slices provider
    // selects the roster facts out of each host's chat state, so a
    // streaming publish on any backend (each backend's restored session
    // streams while the app is open) recomputes nothing here — only a
    // real roster or registry change rebuilds this route.
    final slices = ref.watch(backendSessionSlicesProvider(resolved));
    // The connection banner's facts: the host's label (or authority) and
    // its phase. Reading the domain-state provider keeps the adapter's
    // connection manager out of the UI layer.
    final backend = ref.watch(backendByIdProvider(resolved));
    final connection = ref.watch(backendConnectionStateProvider(resolved));
    final l10n = AppLocalizations.of(context)!;
    final hostLabel = () {
      final label = backend?.label.trim() ?? '';
      if (label.isNotEmpty) return label;
      return backend?.baseUri.authority ?? resolved;
    }();
    final reconnectUri = backend?.baseUri;
    // The Host's transcript view mode, and the policy it selects. A Host that
    // has not answered yet reads as the client default, so the transcript
    // keeps today's fold until the document says otherwise.
    final transcriptView =
        ref.watch(transcriptViewModeProvider(resolved)).value ??
        kDefaultTranscriptViewMode;
    return ref
        .watch(chatUiStateProvider(resolved))
        .when(
          data: (uiState) => Column(
            children: [
              HostUnreachableBanner(
                key: ValueKey('connection-banner:$resolved'),
                hostLabel: hostLabel,
                phase: connection.value?.phase,
                onReconnect: reconnectUri == null
                    ? null
                    : () => ref.invalidate(
                        backendConnectionProvider((resolved, reconnectUri)),
                      ),
              ),
              Expanded(
                child: ChatScreen(
                  uiState: uiState,
                  presentation: presentationPolicyFor(transcriptView),
                  onAction: controller.onAction,
                  loadAttachment: controller.loadAttachmentBytes,
                  observeJobOutput: controller.observeJobOutput,
                  killJob: controller.killJob,
                  jobRoster: controller.uiState.map(
                    (ChatUiState state) => state.jobs,
                  ),
                  readWorkspaceFile: controller.readWorkspaceFile,
                  readWorkspaceFileBytes: controller.readWorkspaceFileBytes,
                  loadPermissionCatalog: controller.loadPermissionPresetCatalog,
                  loadWorkspacePathApplications:
                      controller.workspacePathApplications,
                  backendId: resolved,
                  backendSlices: slices,
                  onRefreshModels: controller.refreshModels,
                  onSelectBackend: (backendId) => ref
                      .read(backendRegistryProvider.future)
                      .then(
                        (registry) =>
                            registry.onAction(SelectBackend(backendId)),
                      ),
                  onSelectBackendSession: (backendId, sessionId) {
                    if (backendId == resolved) {
                      controller.onAction(SelectSession(sessionId));
                      return;
                    }
                    // Switch the registry first, then select on the target
                    // backend's own controller — the chat surface rebinds to
                    // it with the session already chosen.
                    unawaited(
                      ref
                          .read(backendRegistryProvider.future)
                          .then(
                            (registry) =>
                                registry.onAction(SelectBackend(backendId)),
                          ),
                    );
                    ref
                        .read(chatControllerProvider(backendId))
                        .onAction(SelectSession(sessionId));
                  },
                  // Web SessionNodeItem session verbs (sidebar long-press):
                  // dispatch on whichever backend owns the row.
                  dispatchSessionAction: (backendId, action) => ref
                      .read(chatControllerProvider(backendId))
                      .onAction(action),
                  // Sidebar project-header long-press: a new session in
                  // that workspace. Another host's group switches the
                  // presented backend first, so the session it mints is
                  // the one the chat surface shows.
                  onCreateSessionInWorkspace: (backendId, workspaceId) {
                    if (backendId != resolved) {
                      unawaited(
                        ref
                            .read(backendRegistryProvider.future)
                            .then(
                              (registry) =>
                                  registry.onAction(SelectBackend(backendId)),
                            ),
                      );
                    }
                    ref
                        .read(chatControllerProvider(backendId))
                        .onAction(CreateSessionInWorkspace(workspaceId));
                  },
                ),
              ),
            ],
          ),
          // A failed chat-state stream is a localized sentence with a
          // retry, never a raw exception dump.
          error: (error, _) => Scaffold(
            body: Center(
              child: LocalizedErrorView(
                message: l10n.chatLoadFailed,
                onRetry: () {
                  ref.invalidate(chatControllerProvider(resolved));
                  ref.invalidate(chatUiStateProvider(resolved));
                },
              ),
            ),
          ),
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
        );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.uiState,
    required this.onAction,
    super.key,
    this.loadAttachment = _noAttachment,
    this.observeJobOutput = _noJobOutput,
    this.killJob = _noJobKill,
    this.jobRoster = const Stream<List<JobView>>.empty(),
    this.onOpenTeamMember = _noTeamMember,
    this.readWorkspaceFile = _noWorkspaceFileRead,
    this.readWorkspaceFileBytes = _noWorkspaceFileBytes,
    this.loadWorkspacePathApplications = _noWorkspacePathApplications,
    this.loadPermissionCatalog,
    this.onRefreshModels,
    this.backendId,
    this.localState,
    this.backendSlices,
    this.onSelectBackend,
    this.onSelectBackendSession,
    this.dispatchSessionAction,
    this.onCreateSessionInWorkspace,
    this.presentation = kDefaultChatPresentationPolicy,
  });

  final ChatUiState uiState;
  final void Function(ChatAction) onAction;
  final AttachmentLoader loadAttachment;

  /// The transcript view policy this screen folds by: a completed Turn folds
  /// unless the Host's mode disables folding (only `verbose` does). The route
  /// resolves the mode and passes the policy; no widget below reads the
  /// settings surface directly.
  final ChatPresentationPolicy presentation;

  /// Repository seam for the background-jobs sheet's observation stream
  /// (`job/follow`) and its stop (`job/kill`); the sheet owns the stream's
  /// lifetime, opening it on expand and cancelling on collapse.
  final JobOutputObserver observeJobOutput;
  final JobKiller killJob;

  /// The live job roster the sheet follows; a bare pump leaves it empty and
  /// the sheet renders the `uiState` snapshot it was opened with.
  final Stream<List<JobView>> jobRoster;

  /// Opens one Agent-Team member's conversation (the Lead session, or a
  /// teammate's addressed child).
  final void Function(String leadSessionId, TeamMember member) onOpenTeamMember;

  /// Repository seam for the file-preview sheet (`workspaceFiles/read`).
  final WorkspaceFileReader readWorkspaceFile;

  /// Repository seam for the file-preview sheet's byte reads
  /// (`workspaceFiles/readBytes`).
  final WorkspaceFileBytesReader readWorkspaceFileBytes;

  /// Repository seam for the access-mode seat's option list
  /// (`permissionPresets/catalog`): the `permissions` Session projection
  /// carries the current value only, so the seat reads its presets here
  /// (`interaction/permission-presets/src/types.ts:36-41`). Null on a bare
  /// pump: the sheet then states that it could not read the modes.
  final PermissionCatalogLoader? loadPermissionCatalog;

  /// Repository seam for the Open workspace verb's application query
  /// (`session/workspacePathApplications`).
  final WorkspacePathApplicationsLoader loadWorkspacePathApplications;

  /// The backend this surface presents (drives pushed session-tool
  /// pages); null falls back to the active backend at push time.
  final String? backendId;

  /// Composer model seat refresh (re-pulls the session directory).
  final VoidCallback? onRefreshModels;

  /// Chat-surface persistence (drafts, reading offsets, expansion
  /// states, busy-send preference); null disables all of them.
  final ChatLocalState? localState;

  /// Every configured backend's sidebar slice; more than one switches
  /// the sidebar into backend-grouped form. Null keeps the flat
  /// single-host tree (bare pumps and single-backend builds).
  final List<BackendSessionSlice>? backendSlices;

  /// Backend header tap in the sidebar: makes that backend active.
  final void Function(String backendId)? onSelectBackend;

  /// Session tap under any backend's sidebar slice (the active backend
  /// reduces to a plain SelectSession).
  final void Function(String backendId, String sessionId)?
  onSelectBackendSession;

  /// Web SessionNodeItem session verbs (sidebar long-press): dispatch one
  /// ChatAction on whichever backend owns the row (rename's dialog is
  /// owned here).
  final void Function(String backendId, ChatAction action)?
  dispatchSessionAction;

  /// Sidebar project-header long-press: create a session in that
  /// workspace on its owning backend (the Web ProjectRowItem new-session
  /// verb, reached by long-press on the browsing surfaces).
  final void Function(String backendId, String workspaceId)?
  onCreateSessionInWorkspace;

  static Future<Uint8List?> _noAttachment(String sessionId, AttachmentRef ref) {
    return Future<Uint8List?>.value();
  }

  /// Bare pumps own no repository: a preview opened without a real reader
  /// surfaces the localized failure instead of silently doing nothing.
  static Future<WorkspaceFileContent> _noWorkspaceFileRead(
    String sessionId,
    String path,
  ) async {
    throw UnsupportedError('workspaceFiles/read is not wired');
  }

  /// Bare pumps own no repository: an image preview opened without a real byte
  /// reader surfaces the localized failure instead of rendering nothing.
  static Future<WorkspaceFileBytes> _noWorkspaceFileBytes(
    String sessionId,
    String path,
  ) async {
    throw UnsupportedError('workspaceFiles/readBytes is not wired');
  }

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  bool _rail = false;

  /// Shared-store persistence resolved from the enclosing
  /// [ProviderScope]; a [ChatScreen] mounted without a scope (bare test
  /// pumps) keeps persistence off.
  ChatLocalState? _resolvedLocalState;
  bool _localStateResolveStarted = false;

  ChatLocalState? get _effectiveLocalState =>
      widget.localState ?? _resolvedLocalState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_resolveLocalState());
  }

  /// Resolve the shared [LocalStateStore] once: every surface must write
  /// the same instance, or the whole-document flushes overwrite each
  /// other's keys.
  Future<void> _resolveLocalState() async {
    if (widget.localState != null || _localStateResolveStarted) return;
    _localStateResolveStarted = true;
    ProviderContainer container;
    try {
      container = ProviderScope.containerOf(context, listen: false);
    } catch (_) {
      // No scope above: drafts and offsets stay in memory only.
      return;
    }
    try {
      final store = await container.read(localStateStoreProvider.future);
      if (mounted && widget.localState == null && _resolvedLocalState == null) {
        setState(() => _resolvedLocalState = StoreChatLocalState(store));
      }
    } catch (_) {
      // An unreadable documents directory leaves persistence off.
    }
  }

  /// Subagent tool page (web embeds it into conversation context;
  /// mobile pushes it as a route with the current session preloaded).
  /// One team member's conversation, on the same surface the subagent
  /// catalog pushes: the Lead is this conversation's own session (or its
  /// parent), and a teammate is its addressed child. Without a backend (a
  /// bare pump) there is no repository to address, so the row stays read-only.
  void _openTeamMember(String leadSessionId, TeamMember member) {
    final backendId = widget.backendId;
    if (backendId == null) return;
    if (member.isLead) {
      widget.onAction(SelectSession(leadSessionId));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SubagentRecordRoute(
          backendId: backendId,
          initialSessionId: leadSessionId,
          initialChildId: member.id,
        ),
      ),
    );
  }

  void _openSubagents() {
    final sessionId = widget.uiState.selectedSessionId;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (scopeContext) {
          final backendId = widget.backendId;
          if (sessionId == null || backendId == null) {
            return const SubagentRoute();
          }
          return ProviderScope(
            overrides: [
              subagentControllerProvider(backendId).overrideWith(
                (ref) => SubagentController(
                  ref.watch(chatRepositoryProvider(backendId)),
                  initialSessionId: sessionId,
                ),
              ),
            ],
            child: const SubagentRoute(),
          );
        },
      ),
    );
  }

  /// Web SessionNodeItem "Rename session" (sidebar long-press verb):
  /// opens the session rename dialog and dispatches through the
  /// backend-aware action callback.
  void _dispatchRenameSession(String backendId, String sessionId) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => _RenameSessionDialog(
          onSave: (title) {
            widget.dispatchSessionAction?.call(
              backendId,
              RenameSession(sessionId, title),
            );
          },
        ),
      ),
    );
  }

  /// Web SessionNodeItem "Fork session" (sidebar long-press verb):
  /// commits directly on the owning backend's controller.
  void _dispatchForkSession(String backendId, String sessionId) {
    widget.dispatchSessionAction?.call(backendId, ForkSession(sessionId));
  }

  /// Web SessionNodeItem "Archive session" (sidebar long-press verb): the
  /// reference archives a quiet session outright — the undo notice is the
  /// safety net, and only the Host's running-work refusal asks first (raised
  /// by the app root from the refusal itself).
  void _dispatchArchiveSession(String backendId, String sessionId) {
    widget.dispatchSessionAction?.call(backendId, ArchiveSession(sessionId));
  }

  /// Web SessionNodeItem "Unarchive session" (an archived row's own verb):
  /// restores it on whichever backend owns the row.
  void _dispatchUnarchiveSession(String backendId, String sessionId) {
    widget.dispatchSessionAction?.call(backendId, UnarchiveSession(sessionId));
  }

  /// Web PinSessionMenuItem: lifts the row into its group's pin block, or
  /// drops it back to its own order. Both run on the backend that owns the
  /// row, like every other session verb.
  void _dispatchPinSession(String backendId, String sessionId) {
    widget.dispatchSessionAction?.call(backendId, PinSession(sessionId));
  }

  void _dispatchUnpinSession(String backendId, String sessionId) {
    widget.dispatchSessionAction?.call(backendId, UnpinSession(sessionId));
  }

  /// One create from the drawer's New session bar — its dialog's Default
  /// seat mints an unaccounted session, so the workspace id may be null. The
  /// session is minted behind the drawer, so the drawer closes and the reader
  /// lands on it, the way a row tap lands them on theirs.
  void _createSessionFromDrawer(
    BuildContext drawerContext,
    String? workspaceId,
  ) {
    widget.onAction(CreateSessionInWorkspace(workspaceId));
    Scaffold.of(drawerContext).closeDrawer();
  }

  /// One create from a drawer project header's long-press, which always
  /// names its workspace. The panel's own routing survives: the
  /// backend-aware verb when the surface was given one, the active
  /// controller's verb otherwise.
  void _createSessionInWorkspaceFromDrawer(
    BuildContext drawerContext,
    String backendId,
    String workspaceId,
  ) {
    final create = widget.onCreateSessionInWorkspace;
    if (create != null) {
      create(backendId, workspaceId);
    } else {
      widget.onAction(CreateSessionInWorkspace(workspaceId));
    }
    Scaffold.of(drawerContext).closeDrawer();
  }

  PreferredSizeWidget _chatAppBar(
    BuildContext context,
    ChatUiState uiState,
    void Function(ChatAction) onAction, {
    required bool compact,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final sessionId = uiState.selectedSessionId;
    final session = uiState.sessions
        .where((item) => item.id == sessionId)
        .firstOrNull;
    // A blank session has no identity to report, and its workspace is
    // already the hero's subject: naming it twice on one screen is the
    // duplication the bar was redesigned to end.
    final title = session == null || session.blank
        ? l10n.appTitle
        : session.displayTitle;
    final contextLine = session != null && session.blank
        ? null
        : sessionContextLine(session, uiState.models);
    return AppBar(
      // Web's third preset surface: the read-only label naming the
      // preset this session runs, beside the title.
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: contextLine == null
                ? Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        contextLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 8),
          AgentPresetHeaderLabel(
            session: uiState.sessions
                .where((item) => item.id == sessionId)
                .firstOrNull,
            roster: uiState.agentPresets,
          ),
        ],
      ),
      actions: [
        ChatHeaderActions(
          uiState: uiState,
          onAction: onAction,
          backendId: widget.backendId,
          observeJobOutput: widget.observeJobOutput,
          killJob: widget.killJob,
          jobRoster: widget.jobRoster,
          onOpenTeamMember: _openTeamMember,
          onOpenSubagents: _openSubagents,
          compact: compact,
          loadWorkspaceApplications: widget.loadWorkspacePathApplications,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final uiState = widget.uiState;
    final onAction = widget.onAction;
    return LayoutBuilder(
      builder: (context, constraints) {
        // A phone in landscape clears the width breakpoint (780x390) while
        // standing only 390dp tall: the pane split would spend 320dp of that
        // on a sidebar and leave the transcript a ~100dp slit, so the split
        // waits for a surface that has the height to carry it.
        final useTwoPanes =
            constraints.maxWidth >= kTwoPaneMinWidth &&
            constraints.maxHeight >= kTwoPaneMinHeight;
        if (useTwoPanes) {
          return Scaffold(
            appBar: _chatAppBar(context, uiState, onAction, compact: false),
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        AnimatedContainer(
                          // The sidebar's one slide: width tweens between
                          // the wide pane and the rail when the panel's
                          // toggle flips (the panel itself reports the
                          // state through onRailChanged). The 200ms
                          // ease-in-out is a recorded per-change decision —
                          // the default linear reads as a snap at both
                          // ends of a row this wide.
                          duration: DshMotion.durationShort,
                          curve: DshMotion.curveStandard,
                          width: _rail ? kRailWidth : kSidebarWidth,
                          child: SessionPanel(
                            onRailChanged: (rail) =>
                                setState(() => _rail = rail),
                            sessions: uiState.sessions,
                            workspaces: uiState.workspaces,
                            searchResults: uiState.searchResults,
                            selectedSessionId: uiState.selectedSessionId,
                            onSelectSession: (id) =>
                                onAction(SelectSession(id)),
                            onCreateSession: (workspaceId) =>
                                onAction(CreateSessionInWorkspace(workspaceId)),
                            onSearchSessions: (query) =>
                                onAction(SearchSessions(query)),
                            backendSlices: widget.backendSlices,
                            onSelectBackend: widget.onSelectBackend,
                            onSelectBackendSession:
                                widget.onSelectBackendSession,
                            backendId: widget.backendId,
                            onRenameSession: _dispatchRenameSession,
                            onForkSession: _dispatchForkSession,
                            onArchiveSession: _dispatchArchiveSession,
                            onUnarchiveSession: _dispatchUnarchiveSession,
                            onPinSession: _dispatchPinSession,
                            onUnpinSession: _dispatchUnpinSession,
                            pinnedSessionIds: uiState.pinnedSessionIds,
                            onCreateSessionInWorkspace:
                                widget.onCreateSessionInWorkspace,
                          ),
                        ),
                        Expanded(
                          child: ChatPanel(
                            uiState: uiState,
                            presentation: widget.presentation,
                            onAction: onAction,
                            loadAttachment: widget.loadAttachment,
                            readWorkspaceFile: widget.readWorkspaceFile,
                            readWorkspaceFileBytes:
                                widget.readWorkspaceFileBytes,
                            loadPermissionCatalog: widget.loadPermissionCatalog,
                            models: uiState.models,
                            onSelectModel: (selection) =>
                                onAction(SelectModelSeat(selection)),
                            onRefreshModels: widget.onRefreshModels,
                            localState: _effectiveLocalState,
                            backendId: widget.backendId,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        // Compact: the session panel lives in a drawer (web's narrow
        // viewport overlay-sidebar semantics), not a stacked strip.
        return Scaffold(
          appBar: _chatAppBar(context, uiState, onAction, compact: true),
          drawer: Drawer(
            width: kSidebarWidth,
            // Chrome tone: the drawer is the same frame family as the bar
            // and the dock, so it takes their surface rather than the
            // stock drawer's own step.
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            child: SafeArea(
              // The drawer's own context: both create verbs — the New
              // session bar's dialog and the project header's long-press —
              // mint a session behind the drawer, so the drawer closes and
              // the reader lands on it the way a row tap lands on theirs.
              // A dialog opened by the bar is a route of its own and pops
              // itself; closing the drawer under it is independent of that.
              child: Builder(
                builder: (drawerContext) => SessionPanel(
                  inDrawer: true,
                  sessions: uiState.sessions,
                  workspaces: uiState.workspaces,
                  searchResults: uiState.searchResults,
                  selectedSessionId: uiState.selectedSessionId,
                  onSelectSession: (id) {
                    onAction(SelectSession(id));
                    Navigator.of(context).pop();
                  },
                  onCreateSession: (workspaceId) =>
                      _createSessionFromDrawer(drawerContext, workspaceId),
                  onSearchSessions: (query) => onAction(SearchSessions(query)),
                  backendSlices: widget.backendSlices,
                  onSelectBackend: (backendId) {
                    widget.onSelectBackend?.call(backendId);
                    Navigator.of(context).pop();
                  },
                  onSelectBackendSession: (backendId, sessionId) {
                    widget.onSelectBackendSession?.call(backendId, sessionId);
                    Navigator.of(context).pop();
                  },
                  backendId: widget.backendId,
                  onRenameSession: _dispatchRenameSession,
                  onForkSession: _dispatchForkSession,
                  onArchiveSession: _dispatchArchiveSession,
                  onUnarchiveSession: _dispatchUnarchiveSession,
                  onPinSession: _dispatchPinSession,
                  onUnpinSession: _dispatchUnpinSession,
                  pinnedSessionIds: uiState.pinnedSessionIds,
                  onCreateSessionInWorkspace: (backendId, workspaceId) =>
                      _createSessionInWorkspaceFromDrawer(
                        drawerContext,
                        backendId,
                        workspaceId,
                      ),
                ),
              ),
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ChatPanel(
                    uiState: uiState,
                    presentation: widget.presentation,
                    onAction: onAction,
                    loadAttachment: widget.loadAttachment,
                    readWorkspaceFile: widget.readWorkspaceFile,
                    readWorkspaceFileBytes: widget.readWorkspaceFileBytes,
                    loadPermissionCatalog: widget.loadPermissionCatalog,
                    models: uiState.models,
                    onSelectModel: (selection) =>
                        onAction(SelectModelSeat(selection)),
                    onRefreshModels: widget.onRefreshModels,
                    localState: _effectiveLocalState,
                    backendId: widget.backendId,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The app bar's second line: the workspace this session runs in and the
/// model answering in it, "·"-joined. The workspace drops out when the
/// title already names it — an untitled session falls back to its cwd
/// basename, and repeating it under itself says nothing. Null when neither
/// fact is known, which is the signal to render a single-line title.
String? sessionContextLine(SessionSummary? session, SessionModels? models) {
  final parts = <String>[];
  final titled = session?.title?.trim().isNotEmpty ?? false;
  final cwd = session?.cwd;
  if (titled && cwd != null) {
    final segments = cwd.split(RegExp(r'[/\\]'));
    for (final segment in segments.reversed) {
      if (segment.trim().isEmpty) continue;
      parts.add(segment);
      break;
    }
  }
  final model = modelDisplayName(models);
  if (model != null) parts.add(model);
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Icon actions for the chat header (web header-action form).
class ChatHeaderActions extends StatelessWidget {
  const ChatHeaderActions({
    required this.uiState,
    required this.onAction,
    required this.observeJobOutput,
    required this.killJob,
    required this.jobRoster,
    required this.onOpenTeamMember,
    super.key,
    this.backendId,
    this.onOpenSubagents,
    this.loadWorkspaceApplications = _noWorkspacePathApplications,
    this.compact = false,
  });

  final ChatUiState uiState;
  final void Function(ChatAction) onAction;

  /// The background-jobs sheet's repository seams (`job/follow`, `job/kill`)
  /// and the live roster it follows.
  final JobOutputObserver observeJobOutput;
  final JobKiller killJob;
  final Stream<List<JobView>> jobRoster;

  /// Opens one Agent-Team member's conversation.
  final void Function(String leadSessionId, TeamMember member) onOpenTeamMember;

  /// The host this bar belongs to; the trajectory ledger needs it to scope
  /// its controller. Null while no host is resolved, which also hides the
  /// ledger seat.
  final String? backendId;

  /// Phone bars carry the glanceable seats — running jobs — and fold the
  /// session verbs into an overflow menu; a 400dp bar cannot spend six
  /// icon seats and still name the session.
  final bool compact;

  /// Web SubagentCatalogAction seat: opens the subagent catalog for this
  /// session.
  final VoidCallback? onOpenSubagents;

  /// The serving desktop's registered openers for one workspace path
  /// (`session/workspacePathApplications`); read when the Open workspace
  /// verb runs.
  final WorkspacePathApplicationsLoader loadWorkspaceApplications;

  Future<void> _rename(BuildContext context, String sessionId) {
    return showDialog<void>(
      context: context,
      builder: (context) => _RenameSessionDialog(
        onSave: (title) => onAction(RenameSession(sessionId, title)),
      ),
    );
  }

  /// Hand the session's workspace directory to the serving desktop's native
  /// opener (dsh `session/openWorkspacePath`).
  ///
  /// The host's registered applications decide the gesture: exactly one opens
  /// directly through it, none opens through the operating system's own
  /// default association, and more than one lists them in the house menu
  /// sheet. A failed association query falls back to the default open — the
  /// query is an optimization over the OS default, so a host that answers the
  /// availability probe but not the query still opens. The open's own failure
  /// reaches the shared error strip through [onAction]'s controller.
  Future<void> _openWorkspace(BuildContext context, String path) async {
    var applications = const <WorkspacePathApplication>[];
    try {
      applications = await loadWorkspaceApplications(path);
    } catch (_) {
      // Read above: the association query failing leaves the default open.
    }
    if (!context.mounted) return;
    if (applications.length <= 1) {
      onAction(
        OpenWorkspacePath(path, application: applications.firstOrNull?.id),
      );
      return;
    }
    await showMenuSheet<void>(
      context,
      maxHeight: 280,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final scheme = theme.colorScheme;
        final l10n = AppLocalizations.of(sheetContext)!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Text(
                l10n.openWorkspace,
                style: theme.textTheme.titleSmall,
              ),
            ),
            for (final application in applications)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(kShapeChip),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onAction(
                      OpenWorkspacePath(path, application: application.id),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.open_in_new,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            application.name,
                            style: theme.textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (application.isDefault)
                          Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: scheme.primary,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sessionId = uiState.selectedSessionId;
    if (sessionId == null) {
      return const SizedBox.shrink();
    }
    final selectedSession = uiState.sessions
        .where((session) => session.id == sessionId)
        .firstOrNull;
    final archivable = selectedSession?.blank != true;
    // The Open workspace verb needs both facts the host supplies separately:
    // its availability answer and the session's workspace path.
    final openableWorkspacePath = uiState.canOpenWorkspace
        ? selectedSession?.cwd
        : null;
    final hasActiveJobs = uiState.jobs.any(
      (j) => j.status == JobStatus.running,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasActiveJobs || !compact)
          JobListAction(
            jobs: uiState.jobs,
            sessionId: sessionId,
            observeJobOutput: observeJobOutput,
            killJob: killJob,
            jobRoster: jobRoster,
          ),
        if (backendId case final host?)
          TeamAction(
            backendId: host,
            sessionId: sessionId,
            onOpenMember: onOpenTeamMember,
          ),
        if (!compact) ...[
          if (openableWorkspacePath case final path?)
            IconButton(
              tooltip: l10n.openWorkspace,
              onPressed: () => unawaited(_openWorkspace(context, path)),
              icon: const Icon(Icons.open_in_new),
            ),
          SessionLogExportAction(uiState: uiState, onAction: onAction),
          if (uiState.selectedSessionId case final sessionId?)
            if (backendId case final host?)
              TrajectoryEntryButton(backendId: host, sessionId: sessionId),
        ],
        if (compact)
          PopupMenuButton<_SessionVerb>(
            tooltip: l10n.sessionMenuTooltip,
            icon: const Icon(Icons.more_vert),
            onSelected: (verb) {
              switch (verb) {
                case _SessionVerb.trajectory:
                  if (backendId != null) {
                    openTrajectoryLedger(
                      context,
                      backendId: backendId!,
                      sessionId: sessionId,
                    );
                  }
                case _SessionVerb.terminal:
                  if (backendId case final host?) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TerminalRoute(
                          backendId: host,
                          sessionId: sessionId,
                        ),
                      ),
                    );
                  }
                case _SessionVerb.export:
                  onAction(ExportSessionLog(sessionId));
                case _SessionVerb.subagents:
                  onOpenSubagents?.call();
                case _SessionVerb.rename:
                  unawaited(_rename(context, sessionId));
                case _SessionVerb.fork:
                  onAction(ForkSession(sessionId));
                case _SessionVerb.archive:
                  onAction(ArchiveSession(sessionId));
                case _SessionVerb.openWorkspace:
                  if (openableWorkspacePath case final path?) {
                    unawaited(_openWorkspace(context, path));
                  }
              }
            },
            itemBuilder: (context) => [
              if (backendId != null)
                PopupMenuItem(
                  value: _SessionVerb.trajectory,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.route_outlined),
                    title: Text(l10n.trajectoryEntryTooltip),
                  ),
                ),
              if (backendId != null)
                PopupMenuItem(
                  value: _SessionVerb.terminal,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.terminal),
                    title: Text(l10n.terminalEntryTooltip),
                  ),
                ),
              if (uiState.canExportSessionLog)
                PopupMenuItem(
                  value: _SessionVerb.export,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.file_download_outlined),
                    title: Text(l10n.sessionLogExportTooltip),
                  ),
                ),
              if (onOpenSubagents != null)
                PopupMenuItem(
                  value: _SessionVerb.subagents,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.account_tree_outlined),
                    title: Text(l10n.subagentsTooltip),
                  ),
                ),
              PopupMenuItem(
                value: _SessionVerb.rename,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(l10n.renameSession),
                ),
              ),
              PopupMenuItem(
                value: _SessionVerb.fork,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.call_split_outlined),
                  title: Text(l10n.forkSession),
                ),
              ),
              PopupMenuItem(
                value: _SessionVerb.archive,
                enabled: archivable,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: archivable,
                  leading: const Icon(Icons.archive_outlined),
                  title: Text(l10n.archiveSession),
                ),
              ),
              if (openableWorkspacePath != null)
                PopupMenuItem(
                  value: _SessionVerb.openWorkspace,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.open_in_new),
                    title: Text(l10n.openWorkspace),
                  ),
                ),
            ],
          )
        else ...[
          if (onOpenSubagents != null)
            IconButton(
              tooltip: l10n.subagentsTooltip,
              onPressed: onOpenSubagents,
              icon: const Icon(Icons.account_tree_outlined),
            ),
          IconButton(
            tooltip: l10n.renameSession,
            onPressed: () => _rename(context, sessionId),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: l10n.forkSession,
            onPressed: () => onAction(ForkSession(sessionId)),
            icon: const Icon(Icons.call_split_outlined),
          ),
          IconButton(
            tooltip: l10n.archiveSession,
            onPressed: archivable
                ? () => onAction(ArchiveSession(sessionId))
                : null,
            icon: const Icon(Icons.archive_outlined),
          ),
        ],
      ],
    );
  }
}

/// Session verbs the phone bar keeps behind its overflow menu.
enum _SessionVerb {
  trajectory,
  terminal,
  export,
  subagents,
  rename,
  fork,
  archive,
  openWorkspace,
}

/// Sentinel for the turn-status row in the transcript's row list: not a
/// timeline item, only a row the gap math and the builder dispatch on.
const Object _turnStatusSlot = Object();

class _OlderHistorySlot {
  const _OlderHistorySlot();
}

/// Sentinel for the older-history row at the head of the transcript: not a
/// timeline item, only a row the gap math and the builder dispatch on.
const Object _olderHistorySlot = _OlderHistorySlot();

/// Vertical rhythm between two transcript rows — the reference's
/// `--dsh-chat-flow-gap` (`ChatView.module.css:70-95`). A run of steps sits
/// [kChatFlowGapStep] apart and closes up; a message opens a new paragraph at
/// [kChatFlowGap]; a Turn's process control opens its own block at
/// [kChatFlowGapAfterTurnHeader] and holds that clearance on both sides, so the
/// row after it — the first row of its own section, or the next block — is
/// never flush against its hairline (`:91-94`). Equal gaps everywhere read as a
/// list of unrelated lines, which is what the transcript stopped looking like a
/// conversation. The tail signals — the turn-status line and a pending steering
/// row — open their own block like a message does (steering is the reader's own
/// words). A null [below] is the tail: block.
///
/// A Turn's `turn/start` boundary never reaches here: the Turn's process control
/// takes its place in the list, and its hairline rule carries the break the
/// boundary used to. The section's own rows come through here too, with the
/// section handed in as the row above its first member.
double chatFlowGapAfter(Object above, Object? below) {
  if (below == null) return kChatFlowGap;
  // A Turn's process control opens the Turn's own block: its border and its
  // label carry the break, so it takes the header clearance.
  if (below is TurnProcessSection) return kChatFlowGapAfterTurnHeader;
  // The reference gives the sibling that follows a `turn-process` item the same
  // clearance (`ChatView.module.css:93-94`), which is the rule between the
  // control's hairline and everything under it: this port nests the Turn's rows
  // in the section, so that is what keeps them off the rule.
  if (above is TurnProcessSection) return kChatFlowGapAfterTurnHeader;
  final bool aboveIsStep = !_opensBlock(above);
  final bool belowIsStep = !_opensBlock(below);
  return aboveIsStep && belowIsStep ? kChatFlowGapStep : kChatFlowGap;
}

/// Whether a row opens its own paragraph: a message with text, a queued prompt,
/// a Turn's process control, or one of the transcript's tail rows.
bool _opensBlock(Object row) {
  if (row is TimelineMessage) {
    return row.value.text.trim().isNotEmpty;
  }
  return row is SessionQueueItem ||
      row is TurnProcessSection ||
      identical(row, _turnStatusSlot) ||
      identical(row, _olderHistorySlot);
}

/// Share of the chat panel the input dock may occupy. The rest stays with the
/// transcript, which is the surface the reader is reading while a decision
/// waits; the floor is the smallest cap worth giving the dock on a short panel
/// (a landscape phone, or one whose keyboard is open) and the ceiling stops it
/// from swallowing a tall tablet pane.
const double _dockBudgetShare = 0.62;

/// Share the dock may occupy while a decision waits. Answering is the only
/// thing the reader can do with that session, so the decision seat keeps more
/// room than the composer ever needs — enough that its prompt row and its
/// primary action stay on screen on a short phone instead of scrolling out of
/// sight. The detail itself no longer lives here: it opens one surface deeper
/// ([showCardDetailSheet], [showPlanDetail]).
const double _dockDecisionShare = 0.78;
const double _dockMinHeight = 200;
const double _dockMaxHeight = 520;

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    required this.uiState,
    required this.onAction,
    required this.loadAttachment,
    required this.presentation,
    required this.readWorkspaceFile,
    required this.readWorkspaceFileBytes,
    required this.loadPermissionCatalog,
    super.key,
    this.outline = false,
    this.models,
    this.onSelectModel,
    this.onRefreshModels,
    this.localState,
    this.backendId,
  });

  final ChatUiState uiState;
  final void Function(ChatAction) onAction;
  final AttachmentLoader loadAttachment;

  /// The transcript view policy the Turn fold selects from.
  final ChatPresentationPolicy presentation;

  /// Repository seam the file-preview sheet reads through.
  final WorkspaceFileReader readWorkspaceFile;

  /// Repository seam the file-preview sheet reads bytes through.
  final WorkspaceFileBytesReader readWorkspaceFileBytes;

  /// Repository seam the access-mode seat reads its preset list through; null
  /// on a bare pump.
  final PermissionCatalogLoader? loadPermissionCatalog;

  /// The backend this surface presents; drives the pushed subagent record a
  /// workflow member row opens. Null leaves member rows read-only.
  final String? backendId;

  final bool outline;
  final SessionModels? models;
  final void Function(ModelSelection selection)? onSelectModel;
  final VoidCallback? onRefreshModels;

  /// Chat-surface persistence; null disables drafts, reading offsets,
  /// expansion states, and the busy-send preference.
  final ChatLocalState? localState;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  /// Binds the dock element so sheets opened from composer seats can
  /// measure it and float above it (see DockAnchor).
  final GlobalKey _dockKey = GlobalKey();

  /// Web ChatView follow contract: while the reader sits within
  /// [kFollowThreshold] of the bottom the view is "pinned" and follows new
  /// content; a new trailing user node force-scrolls regardless.
  static const double kFollowThreshold = 24;

  final ScrollController _timelineScroll = ScrollController();
  bool _pinned = true;
  int _followDepth = 0;
  bool _needsInitialJump = false;
  String? _lastFollowSignature;
  String? _lastTrailingUserKey;

  /// The reader sits away from the bottom and the jump-to-bottom FAB shows.
  bool _showJumpToBottom = false;

  /// Session-scoped persistence view of the selected session.
  ChatSessionLocalState? _sessionState;

  /// Busy-send preference resolved from [ChatLocalState]; 'steer' routes
  /// the send action through the steering window while a turn runs.
  bool _busyEnterSteer = false;

  /// Reading-position restore for the armed initial jump: the saved
  /// offset, and whether the restore read has settled (a null seam or an
  /// actively running session skips straight to bottom).
  double? _restoredOffset;
  bool _restoreDecided = true;

  /// Distance from the top of the transcript within which scrolling up
  /// automatically triggers background paging of earlier history.
  static const double kAutoLoadOlderThreshold = 160.0;

  /// Single-flight guard preventing multiple auto-load dispatches per scroll burst.
  bool _autoLoadDispatched = false;

  /// Distance from the bottom of the timeline before older history was requested.
  /// Preserved across prepended-item layout to anchor viewport reading position.
  double? _anchorDistanceFromBottom;

  /// Debounced reading-position write; the last observed pixels ride
  /// along so a switch or dispose can flush them for the leaving session.
  Timer? _readOffsetSave;
  double? _pendingReadOffset;

  @override
  void initState() {
    super.initState();
    _timelineScroll.addListener(_onTimelineScroll);
    _bindSession();
    // First mount lands at the bottom like the web's restore-or-bottom.
    _scheduleFollow();
  }

  /// One workflow member's child transcript, on the same subagent surface
  /// the catalog pushes: the route opens the parent's tree and lands on the
  /// member's record once its catalog row supplies the mode the
  /// child-history read requires. Without a backend (a bare pump) there is
  /// no repository to address, so the card stays read-only.
  void _openWorkflowMember(WorkflowMember member) {
    final backendId = widget.backendId;
    final sessionId = widget.uiState.selectedSessionId;
    if (backendId == null || sessionId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SubagentRecordRoute(
          backendId: backendId,
          initialSessionId: sessionId,
          initialChildId: member.childId,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _flushReadOffset();
    _readOffsetSave?.cancel();
    _timelineScroll.removeListener(_onTimelineScroll);
    _timelineScroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Compose remembered these with selectedSessionId as the key.
    final selectionChanged =
        oldWidget.uiState.selectedSessionId != widget.uiState.selectedSessionId;
    // The notification entry can ask for the session that is already on
    // screen; the id is unchanged there, so the request counter is what
    // makes the tap observable (and lets it land on the newest content).
    final latestRequested =
        widget.uiState.selectionLandsAtLatest &&
        oldWidget.uiState.selectionRequestSeq !=
            widget.uiState.selectionRequestSeq;
    if (selectionChanged || latestRequested) {
      _flushReadOffset();
      _readOffsetSave?.cancel();
      _readOffsetSave = null;
      _pinned = true;
      _showJumpToBottom = false;
      _lastFollowSignature = null;
      _lastTrailingUserKey = null;
      _anchorDistanceFromBottom = null;
      _autoLoadDispatched = false;
      _bindSession(landAtLatest: widget.uiState.selectionLandsAtLatest);
      _scheduleFollow();
      return;
    }
    if (oldWidget.localState != widget.localState) {
      _bindSession();
      return;
    }
    // The busy-send preference is live: the settings row can flip it
    // mid-session, and the send action must follow on its next use.
    unawaited(
      widget.localState?.busyEnterBehavior().then((behavior) {
        if (!mounted) return;
        final steer = behavior == kBusyEnterSteer;
        if (steer != _busyEnterSteer) {
          setState(() => _busyEnterSteer = steer);
        }
      }),
    );
    // Own words must be visible: a new trailing user node force-scrolls
    // (send lives in the composer, so arrival is detected here) — never
    // the first laid-out frame of a session, whose jump is the
    // restore-or-bottom landing.
    final trailingUser = _trailingUserKey;
    final appendedUser =
        _lastFollowSignature != null &&
        trailingUser != null &&
        trailingUser != _lastTrailingUserKey;
    _lastTrailingUserKey = trailingUser;
    // Follow new flow content while pinned; do NOT re-pin on every rebuild
    // merely because the offset happens to sit at the bottom.
    final signature = _followSignature();
    final tipMoved = signature != _lastFollowSignature;
    _lastFollowSignature = signature;
    if (_needsInitialJump || appendedUser || (tipMoved && _pinned)) {
      _scheduleFollow();
    }
    // Seamless viewport anchoring: when older history arrives above,
    // adjust scroll offset by the expanded height so the content currently
    // viewed remains at the exact same screen position.
    final oldOlder = oldWidget.uiState.isLoadingOlder;
    final newOlder = widget.uiState.isLoadingOlder;
    if (oldOlder && !newOlder) {
      _autoLoadDispatched = false;
      if (_anchorDistanceFromBottom != null) {
        final anchorDistance = _anchorDistanceFromBottom!;
        _anchorDistanceFromBottom = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_timelineScroll.hasClients) return;
          final position = _timelineScroll.position;
          if (!position.hasContentDimensions) return;
          final newMax = position.maxScrollExtent;
          final target = (newMax - anchorDistance).clamp(0.0, newMax);
          if ((target - position.pixels).abs() > 1.0) {
            _followDepth++;
            try {
              _timelineScroll.jumpTo(target);
            } finally {
              _followDepth--;
            }
          }
        });
      }
    }
  }

  /// Content-growth signal over the displayed flow: row count, the tail
  /// row's identity, the streaming text length, and the pending-steering
  /// tail (a steered word is flow content too).
  String? _followSignature() {
    final items = _timelineItems;
    final steering = _pendingSteering;
    if (items.isEmpty && steering.isEmpty) return null;
    final buffer = StringBuffer();
    if (items.isNotEmpty) {
      final last = items.last;
      final growth = last is TimelineMessage
          ? ':${last.value.text.length}:${last.value.reasoning?.length ?? 0}'
          : '';
      // Row identity deliberately ignores the tail's transient state, so the
      // follow signal names it here: a message that stops streaming and a call
      // that settles are still content changes worth following. The hook audit
      // is the one place the old key saw more than this: it also carried the
      // audit's `point`, which no settled `hook/result` ever rewrites, so no
      // reachable follow changed.
      final transient = switch (last) {
        TimelineMessage(:final value) => ':${value.streaming}',
        TimelineCommand(:final status) => ':$status',
        TimelineToolCall(:final status) => ':$status',
        TimelineWorkflowRun(:final status) => ':$status',
        _ => '',
      };
      buffer.write('${items.length}:${timelineKey(last)}$transient$growth');
    }
    if (steering.isNotEmpty) {
      buffer.write('|steered:${steering.length}:${steering.last.itemId}');
    }
    return buffer.toString();
  }

  /// The displayed tail is a user message (web `lastNode.kind === 'user'`).
  String? get _trailingUserKey {
    final steering = _pendingSteering;
    if (steering.isNotEmpty) return 'steering:${steering.last.itemId}';
    final items = _timelineItems;
    if (items.isEmpty) return null;
    final last = items.last;
    return last is TimelineMessage && last.value.role == MessageRole.user
        ? last.value.id
        : null;
  }

  /// Reader-input attribution: our own driven scrolls never re-evaluate
  /// pinning, so the follow glide cannot unpin itself mid-glide. A depth
  /// (not a bool) survives overlapping glides during fast streaming —
  /// each interrupted animation's cleanup leaves deeper ones armed.
  void _onTimelineScroll() {
    if (_followDepth > 0 || !_timelineScroll.hasClients) return;
    final position = _timelineScroll.position;
    if (!position.hasContentDimensions) return;
    _pinned = position.maxScrollExtent - position.pixels <= kFollowThreshold;
    _scheduleReadOffsetSave(position.pixels);
    _syncJumpToBottomButton();
    _checkAutoLoadOlder(position);
  }

  /// Automatically triggers background loading of earlier history when the
  /// reader scrolls near the top of the transcript.
  void _checkAutoLoadOlder(ScrollPosition position) {
    if (_needsInitialJump || !_restoreDecided || _followDepth > 0) return;
    final uiState = widget.uiState;
    if (!uiState.hasMoreOlder ||
        uiState.isLoadingOlder ||
        _autoLoadDispatched) {
      return;
    }
    if (position.maxScrollExtent <= 0) return;
    if (position.pixels <= kAutoLoadOlderThreshold) {
      _recordScrollAnchor();
      _autoLoadDispatched = true;
      widget.onAction(const LoadOlderHistoryAction());
    }
  }

  /// Captures the distance from the bottom before prepending items so the
  /// reading position can be seamlessly restored.
  void _recordScrollAnchor() {
    if (!_timelineScroll.hasClients) return;
    final position = _timelineScroll.position;
    if (!position.hasContentDimensions) return;
    _anchorDistanceFromBottom = position.maxScrollExtent - position.pixels;
  }

  /// The jump-to-bottom FAB is visible only when the reader is away from
  /// the bottom (beyond the follow threshold) of a scrollable timeline.
  /// Driven scrolls never re-evaluate this — the owning jump/follow paths
  /// pin first and the listener is depth-guarded, so they sync after the
  /// glide instead (the FAB must not hold stale visibility mid-glide).
  void _syncJumpToBottomButton() {
    var visible = false;
    if (_timelineScroll.hasClients) {
      final position = _timelineScroll.position;
      if (position.hasContentDimensions) {
        visible =
            position.maxScrollExtent > 0 &&
            position.maxScrollExtent - position.pixels > kFollowThreshold;
      }
    }
    if (visible == _showJumpToBottom) return;
    setState(() => _showJumpToBottom = visible);
  }

  /// One-click glide to the newest timeline content. The reader's own
  /// scroll listener is depth-guarded so the driven glide neither unpins
  /// nor records a mid-glide reading offset; the destination is pinned,
  /// which also folds the button away once the glide settles.
  Future<void> _jumpToBottom() async {
    if (!_timelineScroll.hasClients) return;
    final position = _timelineScroll.position;
    if (!position.hasContentDimensions) return;
    final target = position.maxScrollExtent;
    if (target <= 0) return;
    _followDepth++;
    _pinned = true;
    try {
      await _timelineScroll.animateTo(
        target,
        duration: DshMotion.durationMedium,
        curve: DshMotion.curveEnter,
      );
    } finally {
      if (mounted) {
        _followDepth--;
        _syncJumpToBottomButton();
      }
    }
  }

  /// Bind the selected session's persistence view, restore its collapsed
  /// outline turns, and arm the reading-position restore (the initial
  /// jump waits for that read; an actively running or streaming session
  /// lands at the bottom and follows instead).
  ///
  /// [landAtLatest] skips the reading-position read entirely, so the armed
  /// initial jump falls through to the tail: the notification entry asks
  /// for the newest content, and resuming a stale position there would
  /// hide exactly the message the notice was about.
  void _bindSession({bool landAtLatest = false}) {
    _needsInitialJump = true;
    _restoredOffset = null;
    _restoreDecided = true;
    final sessionId = widget.uiState.selectedSessionId;
    final sessionState = sessionId == null
        ? null
        : widget.localState?.forSession(sessionId);
    _sessionState = sessionState;
    if (sessionState == null) return;
    unawaited(
      widget.localState?.busyEnterBehavior().then((behavior) {
        if (!mounted) return;
        setState(() => _busyEnterSteer = behavior == kBusyEnterSteer);
      }),
    );
    if (landAtLatest) return;
    if (_sessionActivelyRunning()) return;
    _restoreDecided = false;
    unawaited(
      sessionState.readReadOffset().then(
        (offset) {
          if (!mounted) return;
          _restoredOffset = offset;
          _restoreDecided = true;
          // Content may already be laid out; the armed jump waits on us.
          if (_needsInitialJump) _scheduleFollow();
        },
        onError: (_) {
          if (!mounted) return;
          _restoreDecided = true;
          if (_needsInitialJump) _scheduleFollow();
        },
      ),
    );
  }

  /// Whether the selected session's turn is running or streaming: the
  /// reading-position restore is skipped so the view follows the tail.
  bool _sessionActivelyRunning() {
    final sessionId = widget.uiState.selectedSessionId;
    final session = widget.uiState.sessions
        .where((item) => item.id == sessionId)
        .firstOrNull;
    if (session?.running ?? false) return true;
    return widget.uiState.timeline.any(
      (item) => item is TimelineMessage && item.value.streaming,
    );
  }

  /// Reading positions persist debounced (the store debounces disk
  /// writes on its own); only reader-driven scrolls land here.
  void _scheduleReadOffsetSave(double offset) {
    if (_sessionState == null) return;
    _pendingReadOffset = offset;
    _readOffsetSave?.cancel();
    _readOffsetSave = Timer(const Duration(milliseconds: 500), () {
      _pendingReadOffset = null;
      unawaited(_sessionState?.writeReadOffset(offset));
    });
  }

  /// Write a still-pending reading position for the leaving session.
  void _flushReadOffset() {
    final offset = _pendingReadOffset;
    if (offset == null) return;
    _pendingReadOffset = null;
    unawaited(_sessionState?.writeReadOffset(offset));
  }

  /// Web ComposerSubmissionPolicy.resolve: queue outside a running turn;
  /// inside it the persisted busy-Enter preference decides (the send
  /// button is this client's only submit gesture, so the preference
  /// governs it there).
  PromptMode _promptModeFor(bool running) =>
      running && _busyEnterSteer ? PromptMode.steer : PromptMode.queue;

  void _scheduleFollow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_scrollToBottom());
    });
  }

  Future<void> _scrollToBottom() async {
    if (!_timelineScroll.hasClients) return;
    final position = _timelineScroll.position;
    if (!position.hasContentDimensions) return;
    var target = position.maxScrollExtent;
    // Nothing to reveal yet (empty timeline): the initial jump stays armed
    // so the first history frame still lands at the bottom without a long
    // smooth glide from the top.
    if (target <= 0) return;
    // The reading-position restore owns the initial jump until its read
    // settles; it re-schedules this follow once it has.
    if (!_restoreDecided) return;
    final jump = _needsInitialJump;
    _needsInitialJump = false;
    // A jump (session switch, first mount) pins without ceremony; growth
    // follows with a short ease so streaming glides instead of snapping.
    _followDepth++;
    try {
      if (jump) {
        final restored = _restoredOffset;
        if (restored != null) {
          // Reading restore: land at the saved position (clamped to the
          // laid-out extents) instead of the tail, and only follow from
          // there when the landing sits at the bottom anyway.
          final clamped = restored.clamp(0.0, target).toDouble();
          _pinned = target - clamped <= kFollowThreshold;
          _timelineScroll.jumpTo(clamped);
          return;
        }
        _pinned = true;
        _timelineScroll.jumpTo(target);
        return;
      }
      // Driven follows re-pin (the scroll listener skips driven scrolls).
      _pinned = true;
      // The lazy list's extent estimate moves as tail items materialize
      // under the glide; re-issue while still short of (or past) the
      // settled bottom (bounded so a pathological estimator cannot loop
      // forever).
      for (var attempt = 0; attempt < 3; attempt++) {
        if (!_timelineScroll.hasClients) return;
        final live = _timelineScroll.position;
        if (!live.hasContentDimensions) return;
        target = live.maxScrollExtent;
        if ((target - live.pixels).abs() <= kFollowThreshold) return;
        await _timelineScroll.animateTo(
          target,
          duration: _followDuration(live.pixels, target),
          curve: DshMotion.curveEnter,
        );
      }
    } finally {
      _followDepth--;
      // Driven glides land at (or restore to) a settled position; fold or
      // raise the jump button to match it.
      if (mounted) _syncJumpToBottomButton();
    }
  }

  /// Distance-scaled glide: fast enough to keep up with streaming frames,
  /// short enough that each frame's re-issue never lags the tail.
  Duration _followDuration(double from, double to) {
    final distance = (to - from).abs();
    final ms = (60 + distance * 0.25).clamp(90.0, 220.0);
    return Duration(milliseconds: ms.round());
  }

  /// First unanswered approval; it takes over the composer seat.
  TimelineApprovalRequest? get _pendingApproval {
    for (final item in widget.uiState.timeline) {
      if (item is TimelineApprovalRequest) return item;
    }
    return null;
  }

  /// First unanswered question / plan review request; it takes over the composer seat.
  TimelineQuestionRequest? get _pendingQuestion {
    for (final item in widget.uiState.timeline) {
      if (item is TimelineQuestionRequest) return item;
    }
    return null;
  }

  /// First timed question whose foreground wait already ended. The waterfall
  /// cannot settle it any more, so it takes the composer seat and its answer
  /// rides `userQuestions/answer` (controller routing).
  PendingUserQuestion? get _continuedQuestion {
    for (final row in widget.uiState.pendingUserQuestions) {
      if (row.state == UserQuestionState.continued &&
          row.questions.isNotEmpty) {
        return row;
      }
    }
    return null;
  }

  /// First pending dynamic-Cordis activation that actually needs a decision;
  /// it takes over the composer seat like an approval.
  ///
  /// A request with `requiresApproval: false` is not a pending decision:
  /// the host already started its own half and only needs a browser page to
  /// attach the Client half, which this client cannot do. Showing a Reject
  /// there would invite the reader to cancel a run nobody asked them about
  /// and would not release any blocked tool call, so those requests never
  /// mount a card. `/export`-style special cases do not apply — the host
  /// either forwarded a request or it did not.
  CordisRunRequest? get _pendingCordisRequest {
    for (final request in widget.uiState.cordisRunRequests) {
      if (request.requiresApproval) return request;
    }
    return null;
  }

  /// Whether an interactive decision (plan review, question, approval, or a
  /// plugin activation) is pending and taking over the composer seat.
  bool get _hasPendingDecision =>
      _pendingQuestion != null ||
      _pendingApproval != null ||
      _pendingCordisRequest != null;

  /// Extract the command from the tool call paired with the pending approval.
  String? _commandForApproval(TimelineApprovalRequest approval) {
    final callId = approval.callId;
    if (callId == null) return null;
    for (final item in widget.uiState.timeline) {
      if (item is TimelineToolCall && item.id == callId) {
        return commandOf(item);
      }
    }
    return null;
  }

  /// Whether the transient inbox holds queued rows — the dock's subject.
  /// Steering rows render at the transcript tail and context rows wait
  /// invisible for their durable injection form, so neither mounts the
  /// dock (web QueueDock.tsx:33 filters the same placement).
  bool get _hasQueuedRows {
    for (final queue in widget.uiState.timeline.whereType<TimelineQueue>()) {
      if (queue.items.any((item) => item.placement == QueuePlacement.queued)) {
        return true;
      }
    }
    return false;
  }

  /// Timeline without the queue rows (queued ones ride the composer dock,
  /// steering ones the transcript tail below) and the interactive requests
  /// (approval / question / plan-review) that took over the composer seat.
  List<TimelineItem> get _timelineItems => widget.uiState.timeline
      .where(
        (item) =>
            item is! TimelineQueue &&
            item is! TimelineJobs &&
            item != _pendingApproval &&
            item != _pendingQuestion,
      )
      .toList();

  /// Transient steering rows of the queue snapshot, rendered at the
  /// conversation tail — the port of the web ChatView's pending-steering
  /// bubbles (`ChatView.tsx:454-460`; `api/events.ts:81-82`: "queued items
  /// render in QueueDock, while pending steering renders at the
  /// conversation tail"). A steered word has no durable event until the
  /// running turn claims it; the tail is the only place it can show. Rows
  /// whose claim already landed as a durable user message of the same id
  /// drop out, so one utterance never renders twice across the transient
  /// and durable frames. Context placements stay invisible while
  /// transient, exactly as on the web: their durable form is the
  /// injection row.
  List<SessionQueueItem> get _pendingSteering {
    final steering = <SessionQueueItem>[];
    for (final queue in widget.uiState.timeline.whereType<TimelineQueue>()) {
      for (final item in queue.items) {
        if (item.placement == QueuePlacement.steering) steering.add(item);
      }
    }
    if (steering.isEmpty) return const <SessionQueueItem>[];
    final durableIds = <String>{
      for (final item in widget.uiState.timeline)
        if (item is TimelineMessage && item.value.role == MessageRole.user)
          item.value.id,
    };
    final seen = <String>{};
    return [
      for (final item in steering)
        if (!durableIds.contains(item.itemId) && seen.add(item.itemId)) item,
    ];
  }

  /// Preset staged for the next session (web seat's stage); spent by the
  /// workspace pick that creates the session.
  String? _stagedPreset;

  /// A hero-seat pick: a selected blank session switches its own preset
  /// through the host verb; anything else stages the choice for the
  /// session a later workspace pick creates.
  void _pickPreset(SessionSummary? session, String presetId) {
    final sessionId = widget.uiState.selectedSessionId;
    if (session != null && session.blank && sessionId != null) {
      widget.onAction(
        SelectAgentPreset(sessionId: sessionId, agentPreset: presetId),
      );
      return;
    }
    setState(() => _stagedPreset = presetId);
  }

  /// The one turn-level activity line, riding the timeline tail while the
  /// session's turn runs: `session.running` is the host's word, a
  /// streaming message the local echo before the host confirms. It yields
  /// to the louder tail signals — the streaming caret once assistant text
  /// flows — and to the approval seat, where the wait belongs to the user,
  /// not the agent.
  bool _turnStatusVisible(ChatUiState uiState) {
    final sessionId = uiState.selectedSessionId;
    final session = uiState.sessions
        .where((item) => item.id == sessionId)
        .firstOrNull;
    final busy =
        uiState.isSending ||
        (session?.running ?? false) ||
        uiState.timeline.any(
          (item) => item is TimelineMessage && item.value.streaming,
        );
    if (!busy || _hasPendingDecision) return false;
    return !uiState.timeline.any(
      (item) =>
          item is TimelineMessage &&
          item.value.streaming &&
          item.value.role == MessageRole.assistant &&
          item.value.text.isNotEmpty,
    );
  }

  /// The failed-action strip: localized copy, the controller's existing
  /// retry action, and a dismiss that clears the message.
  ///
  /// [dismissible] is false for a failure the app does not own — the
  /// Agent-level error the host reported is cleared by the session accepting
  /// a new prompt, so offering a close button would hide a fact that is
  /// still true on the host.
  Widget _errorBanner(
    ChatErrorCopy copy, {
    VoidCallback? onRetry,
    bool dismissible = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ErrorBanner(
        message: copy.message,
        detail: copy.detail,
        onRetry: onRetry,
        onDismiss: dismissible
            ? () => widget.onAction(const DismissError())
            : null,
      ),
    );
  }

  /// Opens the file-preview sheet for a tool row's path. The sheet reads
  /// through the repository seam and handles loading, failure, binary, and
  /// truncation itself; the panel only resolves the session the row belongs
  /// to.
  void _openFilePreview(String path, {EditDiffModel? diff}) {
    final sessionId = widget.uiState.selectedSessionId;
    if (sessionId == null) return;
    unawaited(
      showFilePreviewSheet(
        context,
        sessionId: sessionId,
        path: path,
        readFile: widget.readWorkspaceFile,
        readFileBytes: widget.readWorkspaceFileBytes,
        initialDiff: diff,
      ),
    );
  }

  /// Whether the window carries any conversation at all: the durable
  /// transcript, with the live mirrors the host republishes for every
  /// followed session counted only for what they actually show. Both land
  /// unconditionally (`job/list` yields one whole-set `rows` frame on open,
  /// an empty roster included), so a session nothing has happened in still
  /// carries a non-empty window; "nothing here yet" is *this* predicate, not
  /// [ChatUiState.timeline]. The roster is pure chrome; the queue snapshot
  /// is chrome only while it holds no row, since a queued or steered message
  /// is the reader's own words and renders on this surface (the composer
  /// dock or the transcript tail). Reading the raw list would leave a blank
  /// session's hero (fish headline, workspace and preset seats) hidden behind
  /// two seats the reader cannot see — the state a session reached through
  /// the sidebar's long-press create lands in, because its window is already
  /// warm from an earlier follow.
  static bool _hasConversationContent(ChatUiState uiState) =>
      uiState.timeline.any(
        (item) => switch (item) {
          TimelineJobs() => false,
          TimelineQueue(:final items) => items.isNotEmpty,
          _ => true,
        },
      );

  Widget _timelineBody(ChatUiState uiState, SessionSummary? session) {
    if (!_hasConversationContent(uiState)) {
      if (uiState.isTimelineLoading) {
        // First load of the selected conversation: never read the wait as
        // an empty session. A centered loader mirrors the subagent pane.
        return const Center(child: CircularProgressIndicator());
      }
      return EmptyHero(
        workspaces: uiState.workspaces,
        currentWorkspaceLabel: _workspaceLabel(session?.cwd),
        onPickWorkspace: (workspaceId) {
          // The staged preset rides the creation; the stage is spent
          // on first use (web seat semantics), so the next new
          // session opens on the default again.
          final preset = _stagedPreset;
          widget.onAction(
            CreateSessionInWorkspace(workspaceId, agentPreset: preset),
          );
          if (preset != null) {
            setState(() => _stagedPreset = null);
          }
        },
        presetRoster: uiState.agentPresets,
        currentPresetId: stagedPresetId(
          roster: uiState.agentPresets,
          staged: _stagedPreset,
          selectedSession: session,
        ),
        onPickPreset: (presetId) => _pickPreset(session, presetId),
      );
    }
    final items = _timelineItems;
    // The transcript view decides whether a completed Turn folds; the route
    // passes the Host's mode down as this policy, so nothing below reads the
    // settings surface itself.
    final groupedItems = foldTurnProcesses(
      foldTimelineActivities(items),
      foldCompletedTurns: widget.presentation.foldCompletedTurns,
    );
    final steering = _pendingSteering;
    // The produced-files row closes a finished turn. The newest turn only
    // counts as finished once the session stops running, so its row appears
    // at the turn's end rather than under a reply the model may still extend.
    final bool sessionBusy =
        uiState.isSending ||
        (session?.running ?? false) ||
        uiState.timeline.any(
          (item) => item is TimelineMessage && item.value.streaming,
        );
    final turnFilesByMessage = turnFilesByClosingMessage(
      items,
      latestTurnClosed: !sessionBusy,
    );
    final turnEndSeqByMessageId = turnEndSeqByMessage(items);
    // The status line rides the tail of the transcript: with nothing
    // visible to be a tail after (a queue-only window), it renders nothing
    // — the queue dock and the composer seat already carry the run.
    final showTurnStatus = _turnStatusVisible(uiState) && items.isNotEmpty;
    final showOlder = uiState.hasMoreOlder || uiState.isLoadingOlder;
    // The status line names the open Turn's clock; a Turn boundary outside the
    // loaded window leaves the start unknown and the label clockless.
    final runningTurnStart = groupedItems
        .whereType<TurnProcessSection>()
        .where((section) => !section.facts.closed)
        .lastOrNull
        ?.facts
        .startedAtEpochMs;
    // The web's tail order: flow rows, the turn-status line, then the
    // pending steering bubbles (ChatView.tsx:446-460). Steering rides both
    // render modes the same way.
    final rows = <Object>[
      if (showOlder) _olderHistorySlot,
      ...groupedItems,
      if (showTurnStatus) _turnStatusSlot,
      ...steering,
    ];
    // A transcript on a tablet would otherwise run the full pane width and
    // hand the reader 200-character lines: the reading column is capped and
    // centred, so a wide surface gains margins instead of longer paragraphs.
    // The cap binds only above it, which is why a phone is untouched.
    // One transcript row, shared by the list and by a Turn's process
    // disclosure, which renders the rows it owns through the same path a
    // top-level row takes.
    Widget buildRow(Object row) {
      final Key key = transcriptRowKey(row);
      if (identical(row, _olderHistorySlot)) {
        return OlderHistoryRow(
          key: key,
          isLoading: uiState.isLoadingOlder,
          onLoadOlder: () {
            _recordScrollAnchor();
            _autoLoadDispatched = true;
            widget.onAction(const LoadOlderHistoryAction());
          },
        );
      }
      if (row is TurnProcessSection) {
        return TurnProcessRow(
          key: key,
          section: row,
          buildRow: buildRow,
          gapAfter: chatFlowGapAfter,
          expansion: _sessionState,
        );
      }
      if (row is TimelineActivityGroup) {
        return ActivityGroupRow(
          key: key,
          group: row,
          onAction: widget.onAction,
          loadAttachment: widget.loadAttachment,
          sessionId: uiState.selectedSessionId,
          onPreviewFile: _openFilePreview,
          expansion: _sessionState,
          onOpenChild: _openWorkflowMember,
        );
      }
      if (row is TimelineItem) {
        return TimelineRow(
          key: key,
          item: row,
          onAction: widget.onAction,
          loadAttachment: widget.loadAttachment,
          sessionId: uiState.selectedSessionId,
          backendId: widget.backendId,
          onPreviewFile: _openFilePreview,
          expansion: _sessionState,
          onOpenChild: _openWorkflowMember,
          producedPaths: row is TimelineMessage
              ? turnFilesByMessage[row.value.id]?.produced
              : null,
          presentedFiles: row is TimelineMessage
              ? turnFilesByMessage[row.value.id]?.presented
              : null,
          forkAtSeq: row is TimelineMessage
              ? turnEndSeqByMessageId[row.value.id]
              : null,
        );
      }
      if (row is SessionQueueItem) {
        return PendingSteeringRow(
          key: ValueKey('steering:${row.itemId}'),
          text: row.text,
        );
      }
      if (identical(row, _turnStatusSlot)) {
        return RunningStatusRow(
          key: key,
          startedAtEpochMs: runningTurnStart,
          showDivider: _carriesOutput(groupedItems.lastOrNull),
        );
      }
      // The fold produces sections and items only; the tail sentinel above is
      // the one synthetic row this builder is handed.
      return const SizedBox.shrink();
    }

    // The list matches its children by row identity, not by index: a history
    // page prepended above, or any row inserted anywhere, moves the rows below
    // it without recycling their elements — so each keeps the fold, the clock
    // and the scroll it holds.
    final Map<Key, int> rowIndexByKey = indexRowsByKey(rows);

    final Widget transcript = ListView.separated(
      controller: _timelineScroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: rows.length,
      findItemIndexCallback: (Key key) => rowIndexByKey[key],
      separatorBuilder: (_, index) => SizedBox(
        height: chatFlowGapAfter(
          rows[index],
          index + 1 < rows.length ? rows[index + 1] : null,
        ),
      ),
      itemBuilder: (context, index) => buildRow(rows[index]),
    );

    // The end fades follow the scroll position itself. The controller is the
    // animation, so only the mask rebuilds as the reader moves: the list keeps
    // its element — and the reader's offset — while the ramp tracks the edges.
    // The mask stays in the tree even with both edges opaque, because removing
    // it would change the list's position in the tree and rebuild the scroller.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kReadingMeasure),
        child: AnimatedBuilder(
          animation: _timelineScroll,
          builder: (BuildContext context, Widget? child) {
            final ScrollPosition? position = _timelineScroll.hasClients
                ? _timelineScroll.position
                : null;
            return _edgeFade(
              child!,
              fadeTop:
                  position != null &&
                  position.hasContentDimensions &&
                  position.pixels > 0,
              fadeBottom:
                  position != null &&
                  position.hasContentDimensions &&
                  position.pixels < position.maxScrollExtent,
            );
          },
          child: transcript,
        ),
      ),
    );
  }

  /// The transcript's end fade: a [kEdgeFade] ramp on an edge that still has
  /// content behind it — the reference's `fadeTop`/`fadeBottom`
  /// (`ChatGroupSeat.module.css:102-110`). An edge with nothing behind it stays
  /// opaque, so the ramp exists only where the content can still move. Under
  /// `dstIn` only the shader's alpha reads through, so the opaque end is the
  /// surface role: the mask carries no palette value of its own.
  Widget _edgeFade(
    Widget child, {
    required bool fadeTop,
    required bool fadeBottom,
  }) {
    final surface = Theme.of(context).colorScheme.surface;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (Rect rect) {
        final double ramp = (kEdgeFade / rect.height).clamp(0.0, 0.5);
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            surface.withValues(alpha: fadeTop ? 0 : 1),
            surface.withValues(alpha: 1),
            surface.withValues(alpha: 1),
            surface.withValues(alpha: fadeBottom ? 0 : 1),
          ],
          stops: <double>[0, ramp, 1 - ramp, 1],
        ).createShader(rect);
      },
      child: child,
    );
  }

  /// Whether the row above the running status carries output, so the status
  /// line draws its hairline: the reference shows it unless the previous
  /// visible row is the reader's own message, a steering bubble, or the Turn
  /// trigger (`ChatView.module.css` `.runningDivider`).
  static bool _carriesOutput(Object? row) => switch (row) {
    null => false,
    TimelineMessage(:final value) => value.role != MessageRole.user,
    TimelineTurnBoundary() => false,
    SessionQueueItem() => false,
    _ => true,
  };

  /// The jump-to-bottom affordance: a native Material small FAB in the
  /// neutral selector fill (the composer's idle circle convention), so it
  /// never competes with the brand-filled send/stop seat. heroTag is off
  /// so sibling FABs cannot fight over the shared hero on route changes.
  Widget _jumpToBottomFab() {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: AppLocalizations.of(context)!.jumpToBottomTooltip,
      child: _tactileFab(
        context,
        enabled: true,
        DecoratedBox(
          // The reference's to-bottom pill (`ChatView.module.css` `.toBottom`,
          // :252-268): the panel tier with its ring rebound to `border-l3`
          // (:260), on the floating-button fill in `label-primary` (:262-263).
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: DshElevation.panel(scheme, stroke: scheme.borderL3),
          ),
          child: FloatingActionButton.small(
            heroTag: null,
            shape: const CircleBorder(),
            backgroundColor: scheme.buttonFloatingFill,
            foregroundColor: scheme.labelPrimary,
            // The pin's lift is the DecoratedBox ring above; Material's own
            // shadow would stack a second, heavier one under it.
            elevation: 0,
            highlightElevation: 0,
            hoverElevation: 0,
            focusElevation: 0,
            disabledElevation: 0,
            splashColor: Colors.transparent,
            enableFeedback: false,
            onPressed: _jumpToBottom,
            child: const Icon(Icons.arrow_downward, size: 22),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final uiState = widget.uiState;
    final selectedSessionId = uiState.selectedSessionId;
    final selectedSession = uiState.sessions
        .where((session) => session.id == selectedSessionId)
        .firstOrNull;
    final isSessionRunning = selectedSession?.running ?? false;

    // DockAnchor publishes the keyed dock (below) to every sheet opener
    // in the panel — model seat, permission seat, preset seat, the ➕
    // roster, the workspace picker: the sheets float above the dock's
    // top edge instead of hugging the screen bottom (see showMenuSheet).
    // How tall the dock may grow, measured against this panel rather than the
    // screen: the app bar, the root navigation bar and the system insets are
    // already outside these constraints, and anything that grew past them
    // would sit under the tab bar where no tap lands. A panel shorter than the
    // floor keeps the floor out of the way — the dock may never exceed the
    // panel it lives in.
    double dockBudget(double panelHeight) {
      final budget =
          (panelHeight *
                  (_hasPendingDecision ? _dockDecisionShare : _dockBudgetShare))
              .clamp(_dockMinHeight, _dockMaxHeight);
      return budget < panelHeight ? budget : panelHeight;
    }

    return DockAnchor(
      dockKey: _dockKey,
      child: Padding(
        // No inset at the top: the transcript runs to the bar and slides
        // under it. A gap there is a blank strip that also clips the first
        // row mid-line, which reads as a rendering fault.
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        // The panel's own height is the only honest budget for the dock: the
        // screen also carries the app bar, the root navigation bar and the
        // system insets, none of which the dock may grow over.
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              if (uiState.errorMessage case final error?)
                _errorBanner(
                  describeChatError(l10n, error),
                  onRetry: () => widget.onAction(const RetrySessions()),
                )
              else if (uiState.cordisAnswerFailed)
                _errorBanner((message: l10n.cordisAnswerFailed, detail: null))
              else if (uiState.commandFailed)
                _errorBanner((message: l10n.commandFailed, detail: null))
              else if (selectedSession?.agentError case final agentError?)
                // The host reported a failure with no turn position: no
                // timeline item carries it, so this strip is the only place the
                // session can say why it stopped. Not dismissible — the next
                // prompt clears it (web `ClientSession.prompt`).
                _errorBanner((
                  message: l10n.sessionAgentFailed,
                  detail: agentError,
                ), dismissible: false),
              for (final rejection in uiState.imageRejections)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    switch (rejection) {
                      UnsupportedImageType(:final name, :final mediaType) =>
                        l10n.imageRejectionUnsupported(
                          name ?? l10n.attachmentName,
                          mediaType,
                        ),
                      ImageTooLarge(:final name, :final maxBytes) =>
                        l10n.imageRejectionTooLarge(
                          name ?? l10n.attachmentName,
                          maxBytes,
                        ),
                      NoImageRoom(:final room) => l10n.imageRejectionNoRoom(
                        room,
                      ),
                    },
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () {
                          final primaryFocus =
                              FocusManager.instance.primaryFocus;
                          if (primaryFocus != null && primaryFocus.hasFocus) {
                            primaryFocus.unfocus();
                          }
                        },
                        child: _timelineBody(uiState, selectedSession),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: AnimatedSwitcher(
                        duration: DshMotion.durationShort,
                        switchInCurve: DshMotion.curveEnter,
                        switchOutCurve: DshMotion.curveExit,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: animation,
                            child: child,
                          ),
                        ),
                        child: _showJumpToBottom
                            ? _jumpToBottomFab()
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
              // The session's counters are the transcript's footer, not dock
              // chrome: they caption the conversation above the input surface
              // rather than wedge between two of its strips.
              if (!_hasPendingDecision) StatsLine(stats: uiState.sessionStats),
              // Web input-dock order 0: the plan strip before the goal and
              // queue entries. While a decision (plan review, question, approval)
              // is pending, the decision panel takes the composer seat, so the
              // todo/goal chrome stands down — the decision moment keeps the
              // transcript room instead of stacking chrome above it. Every strip
              // shares one raised surface; the parts divide with hairlines, never
              // with borders of their own.
              _InputDock(
                key: _dockKey,
                maxHeight: dockBudget(constraints.maxHeight),
                children: [
                  if (!_hasPendingDecision) ...[
                    TodoPanel(todos: uiState.todos ?? const <TodoItem>[]),
                    GoalBarStrip(goal: uiState.goal, onAction: widget.onAction),
                    // The session's durable reminders: nothing else on this
                    // surface shows them (the pinned deployment composes no
                    // `schedule` projection), and the dock is where the rest
                    // of the session's standing state already lives. Nothing to
                    // show leaves no strip at all: an unreported or empty set
                    // would spend a row of every session's dock on a fact the
                    // reader cannot act on.
                    if (selectedSessionId != null &&
                        (uiState.schedules?.isNotEmpty ?? false))
                      ScheduleReminderStrip(reminders: uiState.schedules),
                  ],
                  // The queue dock is a display strip, not a filled seat:
                  // it rides alongside the approval card the way web's
                  // `conversation.input.dock` slot does (QueueDock is
                  // registered per-session and stays mounted while an
                  // approval panel owns the composer). An approval must
                  // never hide the queued rows the reader is waiting to
                  // send after the decision.
                  if (_hasQueuedRows)
                    QueueDock(
                      items: [
                        for (final dock
                            in uiState.timeline.whereType<TimelineQueue>())
                          ...dock.items,
                      ],
                      running: isSessionRunning,
                      onAction: widget.onAction,
                    ),
                  if (_pendingQuestion case final question?)
                    QuestionRow(
                      key: ValueKey('question-takeover:${question.requestId}'),
                      request: question,
                      onAction: widget.onAction,
                    )
                  else if (_pendingApproval case final approval?)
                    ApprovalRow(
                      request: approval,
                      command: _commandForApproval(approval),
                      onAction: widget.onAction,
                    )
                  else if (_pendingCordisRequest case final cordis?)
                    CordisRequestPanel(
                      key: ValueKey('cordis-takeover:${cordis.requestId}'),
                      request: cordis,
                      onAction: widget.onAction,
                    )
                  else if (_continuedQuestion case final continued?)
                    QuestionRow(
                      key: ValueKey('continued-question:${continued.callId}'),
                      request: TimelineQuestionRequest(
                        requestId: continued.callId,
                        questions: continued.questions,
                      ),
                      onAction: widget.onAction,
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: ComposerBar(
                            onStop: selectedSessionId == null
                                ? null
                                : () =>
                                      widget.onAction(const CancelTurnAction()),
                            enabled:
                                selectedSessionId != null && !uiState.isSending,
                            isSending: uiState.isSending,
                            running: isSessionRunning,
                            plan: uiState.plan,
                            models: widget.models,
                            onSelectModel: widget.onSelectModel,
                            onRefreshModels: widget.onRefreshModels,
                            modelPrefs: uiState.modelPrefs,
                            pendingImages: uiState.pendingImages,
                            imageLimits: uiState.imageLimits,
                            pendingFiles: uiState.pendingFiles,
                            skills: uiState.skills,
                            commands: uiState.commands,
                            fileReferences: uiState.fileReferences,
                            contextPressure: uiState.contextPressure,
                            contextBreakdown: uiState.contextBreakdown,
                            onAction: widget.onAction,
                            sessionId: selectedSessionId,
                            sessionState: _sessionState,
                            permissions: uiState.permissions,
                            sandboxMode: uiState.sandboxMode,
                            loadPermissionCatalog: widget.loadPermissionCatalog,
                            // Web ComposerSubmissionPolicy: queue outside a
                            // running turn; inside it the persisted busy-Enter
                            // preference decides (the send button is the only
                            // submit gesture on a soft keyboard). The future
                            // resolves with the host's acceptance: the
                            // composer clears its draft only then.
                            onSend: (text) {
                              final settled = Completer<bool>();
                              widget.onAction(
                                SendPrompt(
                                  text,
                                  mode: _promptModeFor(isSessionRunning),
                                  onSettled: (accepted) {
                                    if (!settled.isCompleted) {
                                      settled.complete(accepted);
                                    }
                                  },
                                ),
                              );
                              return settled.future;
                            },
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The input dock: one raised surface carrying every strip that sits
/// between the transcript and the thumb — plan, goal, queue, composer.
/// Each strip used to draw its own border and radius, which stacked three
/// nested boxes at the screen's busiest edge; the surface belongs to the
/// dock, and the strips divide with hairlines.
///
/// [maxHeight] is the panel's budget for the dock (see [_dockBudgetShare]).
/// It bounds the dock so its content can never grow past the panel's own
/// bottom edge, where the root navigation bar sits and nothing below can be
/// tapped; content taller than the budget scrolls inside the dock instead.
/// A decision card reads the same budget from [DockBudget] and sizes its
/// scrollable body against it, so its own action row lands at the dock's
/// bottom edge rather than below it. A bare pump without a budget keeps the
/// dock's historical min-size shape.
class _InputDock extends StatelessWidget {
  const _InputDock({required this.children, this.maxHeight, super.key});

  final List<Widget> children;

  /// The height the dock may occupy, or null when no sized panel encloses
  /// it (a widget test pumping the dock's host directly).
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final budget = maxHeight;
    final content = Column(mainAxisSize: MainAxisSize.min, children: children);
    final Widget body = budget == null
        ? content
        : ConstrainedBox(
            constraints: BoxConstraints(maxHeight: budget),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: content,
            ),
          );
    // The reference's input card (`InputBar.module.css` `.card`, :46-63): the
    // input surface on the panel radius, its edge drawn as the elevation
    // hairline rebound to `border-l2` (:55-57), under the soft tier (:63).
    // There is no Material border and no M3 shadow: the pin's soft tier is a
    // half-pixel ring plus two very light layers, which is why this surface
    // used to read heavier than the reference's.
    final Widget dock = Container(
      decoration: BoxDecoration(
        color: scheme.inputSurface,
        borderRadius: BorderRadius.circular(kRadiusPanel),
        boxShadow: DshElevation.soft(scheme, stroke: scheme.borderL2),
      ),
      clipBehavior: Clip.antiAlias,
      child: body,
    );
    if (budget == null) return dock;
    return DockBudget(maxHeight: budget, child: dock);
  }
}

/// Plan-mode status chip — port of the web `PlanModeControl` (figma
/// warn-state pill). Renders only while the effective target is plan mode
/// (`pending ? !active : active` — the folded host value, not client
/// optimism) and exits by executing `/plan off`. Entering plan mode is done
/// by typing `/plan` in the composer, never by this chip.
class PlanChip extends StatefulWidget {
  const PlanChip({
    required this.plan,
    required this.onExit,
    super.key,
    this.locked = false,
  });

  final PlanState? plan;
  final VoidCallback onExit;
  final bool locked;

  @override
  State<PlanChip> createState() => _PlanChipState();
}

class _PlanChipState extends State<PlanChip> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    // Undefined (null: no frame yet) and off both render nothing.
    if (plan == null) return const SizedBox.shrink();
    final target = plan.pending ? !plan.active : plan.active;
    if (!target) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    // Web .chip:hover — the label deepens toward warn-primary.
    final label = _hovering ? scheme.error : scheme.onErrorContainer;
    return MouseRegion(
      cursor: widget.locked
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Opacity(
        // Web .chip:disabled — the locked seat dims instead of vanishing.
        opacity: widget.locked ? 0.6 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(kShapePill),
            onTap: widget.locked ? null : widget.onExit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(kShapePill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DefaultTextStyle(
                    style: Theme.of(context).textTheme.labelMedium!.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 20 / 13,
                      color: label,
                    ),
                    child: const Text(
                      // Design literal, not copy: the chip wordmark stays
                      // 'Plan' in every locale.
                      'Plan',
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.close, size: 12, color: label),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mobile-first history indicator at the head of the transcript:
/// - When loading: clean centered CircularProgressIndicator with localized copy
/// - When idle (e.g. at the head): unobtrusive TextButton allowing manual trigger
class OlderHistoryRow extends StatelessWidget {
  const OlderHistoryRow({
    required this.isLoading,
    required this.onLoadOlder,
    super.key,
  });

  final bool isLoading;
  final VoidCallback onLoadOlder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        child: isLoading
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l10n.chatLoadingOlder,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              )
            : TextButton.icon(
                key: const ValueKey('chat-load-older-button'),
                onPressed: onLoadOlder,
                icon: Icon(
                  Icons.history_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                label: Text(
                  l10n.chatLoadOlder,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
      ),
    );
  }
}

class TimelineRow extends StatelessWidget {
  const TimelineRow({
    required this.item,
    required this.onAction,
    required this.loadAttachment,
    super.key,
    this.sessionId,
    this.backendId,
    this.onPreviewFile,
    this.expansion,
    this.producedPaths,
    this.presentedFiles,
    this.forkAtSeq,
    this.onOpenChild,
  });

  final TimelineItem item;
  final void Function(ChatAction) onAction;
  final AttachmentLoader loadAttachment;

  /// Session a tool row's durable result images are read against.
  final String? sessionId;

  /// The backend presenting this transcript; null (a bare pump, or a
  /// read-only child record) leaves the reply footer without its feedback
  /// pair, which can only address a live backend.
  final String? backendId;

  /// File-preview action for a tool row's generated/edited path.
  final void Function(String path, {EditDiffModel? diff})? onPreviewFile;

  /// Tool-row expansion persistence of the selected session; null keeps
  /// expansion in memory only.
  final ToolExpansionPersistence? expansion;

  /// Paths this turn's successful mutations produced; non-null only on the
  /// turn's closing assistant message.
  final List<String>? producedPaths;

  /// Files this turn's successful `present` calls declared; non-null only on
  /// the turn's closing assistant message, and empty when the turn declared
  /// none.
  final List<PresentedFile>? presentedFiles;

  /// This row's message's completed-turn anchor for `session/fork`; null when
  /// the message's turn has not closed, which hides the fork seat rather than
  /// asking the host to cut a partial turn.
  final int? forkAtSeq;

  /// Jump target for a workflow member's child session; null renders the
  /// card read-only (a nested child record has no further navigation seat).
  final WorkflowMemberOpener? onOpenChild;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return switch (item) {
      TimelineMessage(
        :final value,
        :final steering,
        :final stepStartedAtEpochMs,
        :final stepEndedAtEpochMs,
      ) =>
        MessageRow(
          message: value,
          steering: steering,
          stepStartedAtEpochMs: stepStartedAtEpochMs,
          stepEndedAtEpochMs: stepEndedAtEpochMs,
          loadAttachment: loadAttachment,
          backendId: backendId,
          // `session/fork`'s `atSeq` is an exact inclusive event seq, so the
          // seat cuts the completed turn the message sits in.
          onFork: forkAtSeq == null
              ? null
              : () => onAction(ForkSession(value.sessionId, atSeq: forkAtSeq)),
          usage: (item as TimelineMessage).usage,
          firstTokenAtEpochMs: (item as TimelineMessage).firstTokenAtEpochMs,
          producedPaths: producedPaths,
          presentedFiles: presentedFiles,
          onPreviewFile: onPreviewFile == null
              ? null
              : (path) => onPreviewFile!(path),
        ),
      TimelineTurnBoundary(:final turn) => TurnBoundaryRow(turn: turn),
      TimelineCompaction() => CompactionRow(
        compaction: item as TimelineCompaction,
      ),
      TimelineCommand() => CommandRow(command: item as TimelineCommand),
      TimelineContextInjection() => ContextInjectionRow(
        injection: item as TimelineContextInjection,
      ),
      TimelineToolCall() => ToolCallRow(
        call: item as TimelineToolCall,
        sessionId: sessionId,
        loadAttachment: loadAttachment,
        onPreviewFile: onPreviewFile,
        expansion: expansion,
      ),
      TimelineApprovalRequest() => const SizedBox.shrink(),
      TimelineQuestionRequest() => const SizedBox.shrink(),
      TimelineQueue() => const SizedBox.shrink(),
      TimelineJobs() => const SizedBox.shrink(),
      // Hook audits and workflow runs are decoded durable facts with their
      // own transcript rows. A hook deny sits at its log position so the
      // refusal reads next to the tool row it explains; a workflow run is
      // its own collapsible card.
      TimelineHookAudit(:final audit) => HookAuditRow(audit: audit),
      final TimelineWorkflowRun run => WorkflowRunRow(
        run: run,
        onOpenChild: onOpenChild,
      ),
      TimelineError(:final message, :final code) => SizedBox(
        width: double.infinity,
        child: Text(switch (code) {
          'error' => l10n.turnFailed(
            message.isEmpty ? l10n.unknownModelFailure : message,
          ),
          'aborted' => l10n.turnStopped,
          'interrupted' => l10n.turnInterrupted,
          'blocked' => l10n.turnBlocked,
          'max-tokens' => l10n.turnMaxTokens,
          _ => message,
        }, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ),
    };
  }
}

/// The owning step's measured range, under the answer it produced:
/// `step/end − step/start` ([TimelineMessage.stepEndedAtEpochMs] /
/// [TimelineMessage.stepStartedAtEpochMs]), the reference's `stepEnd`
/// (`client/ui-trajectory/src/client/trajectory-assistant-definition.ts:247`).
/// The turn control still names the turn's total (`Completed in …`); this
/// names one step inside it, in the same unit vocabulary, floored at one
/// second the way the turn's own clock is.
class _StepDuration extends StatelessWidget {
  const _StepDuration({
    required this.startedAtEpochMs,
    required this.endedAtEpochMs,
  });

  final int startedAtEpochMs;
  final int endedAtEpochMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final int elapsed = endedAtEpochMs - startedAtEpochMs;
    final String text = runDurationParts(
      elapsed < 1000 ? 1000 : elapsed,
      AppLocalizations.of(context)!,
    ).map((part) => part.text).join();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class MessageRow extends StatelessWidget {
  const MessageRow({
    required this.message,
    required this.loadAttachment,
    super.key,
    this.steering = false,
    this.stepStartedAtEpochMs,
    this.stepEndedAtEpochMs,
    this.backendId,
    this.onFork,
    this.usage,
    this.firstTokenAtEpochMs,
    this.producedPaths,
    this.presentedFiles,
    this.onPreviewFile,
  });

  final ChatMessage message;

  /// Whether a durable inbox splice admitted this message into a running
  /// turn's next step ([TimelineMessage.steering]); the user row then wears
  /// the steering badge.
  final bool steering;

  /// The owning step's `step/start` and `step/end` logged times, when the
  /// folded window carried both; the answer row then names the step's range.
  final int? stepStartedAtEpochMs;
  final int? stepEndedAtEpochMs;
  final AttachmentLoader loadAttachment;

  /// The backend presenting this transcript; null hides the reply footer's
  /// feedback pair (a bare pump, or a read-only child record).
  final String? backendId;

  /// Cuts a new session at this message (host: the end of the turn that
  /// contains it). Null while the message carries no logged position —
  /// a locally composed row has nothing to anchor.
  final VoidCallback? onFork;

  /// Provider token accounting this assistant message carried; null when
  /// the host reported none.
  final TokenUsage? usage;

  /// Timestamp of this message's first output delta; null when unrecorded.
  final int? firstTokenAtEpochMs;

  /// Paths the turn's successful mutations produced; rendered between the
  /// body and the action row on the closing assistant message.
  final List<String>? producedPaths;

  /// Files the turn's successful `present` calls declared; rendered under the
  /// produced-files row, before the action row.
  final List<PresentedFile>? presentedFiles;

  /// Opens a produced path with the in-app preview sheet.
  final void Function(String path)? onPreviewFile;

  @override
  Widget build(BuildContext context) {
    if (message.role == MessageRole.user) {
      // The reader's own words: the reference's bubble, right-aligned, with
      // maxWidth capped at 82% (up to 525dp) so short messages fit their
      // content while long runs wrap cleanly.
      // No action row rides under it — long-press copies, and the reply's
      // row already dates the turn.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // A steering message is human input `agent/inbox/spliced` admitted
          // into the running turn's next step; the badge names it so the
          // reader can tell it from a new ask.
          if (steering) const _SteeringBadge(),
          Align(
            alignment: Alignment.centerRight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double cap = constraints.maxWidth * 0.82;
                final double maxWidth = cap > 525 ? 525 : cap;
                return ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: _UserBubble(text: message.text, onFork: onFork),
                );
              },
            ),
          ),
          for (final ref in message.images)
            AttachmentImageRow(
              sessionId: message.sessionId,
              ref: ref,
              loadAttachment: loadAttachment,
            ),
        ],
      );
    }
    // Assistant: flat markdown column (Think row + body + media).
    final l10n = AppLocalizations.of(context)!;
    final paths = producedPaths;
    final presented = presentedFiles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.reasoning case final String reasoning
            when reasoning.isNotEmpty)
          ReasoningRow(
            text: reasoning,
            running: message.streaming,
            elapsedDuration: message.reasoningDuration,
          ),
        if (message.text.isNotEmpty) MarkdownText(text: message.text),
        // The step's own range, beside the answer it produced. A step whose
        // start or end fell outside the folded window renders nothing rather
        // than a guess; the turn control keeps the turn's total.
        if (stepStartedAtEpochMs != null && stepEndedAtEpochMs != null)
          _StepDuration(
            startedAtEpochMs: stepStartedAtEpochMs!,
            endedAtEpochMs: stepEndedAtEpochMs!,
          ),
        for (final ref in message.images)
          AttachmentImageRow(
            sessionId: message.sessionId,
            ref: ref,
            loadAttachment: loadAttachment,
          ),
        // The turn's produced files close the body, above the action row —
        // the reference turn-tail order (ProducedFiles, then the presented
        // cards, then MessageIconActions). Streaming hides them: the rows
        // belong to a finished turn.
        if (!message.streaming &&
            paths != null &&
            paths.isNotEmpty &&
            onPreviewFile != null)
          ProducedFilesRow(paths: paths, onOpenFile: onPreviewFile!),
        if (!message.streaming &&
            presented != null &&
            presented.isNotEmpty &&
            onPreviewFile != null)
          PresentedFilesRow(files: presented, onOpenFile: onPreviewFile!),
        if (message.streaming) ...[
          // Once text flows the streaming tail is the blinking caret;
          // the pre-first-token wait is said once, by the turn-status
          // line at the timeline tail — not a loader here too.
          if (message.text.isNotEmpty)
            const _StreamingCaret(key: ValueKey('streaming-caret')),
        ] else if (message.text.isNotEmpty) ...[
          MessageIconActions(
            text: message.text,
            timeEpochMs: message.createdAtEpochMs,
            clockAtStart: false,
            onFork: onFork,
            metrics: messageRunMetricsText(
              usage: usage,
              firstTokenAtEpochMs: firstTokenAtEpochMs,
              messageAtEpochMs: message.createdAtEpochMs,
              l10n: l10n,
            ),
          ),
        ],
      ],
    );
  }
}

/// The reader's message container: the reference's `--dsw-specific-bubble`
/// fill ([DshSchemeColors.bubble]) on the one `--dsw-radius-xl` step
/// ([kShapeBubble]), every corner alike. Long-press copies the text — the
/// gesture every mobile transcript carries — so the bubble needs no chrome of
/// its own.
/// The eyebrow over a steering message — one a durable `agent/inbox/spliced`
/// claimed from the running turn's next-step inbox.
///
/// The reference renders a user row and a steering row on one shared bubble
/// (`MessageItem.tsx:161`) and marks the row only with `data-pending-steering`
/// (`:191`), which carries no visible style, so nothing in the pin tells the
/// two apart: this badge is the phone's own affordance over a fact the fold
/// already decided ([TimelineMessage.steering]).
class _SteeringBadge extends StatelessWidget {
  const _SteeringBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(right: 4, bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.subdirectory_arrow_right,
            size: 14,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            l10n.steeringMessageBadge,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserBubble extends StatefulWidget {
  const _UserBubble({required this.text, this.onFork});

  final String text;
  final VoidCallback? onFork;

  @override
  State<_UserBubble> createState() => _UserBubbleState();
}

class _UserBubbleState extends State<_UserBubble> {
  String get text => widget.text;
  VoidCallback? get onFork => widget.onFork;

  Future<void> _copy(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.copiedTooltip),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  /// The bubble's verbs, at the press point: copy always, fork when the
  /// message has a logged position to cut at.
  /// The bubble's verbs, in the house menu sheet: the pin's menu material
  /// (fill over the backdrop, the half-pixel ring, `kRadiusLg` and
  /// `DshElevation.prominent`) rather than the framework `showMenu`, whose
  /// `MenuStyle` can carry only the fill composite and a corner.
  Future<void> _openMenu(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final verb = await showMenuSheet<_BubbleVerb>(
      context,
      // The pins the tiles' Material directly above them: the menu material's
      // translucent fill is a decoration between the sheet's Material and the
      // ListTiles, and a ListTile needs an undecorated Material parent.
      builder: (sheetContext) => Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.copy_outlined, size: 18),
              title: Text(l10n.copyTooltip),
              onTap: () => Navigator.of(sheetContext).pop(_BubbleVerb.copy),
            ),
            if (onFork != null)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.alt_route, size: 18),
                title: Text(l10n.forkFromHere),
                onTap: () => Navigator.of(sheetContext).pop(_BubbleVerb.fork),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (verb) {
      case _BubbleVerb.copy:
        await _copy(context);
      case _BubbleVerb.fork:
        onFork?.call();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (text.isEmpty) return const SizedBox.shrink();
    return Material(
      color: theme.colorScheme.bubble,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kShapeBubble),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onLongPress: () => _openMenu(context),
        child: Padding(
          // The reference's 42px single-line bubble: a 22px line plus 10px of
          // vertical padding, 16px at the sides (`MessageItem.module.css`
          // .bubble, :24-33).
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            text,
            // The reference's bubble reads the content size on its 22px line
            // in `label-primary` (`MessageItem.module.css:24-33`).
            style: DshType.s14.style(color: theme.colorScheme.labelPrimary),
          ),
        ),
      ),
    );
  }
}

enum _BubbleVerb { copy, fork }

/// Pending steering at the conversation tail — the port of the web's
/// `PendingSteeringBubble` (`ChatView.tsx:454-460`, `MessageItem.tsx:257-
/// 278`). The web shows it as a plain user bubble with no decoration; on a
/// phone an undecorated bubble cannot be told from a delivered message, so
/// the row wears this client's existing pending-row language — the
/// activity dot and sweep glare of a running step, with the host's steer
/// verb as the caption — while keeping the reader's right-aligned bubble
/// geometry so it still reads as their own words. The row is transient by
/// nature: the host's claim replaces it with the durable user message.
class PendingSteeringRow extends StatefulWidget {
  const PendingSteeringRow({required this.text, super.key});

  final String text;

  @override
  State<PendingSteeringRow> createState() => _PendingSteeringRowState();
}

class _PendingSteeringRowState extends State<PendingSteeringRow>
    with SingleTickerProviderStateMixin {
  /// The glare band's pass — the shared in-flight period (turn-status row,
  /// reasoning and tool rows).
  static const Duration _glarePeriod = Duration(milliseconds: 1800);

  late final AnimationController _glare = AnimationController(
    vsync: this,
    duration: _glarePeriod,
  )..repeat();

  @override
  void dispose() {
    _glare.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final reduced = DshMotion.isReducedMotion(context);
    return Align(
      alignment: Alignment.centerRight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double cap = constraints.maxWidth * 0.82;
          final double maxWidth = cap > 525 ? 525 : cap;
          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ActivityDot(),
                      const SizedBox(width: 8),
                      Text(
                        l10n.steeringPending,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                SweepHighlight(
                  controller: reduced ? null : _glare,
                  child: _UserBubble(text: widget.text),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Streaming assistant tail: a 2×18 primary caret blinking at 1s once
/// text flows. Before the first token the turn's wait belongs to the
/// [RunningStatusRow] at the timeline tail, so the transcript never carries
/// two tail signals at once.
class _StreamingCaret extends StatefulWidget {
  const _StreamingCaret({super.key});

  @override
  State<_StreamingCaret> createState() => _StreamingCaretState();
}

class _StreamingCaretState extends State<_StreamingCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  @override
  void initState() {
    super.initState();
    _blink.repeat(reverse: true);
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: _blink,
      child: Container(width: 2, height: 18, color: scheme.primary),
    );
  }
}

/// Draft-image thumbnail: decode the pending base64 payload once per
/// image, downsampled to icon size. The name chip stays if the bytes
/// fail to decode.
class PendingImageThumbnail extends StatefulWidget {
  const PendingImageThumbnail({required this.image, super.key});

  final PendingImage image;

  @override
  State<PendingImageThumbnail> createState() => _PendingImageThumbnailState();
}

class _PendingImageThumbnailState extends State<PendingImageThumbnail> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    unawaited(
      Future<void>(() {
        try {
          final bytes = base64Decode(widget.image.base64Data);
          if (mounted) setState(() => _bytes = bytes);
        } catch (_) {
          // The name chip stays when the bytes fail to decode.
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return const SizedBox(width: 36, height: 36);
    return ClipRRect(
      borderRadius: BorderRadius.circular(kShapeChip),
      child: Image.memory(
        bytes,
        cacheWidth: 128,
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const SizedBox(width: 36, height: 36),
      ),
    );
  }
}

/// One durable image: lazy download through the loader, placeholder on
/// failure.
class AttachmentImageRow extends StatefulWidget {
  const AttachmentImageRow({
    required this.sessionId,
    required this.ref,
    required this.loadAttachment,
    super.key,
  });

  final String sessionId;
  final AttachmentRef ref;
  final AttachmentLoader loadAttachment;

  @override
  State<AttachmentImageRow> createState() => _AttachmentImageRowState();
}

class _AttachmentImageRowState extends State<AttachmentImageRow> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    unawaited(
      widget.loadAttachment(widget.sessionId, widget.ref).then((bytes) {
        if (mounted) setState(() => _bytes = bytes);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        width: double.infinity,
        child: bytes != null
            ? Image.memory(
                bytes,
                width: double.infinity,
                height: 180,
                fit: BoxFit.fitWidth,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _placeholder(context),
              )
            : _placeholder(context),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ref = widget.ref;
    final name = ref.name;
    final nameSuffix = name == null ? '' : l10n.imagePlaceholderSuffix(name);
    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.imageLoadingPlaceholder(
              ref.bytes,
              ref.height,
              nameSuffix,
              ref.width,
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        OutlinedButton(
          onPressed: () {
            setState(() => _bytes = null);
            _load();
          },
          child: Text(l10n.retry),
        ),
      ],
    );
  }
}

/// One folded execution phase: the thoughts, injected context and tool calls
/// that ran between two transcript anchors, behind a single collapsed header.
/// The card owns the phase's only disclosure — its members render inline, so a
/// phase that reasoned, was handed context and then ran tools reads as one
/// step instead of a stack of folded rows.
class ActivityGroupRow extends StatefulWidget {
  const ActivityGroupRow({
    required this.group,
    required this.onAction,
    required this.loadAttachment,
    super.key,
    this.sessionId,
    this.onPreviewFile,
    this.expansion,
    this.onOpenChild,
  });

  final TimelineActivityGroup group;
  final void Function(ChatAction) onAction;
  final AttachmentLoader loadAttachment;

  /// Session a member's durable result images are read against.
  final String? sessionId;

  /// File-preview action for a grouped tool row's generated/edited path.
  final void Function(String path, {EditDiffModel? diff})? onPreviewFile;

  final ToolExpansionPersistence? expansion;

  /// Jump target for a grouped workflow member's child session.
  final WorkflowMemberOpener? onOpenChild;

  @override
  State<ActivityGroupRow> createState() => _ActivityGroupRowState();
}

class _ActivityGroupRowState extends State<ActivityGroupRow>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  /// The row's activity clock. [SweepHighlight] reads the pinned
  /// [kSweepCycle] off this clock's elapsed time, so the controller only has to
  /// repeat.
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: kSweepCycle,
  );

  bool get _isRunning =>
      widget.group.calls.any((call) => call.status == ToolRunStatus.running) ||
      (widget.group.thought?.value.streaming ?? false);

  bool get _hasFailure =>
      widget.group.calls.any((call) => call.status == ToolRunStatus.failed);

  /// Whether the reader has toggled this fold, so a restore landing late cannot
  /// undo the tap that came after it.
  bool _toggled = false;

  String get _expansionKey => 'activity-group:${widget.group.id}';

  @override
  void initState() {
    super.initState();
    if (_hasFailure && !_isRunning) _expanded = true;
    if (_isRunning) _sweep.repeat();
    final expansion = widget.expansion;
    if (expansion != null) {
      unawaited(
        expansion.expanded(_expansionKey).then((restored) {
          if (!mounted || _toggled || restored == _expanded) return;
          setState(() => _expanded = restored);
        }),
      );
    }
  }

  void _toggle() {
    _toggled = true;
    setState(() => _expanded = !_expanded);
    unawaited(widget.expansion?.setExpanded(_expansionKey, _expanded));
  }

  @override
  void didUpdateWidget(covariant ActivityGroupRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasRunning =
        oldWidget.group.calls.any(
          (call) => call.status == ToolRunStatus.running,
        ) ||
        (oldWidget.group.thought?.value.streaming ?? false);
    if (wasRunning && !_isRunning && _hasFailure && !_expanded) {
      setState(() => _expanded = true);
    }
    if (_isRunning && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if (!_isRunning && _sweep.isAnimating) {
      _sweep.stop(canceled: true);
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.group.entries;
    final calls = widget.group.calls;
    final thought = widget.group.thought;
    // The member list is a second row list, and a duplicate identity inside it
    // bleeds state exactly as one at the top level does.
    indexRowsByKey(entries);

    // The group's ranked work and the one line it is doing now: the reference
    // grouping's own `processActivity` model drives both the settled title
    // (its top three categories) and the live label with its running detail.
    final summary = deriveProcessActivity(
      calls,
      reasoningDetail: () => latestReasoningDetail(thought?.value.reasoning),
    );
    final running = summary.running != null;

    // The group header is the reference's process card: a 16px leading box
    // holding the category icon under a chevron that fades in on hover or
    // while open, then the label — the running detail joins it after the
    // locale's separator. Only the label rides the sweep, so the leading box
    // stays outside the highlight.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProcessGroupHeader(
          summary: summary,
          closed: widget.group.closed,
          open: _expanded,
          sweep: running && !DshMotion.isReducedMotion(context) ? _sweep : null,
          onTap: _toggle,
        ),
        // The phase divides from what follows with the header's own 8px
        // gap; the transcript's rows carry no rules of their own.
        if (_expanded) ...[
          // The reference's group body is a flat scroller: no indent, no
          // gutter rule — its members are the same seats the transcript lays
          // out (`ChatGroupSeat.module.css` `.body`, :87-93, carries only the
          // cap, the scroll and the fade). The members keep the transcript's
          // own step rhythm.
          ProcessGroupBody(
            startAtBottom: !widget.group.closed,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  // The reference's group body steps its members at the
                  // flow gap's 6px (`ChatGroupSeat.module.css` `.body`, :87-88).
                  if (i > 0) const SizedBox(height: 6),
                  switch (entries[i]) {
                    final TimelineToolCall call => ToolCallRow(
                      key: transcriptRowKey(call),
                      call: call,
                      sessionId: widget.sessionId,
                      loadAttachment: widget.loadAttachment,
                      onPreviewFile: widget.onPreviewFile,
                      expansion: widget.expansion,
                    ),
                    final TimelineContextInjection injection => Material(
                      type: MaterialType.transparency,
                      child: ContextInjectionRow(
                        key: transcriptRowKey(injection),
                        injection: injection,
                      ),
                    ),
                    TimelineMessage(:final value) => Material(
                      type: MaterialType.transparency,
                      child: ReasoningRow(
                        key: transcriptRowKey(entries[i]),
                        text: value.reasoning ?? '',
                        running: value.streaming,
                        elapsedDuration: value.reasoningDuration,
                      ),
                    ),
                    _ => const SizedBox.shrink(),
                  },
                ],
              ],
            ),
          ),
        ] else
          // A closed fold keeps the header's 8px tail, so the phase reads as
          // a block rather than a step.
          const SizedBox(height: 8),
      ],
    );
  }
}

/// Tool summary row — port of the web ToolRow (figma 122:9479): one 24px
/// line [leading state slot] gap6 [title] dot [summary FILL truncate]; the
/// details (arguments + result) expand below on tap. Running rows carry the
/// shared sweep glare — the web row's contract, where the sweep, not a
/// spinner, is the in-flight motion. The leading slot keeps one 14px
/// geometry across the run (activity dot / success check / error cross) so
/// the row's left edge never jumps at settle, and the title sets the
/// monospace stack; the expanded details render as the web IN/OUT card
/// (bordered code surface with gutter labels and a hairline divider).
class ToolCallRow extends StatefulWidget {
  const ToolCallRow({
    required this.call,
    super.key,
    this.sessionId,
    this.loadAttachment = _noAttachmentBytes,
    this.expansion,
    this.onPreviewFile,
  });

  final TimelineToolCall call;

  /// Session the durable images of this call are read against; null keeps
  /// the image body hidden (a bare test pump owns no repository).
  final String? sessionId;

  /// Session-authorized byte loader for a result image reference.
  final AttachmentLoader loadAttachment;

  /// Expansion persistence keyed by this row's [timelineKey] value;
  /// null keeps expansion in memory only.
  final ToolExpansionPersistence? expansion;
  final void Function(String path, {EditDiffModel? diff})? onPreviewFile;

  @override
  State<ToolCallRow> createState() => _ToolCallRowState();
}

class _ToolCallRowState extends State<ToolCallRow>
    with SingleTickerProviderStateMixin {
  /// Whether the row's body is open. The reference's tool row owns its own
  /// disclosure (`ToolRow.tsx:145`, `DisclosureRow`'s `useDisclosure`), and its
  /// header is a 24px line, not a Material tile.
  bool _expanded = false;

  /// Opens or closes the body and records the reader's fold, so a remount
  /// restores what they opened.
  void _toggle() {
    setState(() => _expanded = !_expanded);
    unawaited(
      widget.expansion?.setExpanded(timelineKey(widget.call), _expanded),
    );
  }

  /// The row's activity clock. [SweepHighlight] reads the pinned
  /// [kSweepCycle] off this clock's elapsed time, so the controller only has to
  /// repeat.
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: kSweepCycle,
  );

  @override
  void initState() {
    super.initState();
    final expansion = widget.expansion;
    if (expansion != null) {
      final key = timelineKey(widget.call);
      unawaited(
        expansion.expanded(key).then((restored) {
          // Restore through the native controller: the tile reads this same
          // instance at initState, so a restore landing before or after the
          // first build both take effect.
          if (mounted && restored && !_expanded) {
            setState(() => _expanded = true);
          }
        }),
      );
    }
    if (widget.call.status == ToolRunStatus.failed && !_expanded) {
      _expanded = true;
    }
    if (widget.call.status == ToolRunStatus.running) _sweep.repeat();
  }

  @override
  void didUpdateWidget(covariant ToolCallRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final running = widget.call.status == ToolRunStatus.running;
    if (running && oldWidget.call.status != ToolRunStatus.running) {
      _sweep.repeat();
    }
    if (!running && oldWidget.call.status == ToolRunStatus.running) {
      _sweep.stop(canceled: true);
      if (widget.call.status == ToolRunStatus.failed && !_expanded) {
        setState(() => _expanded = true);
      }
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final call = widget.call;
    final model = deriveToolRowModel(call, l10n);
    final running = model.state == ToolRowState.running;
    final failed = model.state == ToolRowState.error;
    // A result that carried durable images renders the reference's image
    // card instead of the generic IN/OUT body: the text envelope (path,
    // media type, pixel size) reads as the card's meta line under the
    // gallery, and the args never take a card of their own.
    final images = widget.sessionId == null || failed
        ? const <AttachmentRef>[]
        : call.images;
    final hasDetails =
        model.body != null || model.output != null || images.isNotEmpty;
    // The row keeps the pin's disclosure chrome: a fixed 24px line whose
    // leading box holds the tool's business glyph, stepping its tone on hover,
    // with the chevron only while there is a body to disclose
    // (`DisclosureRow.module.css:19-28`, :47-69; `ToolRow.tsx:167`). The run
    // state is colour-only in the pin, so its hidden state label is announced
    // rather than drawn (`ToolRow.tsx:104-113`).
    final String summaryText = failed && model.errorSummary != null
        ? model.errorSummary!
        : model.summary;
    return DisclosureRow(
      open: _expanded,
      expandable: hasDetails,
      onToggle: _toggle,
      semanticLabel: running
          ? l10n.semanticsRunning
          : failed
          ? l10n.semanticsFailed
          : null,
      stateLabel: running
          ? l10n.runStatusRunning
          : failed
          ? l10n.runStatusFailed
          : l10n.runStatusDone,
      header: (BuildContext context, Color color) => ClipRect(
        child: SweepHighlight(
          controller: running && !DshMotion.isReducedMotion(context)
              ? _sweep
              : null,
          child: Padding(
            padding: EdgeInsets.zero,
            child: Row(
              children: [
                // The pin's leading slot holds the tool's **business**
                // glyph in a 16px box — never a status mark: a product
                // row supplies its own (the todo checklist,
                // `todo-row.tsx:65`), every other row its variant glyph
                // (`GenericToolCard.tsx:17-25`).
                SizedBox(
                  width: 16,
                  height: 16,
                  child: Center(
                    child: Icon(
                      model.leading ?? variantIcon(model.variant),
                      size: 14,
                      color: color,
                    ),
                  ),
                ),
                // Web DisclosureRow / ToolRow header: `[16 leading] gap6
                // [title 13] gap8 [2x2 dot] gap8 [summary FILL
                // truncate]` — the verb is a label, the payload is data,
                // and neither is bold or monospace. An empty summary
                // drops the dot with it (`ToolRow.tsx:210-213`).
                const SizedBox(width: 6),
                Text(
                  model.title,
                  style: DshType.chatRowTitle.style(color: color),
                ),
                if (summaryText.isNotEmpty)
                  Container(
                    width: 2,
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: scheme.labelCaption,
                      shape: BoxShape.circle,
                    ),
                  ),
                Expanded(
                  child: Text(
                    // Web ToolRow: the summary is args-derived; the
                    // settled result text never reaches this slot. A
                    // failure keeps its own tone (`ToolRow.module.css`
                    // `.errorSummary`, :80-82).
                    summaryText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DshType.chatRowTitle.style(
                      color: failed ? scheme.stateErrorPrimary : color,
                    ),
                  ),
                ),
                // The todo parallel-active count rides a
                // non-shrinking suffix beside the truncatable text.
                if (model.summarySuffix case final suffix?) ...[
                  const SizedBox(width: 4),
                  Text(suffix, style: DshType.chatRowTitle.style(color: color)),
                ],
              ],
            ),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (images.isNotEmpty) ...[
            // The reference image card: the gallery, then the model-facing
            // envelope (path, media type, pixel size) as its meta line.
            ToolImageGallery(
              sessionId: widget.sessionId!,
              images: images,
              loadAttachment: widget.loadAttachment,
            ),
            if (model.output case final output?)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 14, 4),
                child: Text(
                  output,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ] else if (hasDetails)
            Container(
              width: double.infinity,
              // The reference's expanded IO card (`ToolRow.module.css`
              // `.ioCard`, :181-189): `margin: 4px 0 4px 4px`, a half-pixel
              // `border-l1` hairline, the code-block radius and surface.
              margin: const EdgeInsets.fromLTRB(4, 4, 0, 4),
              decoration: BoxDecoration(
                color: scheme.markdownCodeBlock,
                borderRadius: BorderRadius.circular(kRadiusLg),
                border: Border.all(color: scheme.borderL1, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (model.diff case final diff?)
                    _diffSection(context, diff)
                  else if (model.body case final body?)
                    _ioSection(context, l10n.inputLabel, body, failed: false),
                  if ((model.diff != null || model.body != null) &&
                      model.output != null)
                    Container(
                      height: 1,
                      color: scheme.outlineVariant,
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                  if (model.output case final output?)
                    _ioSection(
                      context,
                      l10n.outputLabel,
                      output,
                      failed: failed,
                    ),
                  if (model.filePath case final filePath?)
                    _fileActionBar(
                      context,
                      filePath,
                      title: model.title,
                      diff: model.diff,
                      input: model.body,
                      output: model.output,
                      failed: failed,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _fileActionBar(
    BuildContext context,
    String path, {
    required String title,
    EditDiffModel? diff,
    String? input,
    String? output,
    bool failed = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          // The peek is bounded, so the whole payload gets its own surface: the
          // row keeps one line and the content opens one level deeper.
          OutlinedButton.icon(
            onPressed: () => showToolDetail(
              context,
              args: ToolDetailArgs(
                title: title,
                diff: diff,
                input: input,
                output: output,
                failed: failed,
                path: path,
              ),
              onPreviewFile: widget.onPreviewFile,
            ),
            icon: const Icon(Icons.open_in_full, size: 14),
            label: Text(
              l10n.open,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              side: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          if (widget.onPreviewFile != null)
            OutlinedButton.icon(
              onPressed: () => widget.onPreviewFile!(path, diff: diff),
              icon: const Icon(Icons.visibility_outlined, size: 14),
              label: Text(
                l10n.previewFile,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                ),
              ),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                side: BorderSide(color: scheme.outlineVariant),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () {
              unawaited(Clipboard.setData(ClipboardData(text: path)));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.copiedFeedback),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            icon: Icon(
              Icons.copy_outlined,
              size: 14,
              color: scheme.onSurfaceVariant,
            ),
            label: Text(
              l10n.copyPath,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              side: BorderSide(color: scheme.outlineVariant),
            ),
          ),
        ],
      ),
    );
  }

  /// One IN/OUT gutter-label section of the expanded card: sticky-label
  /// caption beside the monospace payload (web ToolRow .io-section).
  Widget _ioSection(
    BuildContext context,
    String label,
    String payload, {
    required bool failed,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.outline,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                child: Text(
                  payload,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: failed
                        ? theme.colorScheme.error
                        : scheme.onSurfaceVariant,
                    fontFamily: kCodeFontFamily,
                    fontFamilyFallback: kCodeFontFamilyFallback,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            tooltip: l10n.copyTooltip,
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: payload));
              messenger.showSnackBar(
                SnackBar(
                  content: Text(l10n.copiedTooltip),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(milliseconds: 1400),
                ),
              );
            },
            icon: Icon(Icons.copy_outlined, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _diffSection(BuildContext context, EditDiffModel diff) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final fullDiffText = diffPlainText(diff);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.diffLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.outline,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            // The peek is bounded: the transcript is the surface the reader is
            // reading, and the whole diff opens one level deeper
            // ([showToolDetail]).
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(child: DiffLineList(diff: diff)),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            tooltip: l10n.copyTooltip,
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: fullDiffText));
              messenger.showSnackBar(
                SnackBar(
                  content: Text(l10n.copiedTooltip),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(milliseconds: 1400),
                ),
              );
            },
            icon: Icon(Icons.copy_outlined, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

String toolRunStatusLabel(ToolRunStatus status, AppLocalizations l10n) =>
    switch (status) {
      ToolRunStatus.running => l10n.runStatusRunning,
      ToolRunStatus.completed => l10n.runStatusDone,
      ToolRunStatus.failed => l10n.runStatusFailed,
    };

/// The goal indicator docked above the message composer (web GoalBar).
/// A present goal shows a goal glyph, a phase label, the truncated
/// objective, and icon actions: pause / resume, inline edit in the same
/// strip, and clear. Renders nothing when goal is null or complete.
class GoalBarStrip extends StatefulWidget {
  const GoalBarStrip({required this.goal, required this.onAction, super.key});

  final GoalProjection? goal;
  final void Function(ChatAction) onAction;

  @override
  State<GoalBarStrip> createState() => _GoalBarStripState();
}

class _GoalBarStripState extends State<GoalBarStrip> {
  bool _editing = false;
  late final TextEditingController _editController = TextEditingController();
  String? _lastGoalId;

  @override
  void initState() {
    super.initState();
    _syncDraft();
  }

  @override
  void didUpdateWidget(covariant GoalBarStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentId = widget.goal?.goal.id;
    if (currentId != _lastGoalId) {
      _editing = false;
      _syncDraft();
    }
  }

  void _syncDraft() {
    _lastGoalId = widget.goal?.goal.id;
    final objective = widget.goal?.goal.objective ?? '';
    _editController.text = objective;
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  void _submitEdit() {
    final trimmed = _editController.text.trim();
    if (trimmed.isEmpty) return;
    widget.onAction(EditGoal(trimmed));
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final projection = widget.goal;
    if (projection == null) return const SizedBox.shrink();
    final snapshot = projection.goal;
    if (snapshot.phase == GoalPhase.complete) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    // Inline edit form in the exact same strip (reference GoalBar.tsx)
    if (_editing) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Container(
          height: 36,
          padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(kShapeDock),
            ),
            border: Border(
              top: BorderSide(color: scheme.outlineVariant),
              left: BorderSide(color: scheme.outlineVariant),
              right: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.track_changes_outlined,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _editController,
                  autofocus: true,
                  style: theme.textTheme.bodySmall,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: (_) => _submitEdit(),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 14,
                tooltip: l10n.save,
                onPressed: _submitEdit,
                icon: Icon(Icons.check, size: 14, color: scheme.primary),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 14,
                tooltip: l10n.cancel,
                onPressed: () {
                  _syncDraft();
                  setState(() => _editing = false);
                },
                icon: Icon(
                  Icons.close,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final phaseLabel = switch (snapshot.phase) {
      GoalPhase.active => l10n.chatGoalPhaseActive,
      GoalPhase.paused => l10n.chatGoalPhasePaused,
      GoalPhase.blocked => l10n.chatGoalPhaseBlocked,
      GoalPhase.complete => '',
    };

    final phaseColor = switch (snapshot.phase) {
      GoalPhase.active => scheme.secondary,
      GoalPhase.paused => scheme.onSurfaceVariant,
      GoalPhase.blocked => scheme.error,
      GoalPhase.complete => scheme.onSurfaceVariant,
    };

    final tooltipText = snapshot.phase == GoalPhase.blocked
        ? snapshot.blockedReason
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(kShapeDock),
          ),
          border: Border(
            top: BorderSide(color: scheme.outlineVariant),
            left: BorderSide(color: scheme.outlineVariant),
            right: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.track_changes_outlined,
              size: 14,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              phaseLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: phaseColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Tooltip(
                message: tooltipText ?? snapshot.objective,
                child: Text(
                  snapshot.objective,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
            if (snapshot.phase == GoalPhase.active)
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 14,
                tooltip: l10n.pauseGoal,
                onPressed: () => widget.onAction(const ToggleGoalPause()),
                icon: Icon(
                  Icons.pause_outlined,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            if (snapshot.phase == GoalPhase.paused ||
                snapshot.phase == GoalPhase.blocked)
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 14,
                tooltip: l10n.resumeGoal,
                onPressed: () => widget.onAction(const ToggleGoalPause()),
                icon: Icon(
                  Icons.play_arrow_outlined,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 14,
              tooltip: l10n.edit,
              onPressed: () {
                _syncDraft();
                setState(() => _editing = true);
              },
              icon: Icon(
                Icons.edit_outlined,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 14,
              tooltip: l10n.clearGoal,
              onPressed: () => widget.onAction(const ClearGoal()),
              icon: Icon(
                Icons.delete_outline,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Queue dock — port of the web QueueDock (FileContainerText 1:791): a
/// panel attached above the composer card, r12 top corners, tip fill,
/// l1 border (the composer card's own edge closes the bottom). One
/// queued message renders directly; several collapse behind a count
/// header; only `queued`-placement rows ride the dock (steering rides
/// the timeline, context the injection rows).
class QueueDock extends StatefulWidget {
  const QueueDock({
    required this.items,
    required this.running,
    required this.onAction,
    super.key,
  });

  final List<SessionQueueItem> items;
  final bool running;
  final void Function(ChatAction) onAction;

  @override
  State<QueueDock> createState() => _QueueDockState();
}

class _QueueDockState extends State<QueueDock> {
  bool _collapsed = true;

  @override
  Widget build(BuildContext context) {
    final queue = widget.items
        .where((item) => item.placement == QueuePlacement.queued)
        .toList();
    if (queue.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    // Interaction reopens the list; an emptied queue recollapses (web
    // effect).
    final expanded = !_collapsed || queue.length == 1;
    // The reference's queue panel (`ui-conversation/src/client/queue/
    // QueueDock.module.css` `.panel`, :31-58): the menu material on its own
    // backdrop, the radius-lg step on the top corners only (the panel attaches
    // under the input card, whose own top border closes the shape), a
    // half-pixel `border-l1` hairline that stops at the bottom edge (:51-57),
    // and no shadow. Inside the now-white dock this is what used to read as a
    // grey stripe.
    return MenuMaterial(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(kRadiusLg),
      ),
      borderBottom: false,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (queue.length > 1)
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(kShapeChip),
                onTap: () => setState(() => _collapsed = !_collapsed),
                child: SizedBox(
                  height: 36,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.queue,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l10n.queuedMessagesCount(queue.length),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ),
                        Icon(
                          expanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_up,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (expanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: queue.length,
                itemBuilder: (context, index) => _QueueItemRow(
                  key: ValueKey(queue[index].itemId),
                  item: queue[index],
                  // Single-item strip has no count header, so the row
                  // itself carries the queue glyph.
                  leadIcon: queue.length == 1,
                  running: widget.running,
                  separated: index > 0,
                  onAction: widget.onAction,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One queued row (web `.row`): 36px tall, 12/5 padding, 1px inset
/// hairline above every row but the first; the preview is a single
/// 13px dimmed line, and the trailing actions are 28px circles (edit →
/// inline editor, steer — only while the turn runs, remove).
class _QueueItemRow extends StatefulWidget {
  const _QueueItemRow({
    required this.item,
    required this.leadIcon,
    required this.running,
    required this.separated,
    required this.onAction,
    super.key,
  });

  final SessionQueueItem item;
  final bool leadIcon;
  final bool running;
  final bool separated;
  final void Function(ChatAction) onAction;

  @override
  State<_QueueItemRow> createState() => _QueueItemRowState();
}

class _QueueItemRowState extends State<_QueueItemRow> {
  final TextEditingController _editor = TextEditingController();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _editor.text = widget.item.text;
  }

  @override
  void didUpdateWidget(covariant _QueueItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.item.text != widget.item.text) {
      _editor.text = widget.item.text;
    }
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  void _save() {
    final text = _editor.text.trim();
    if (text.isEmpty) return;
    widget.onAction(
      UpdateQueueAction(
        itemId: widget.item.itemId,
        kind: QueueUpdateKind.edit,
        text: text,
      ),
    );
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final item = widget.item;
    return Container(
      decoration: BoxDecoration(
        border: widget.separated
            ? Border(top: BorderSide(color: scheme.outlineVariant))
            : null,
      ),
      child: SizedBox(
        height: 36,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 5, 4),
          child: Row(
            children: [
              if (widget.leadIcon) ...[
                Icon(Icons.queue, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: _editing
                    ? SizedBox(
                        height: 28,
                        child: TextField(
                          controller: _editor,
                          autofocus: true,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                          ),
                          onSubmitted: (_) => _save(),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: l10n.editQueuedMessageHint,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(kShapeChip),
                              borderSide: BorderSide(
                                color: scheme.outlineVariant,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(kShapeChip),
                              borderSide: BorderSide(
                                color: scheme.outlineVariant,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(kShapeChip),
                              borderSide: BorderSide(color: scheme.primary),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                          ),
                        ),
                      )
                    : Text(
                        item.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              if (_editing) ...[
                _QueueAction(
                  tooltip: l10n.saveQueuedMessage,
                  icon: Icons.check,
                  onTap: _save,
                ),
                _QueueAction(
                  tooltip: l10n.cancelEdit,
                  icon: Icons.close,
                  onTap: () => setState(() => _editing = false),
                ),
              ] else ...[
                // Web rule: editing is a text-only affordance; a
                // non-text row keeps the button disabled.
                _QueueAction(
                  tooltip: l10n.editQueuedMessageHint,
                  icon: Icons.edit_outlined,
                  enabled: item.text.trim().isNotEmpty,
                  onTap: () => setState(() => _editing = true),
                ),
                _QueueAction(
                  tooltip: l10n.steer,
                  icon: Icons.send_outlined,
                  // Web: steering needs the running window.
                  enabled: widget.running,
                  onTap: () => widget.onAction(
                    UpdateQueueAction(
                      itemId: item.itemId,
                      kind: QueueUpdateKind.steer,
                    ),
                  ),
                ),
                _QueueAction(
                  tooltip: l10n.removeQueuedMessage,
                  icon: Icons.delete_outline,
                  onTap: () => widget.onAction(
                    UpdateQueueAction(
                      itemId: item.itemId,
                      kind: QueueUpdateKind.remove,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One dock action (web `.action`): a standard [IconButton] squeezed to
/// the 28px web visual via its constraints — native ripple, focus, and
/// disabled handling on the compact 36px dock-row footprint.
class _QueueAction extends StatelessWidget {
  const _QueueAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 14),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      style: IconButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        disabledForegroundColor: scheme.onSurfaceVariant.withValues(
          alpha: 0.45,
        ),
        hoverColor: scheme.surfaceContainerHigh,
      ),
    );
  }
}

class QuestionRow extends StatefulWidget {
  const QuestionRow({required this.request, required this.onAction, super.key});

  final TimelineQuestionRequest request;
  final void Function(ChatAction) onAction;

  @override
  State<QuestionRow> createState() => _QuestionRowState();
}

class _QuestionRowState extends State<QuestionRow> {
  Map<String, QuestionDraft> _drafts = const <String, QuestionDraft>{};
  int _index = 0;
  String? _error;

  /// Whether the flow has dispatched its answer. The sheet closes on it: the
  /// request it was opened for is settled, so leaving the sheet up would leave
  /// the reader on a card the session no longer has.
  bool _settled = false;

  @override
  void didUpdateWidget(covariant QuestionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Compose remembered drafts keyed by request id.
    if (oldWidget.request.requestId != widget.request.requestId) {
      _drafts = const <String, QuestionDraft>{};
      _index = 0;
      _error = null;
      _settled = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final review = _planReviewOf(request.questions);
    if (review != null) {
      return _PlanReviewRow(
        requestId: request.requestId,
        review: review,
        onAction: widget.onAction,
      );
    }
    if (request.questions.isEmpty) return const SizedBox.shrink();
    final question =
        request.questions[_index.clamp(0, request.questions.length - 1)];
    // The card's line: the asker's own question, with the detail's first line
    // as its one-line summary. The answer seats do not live on this row — they
    // belong to the decision surface ([_openSheet]), the way the reference
    // moves a card's content out of the transcript and into its own pane.
    final detail = question.detail;
    return CardDetailRow(
      icon: Icons.help_outline,
      title: question.question,
      summary: detail == null
          ? null
          : extractMarkdownPlainText(
              detail,
              mode: MarkdownPlainTextMode.firstLine,
            ),
      openLabel: AppLocalizations.of(context)!.answer,
      onOpen: _openSheet,
    );
  }

  /// Opens the decision surface: the question's detail scrolls above, its
  /// options sit at the bottom of the sheet, and every draft stays on this row
  /// — a dismiss returns the reader to the same card with the answer in
  /// progress intact.
  void _openSheet() {
    final request = widget.request;
    unawaited(
      showCardDetailSheet<void>(
        context,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => _AskDecisionSheet(
            questions: request.questions,
            index: _index.clamp(0, request.questions.length - 1),
            drafts: _drafts,
            error: _error,
            onChoose: (id, option) => setSheetState(() => _choose(id, option)),
            onDraftChange: (id, draft) =>
                setSheetState(() => _drafts = {..._drafts, id: draft}),
            onBack: () => setSheetState(() {
              if (_index > 0) _index -= 1;
              _error = null;
            }),
            onNext: () => setSheetState(() {
              _continue();
              if (_settled) Navigator.of(sheetContext).pop();
            }),
            onSkip: () => setSheetState(() {
              _skip();
              if (_settled) Navigator.of(sheetContext).pop();
            }),
            onDismiss: () {
              Navigator.of(sheetContext).pop();
              widget.onAction(
                DismissQuestionAction(requestId: request.requestId),
              );
            },
          ),
        ),
      ),
    );
  }

  void _choose(String questionId, String option) {
    final question = widget.request.questions
        .where((item) => item.id == questionId)
        .firstOrNull;
    if (question == null) return;
    if (question.multiSelect) {
      final current = _drafts[questionId] ?? const QuestionDraft();
      final selected = current.selected.contains(option)
          ? current.selected.difference({option})
          : {...current.selected, option};
      setState(() {
        _drafts = {
          ..._drafts,
          questionId: QuestionDraft(
            selected: selected,
            customText: current.customText,
          ),
        };
      });
    } else {
      setState(() {
        _drafts = {
          ..._drafts,
          questionId: QuestionDraft(selected: {option}, customText: ''),
        };
        if (_index < widget.request.questions.length - 1) _index += 1;
      });
    }
  }

  void _continue() {
    final question = widget.request.questions[_index];
    final draft = _drafts[question.id] ?? const QuestionDraft();
    if (draft.selected.isEmpty && draft.customText.trim().isEmpty) {
      setState(
        () => _error = AppLocalizations.of(context)!.questionErrorUnanswered,
      );
      return;
    }
    if (_index < widget.request.questions.length - 1) {
      setState(() {
        _index += 1;
        _error = null;
      });
      return;
    }
    _submit();
  }

  void _skip() {
    final question = widget.request.questions[_index];
    setState(() {
      _drafts = {
        ..._drafts,
        question.id: const QuestionDraft(
          selected: <String>{},
          customText: '',
          skipped: true,
        ),
      };
      if (_index < widget.request.questions.length - 1) _index += 1;
    });
    if (_index >= widget.request.questions.length - 1) {
      _submit();
    }
  }

  void _submit() {
    final request = widget.request;
    final missing = request.questions.indexWhere(
      (question) =>
          !_completed(question, _drafts[question.id] ?? const QuestionDraft()),
    );
    if (missing >= 0) {
      setState(() {
        _index = missing;
        _error = AppLocalizations.of(context)!.questionErrorIncomplete;
      });
      return;
    }
    widget.onAction(
      AnswerQuestionAction(
        requestId: request.requestId,
        answers: [
          for (final question in request.questions)
            _answerFor(question, _drafts[question.id]),
        ],
      ),
    );
    // The request is answered: the decision surface closes with it.
    _settled = true;
  }

  bool _completed(QuestionItem question, QuestionDraft draft) =>
      draft.skipped ||
      draft.selected.isNotEmpty ||
      draft.customText.trim().isNotEmpty;

  QuestionAnswer _answerFor(QuestionItem question, QuestionDraft? draftIn) {
    final draft = draftIn ?? const QuestionDraft();
    if (draft.skipped) {
      return QuestionAnswer(questionId: question.id);
    }
    final custom = draft.customText.trim();
    final useCustomOnly = custom.isNotEmpty && !question.multiSelect;
    return QuestionAnswer(
      questionId: question.id,
      selectedOptions: useCustomOnly
          ? const <String>[]
          : draft.selected.toList(),
      customText: custom.isEmpty ? null : custom,
    );
  }
}

/// Narrow a question request to a renderable plan review, or return null to
/// leave it to the generic question flow. Mirrors the web `planReviewOf`: the
/// decision card answers the whole request with one of the asker's own option
/// labels, so it claims a request only when a single question declares the
/// intent, carries the plan as its detail, and stays a binary single choice
/// (at most one option besides approve, never multi-select).
({String id, String question, String plan, String approve, String? decline})?
_planReviewOf(List<QuestionItem> questions) {
  if (questions.length != 1) return null;
  final question = questions.single;
  final intent = question.intent;
  if (intent?.kind != 'plan-review' || question.detail == null) return null;
  if (question.multiSelect) return null;
  if (question.options.length > 2) return null;
  final approve = intent!.approve;
  if (approve == null || !question.options.contains(approve)) return null;
  final decline = question.options
      .where((option) => option != approve)
      .firstOrNull;
  return (
    id: question.id,
    question: question.question,
    plan: question.detail!,
    approve: approve,
    decline: decline,
  );
}

/// Split the conventional recommendation suffix off a display label without
/// changing the answer value (the label the user picks stays the full wire
/// string). Mirrors the web `parseRecommendedLabel`.
({String label, bool recommended}) _parseRecommendedLabel(String label) {
  final suffix = RegExp(
    r'\s*(?:\((?:recommended|推荐)\)|（(?:recommended|推荐)）)\s*$',
    caseSensitive: false,
  );
  if (suffix.hasMatch(label)) {
    return (label: label.replaceAll(suffix, ''), recommended: true);
  }
  return (label: label, recommended: false);
}

/// The ask card's decision surface — the web `QuestionComposer` port, hosted
/// in a large sheet instead of in the composer seat.
///
/// The card that opens it is one line (`CardDetailRow`); this is the surface
/// the reference gives the question's own pane. The question's detail scrolls
/// in the upper half and every answer seat sits at the bottom of the sheet —
/// the option rows, the custom-answer row or the optionless textarea, and the
/// pager with skip / next / submit — so the thumb never has to travel past a
/// long detail to decide.
class _AskDecisionSheet extends StatelessWidget {
  const _AskDecisionSheet({
    required this.questions,
    required this.index,
    required this.drafts,
    required this.error,
    required this.onChoose,
    required this.onDraftChange,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
    required this.onDismiss,
  });

  final List<QuestionItem> questions;
  final int index;
  final Map<String, QuestionDraft> drafts;
  final String? error;
  final void Function(String questionId, String option) onChoose;
  final void Function(String questionId, QuestionDraft draft) onDraftChange;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final question = questions[index];
    final draft = drafts[question.id] ?? const QuestionDraft();
    final hasOptions = question.options.isNotEmpty;
    final answered =
        draft.selected.isNotEmpty || draft.customText.trim().isNotEmpty;
    final isLast = index == questions.length - 1;
    final detail = question.detail;
    // The sheet's own panel is the surface (see [showCardDetailSheet]); this
    // builds the content on it, not a card of its own.
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _QuestionCardHeader(question: question, onDismiss: onDismiss),
          // The reading half: the detail and the option rows travel together,
          // because an option is chosen against the text above it.
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (detail != null) MarkdownText(text: detail),
                  if (hasOptions)
                    if (question.multiSelect)
                      for (final option in question.options)
                        _QuestionOptionTile(
                          question: question,
                          option: option,
                          selected: draft.selected.contains(option),
                          onChanged: () => onChoose(question.id, option),
                        )
                    else
                      RadioGroup<String>(
                        groupValue: draft.selected.isEmpty
                            ? null
                            : draft.selected.first,
                        onChanged: (value) {
                          if (value != null) onChoose(question.id, value);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            for (final option in question.options)
                              _QuestionOptionTile(
                                question: question,
                                option: option,
                                selected: draft.selected.contains(option),
                                onChanged: () => onChoose(question.id, option),
                              ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
          // The answering half, pinned at the bottom of the sheet where the
          // thumb already is: the free-form seat when the asker offered no
          // options, the pager and Submit either way. The sheet's height is a
          // share of the screen, so these never scroll out of reach.
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
            child: hasOptions
                ? _CustomAnswerRow(
                    question: question,
                    draft: draft,
                    onDraftChange: (d) => onDraftChange(question.id, d),
                  )
                : _CustomAnswerField(
                    question: question,
                    draft: draft,
                    onDraftChange: (d) => onDraftChange(question.id, d),
                  ),
          ),
          _QuestionCardFooter(
            total: questions.length,
            index: index,
            error: error,
            answered: answered,
            isLast: isLast,
            onBack: onBack,
            onNext: onNext,
            onSkip: onSkip,
          ),
        ],
      ),
    );
  }
}

class _QuestionCardHeader extends StatelessWidget {
  const _QuestionCardHeader({required this.question, required this.onDismiss});

  final QuestionItem question;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (question.header case final String header)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      header,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                        height: 16 / 11,
                      ),
                    ),
                  ),
                Text(
                  question.question,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    height: 22 / 16,
                  ),
                ),
              ],
            ),
          ),
          // No fold seat: the card itself is the fold now — dismissing the
          // sheet is what returns the reader to the one-line card.
          _RoundIconButton(
            tooltip: AppLocalizations.of(context)!.questionCancel,
            icon: Icons.close,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// One selectable option row (web `.option`): a native indicator seat
/// (RadioListTile under the card's RadioGroup for single-select,
/// CheckboxListTile for multi-select), the display label with the
/// recommended badge, and the asker's description. The native
/// ListTile/Radio/Checkbox themes carry the row fill and indicator.
class _QuestionOptionTile extends StatelessWidget {
  const _QuestionOptionTile({
    required this.question,
    required this.option,
    required this.selected,
    required this.onChanged,
  });

  final QuestionItem question;
  final String option;
  final bool selected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final display = _parseRecommendedLabel(option);
    Widget? subtitle;
    if (question.optionDescriptions[option] case final String description) {
      subtitle = Text(
        description,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 14,
          height: 24 / 14,
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    final title = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 2,
      children: [
        Text(
          display.label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            height: 24 / 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (display.recommended)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(kShapeChip),
            ),
            child: Text(
              AppLocalizations.of(context)!.questionRecommended,
              style: TextStyle(
                // The M3 role pairing, not two pale containers: the web badge
                // paints accent-fill with dark ink, and primaryContainer text
                // on secondaryContainer measured 1.00:1 — invisible.
                color: scheme.onPrimaryContainer,
                fontSize: 11,
                height: 18 / 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(kShapeChip),
    );
    // The option rows need their own Material ancestor: the question card
    // behind them is a decorated container, and ListTile paints its
    // background and ink splashes on the nearest Material — one must sit
    // between the tile and the card decoration.
    return Material(
      color: Colors.transparent,
      child: question.multiSelect
          ? CheckboxListTile(
              value: selected,
              onChanged: (_) => onChanged(),
              controlAffinity: ListTileControlAffinity.leading,
              shape: shape,
              title: title,
              subtitle: subtitle,
            )
          : RadioListTile<String>(
              // The ancestor RadioGroup owns the group value and change
              // routing; the tile carries only its own value.
              value: option,
              controlAffinity: ListTileControlAffinity.leading,
              shape: shape,
              title: title,
              subtitle: subtitle,
            ),
    );
  }
}

/// Multi-select checkbox (web `.checkbox`): a 14×14 radius-4 box centered in
/// the 20px indicator seat, filled with the label-primary color and a
/// foreground check when checked.
class _QuestionCheckbox extends StatelessWidget {
  const _QuestionCheckbox({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 20,
      height: 20,
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: checked ? scheme.onSurface : Colors.transparent,
            border: Border.all(
              color: checked ? scheme.onSurface : scheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(kShapeChip),
          ),
          child: checked
              ? Icon(Icons.check, size: 12, color: scheme.onSurface)
              : null,
        ),
      ),
    );
  }
}

/// Single-select number chip (web `.number`): a 20×20 radius-6 overlay chip
/// holding the option index or an edit glyph.
class _QuestionNumberChip extends StatelessWidget {
  const _QuestionNumberChip({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kShapeChip),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// Inline custom-answer row (web `.customRow`): an option-shaped row whose
/// copy is a borderless text input; a typed draft lifts it to the selected
/// look, and the leading indicator mirrors the option row (checkbox for
/// multi-select, edit chip for single-select).
class _CustomAnswerRow extends StatefulWidget {
  const _CustomAnswerRow({
    required this.question,
    required this.draft,
    required this.onDraftChange,
  });

  final QuestionItem question;
  final QuestionDraft draft;
  final void Function(QuestionDraft) onDraftChange;

  @override
  State<_CustomAnswerRow> createState() => _CustomAnswerRowState();
}

class _CustomAnswerRowState extends State<_CustomAnswerRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.draft.customText)
      ..selection = TextSelection.collapsed(
        offset: widget.draft.customText.length,
      );
  }

  @override
  void didUpdateWidget(covariant _CustomAnswerRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.draft.customText != _controller.text) {
      _controller.text = widget.draft.customText;
      _controller.selection = TextSelection.collapsed(
        offset: widget.draft.customText.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = widget.draft.customText.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      decoration: BoxDecoration(
        color: active ? scheme.surfaceContainerHigh : Colors.transparent,
        border: Border.all(
          color: active ? scheme.outlineVariant : Colors.transparent,
        ),
        borderRadius: BorderRadius.circular(kShapeCard),
      ),
      child: Row(
        children: [
          if (widget.question.multiSelect)
            _QuestionCheckbox(checked: active)
          else
            _QuestionNumberChip(
              child: Icon(
                Icons.edit_outlined,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: AppLocalizations.of(context)!.typeYourAnswerHint,
                hintStyle: TextStyle(
                  color: scheme.outline,
                  fontSize: 14,
                  height: 24 / 14,
                ),
              ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
                height: 24 / 14,
              ),
              onChanged: (text) => widget.onDraftChange(
                QuestionDraft(
                  selected: widget.question.multiSelect
                      ? widget.draft.selected
                      : const <String>{},
                  customText: text,
                ),
              ),
              onSubmitted: (_) {},
            ),
          ),
        ],
      ),
    );
  }
}

/// Optionless question: the free-form answer is the whole body (web
/// `.customTextarea`).
class _CustomAnswerField extends StatefulWidget {
  const _CustomAnswerField({
    required this.question,
    required this.draft,
    required this.onDraftChange,
  });

  final QuestionItem question;
  final QuestionDraft draft;
  final void Function(QuestionDraft) onDraftChange;

  @override
  State<_CustomAnswerField> createState() => _CustomAnswerFieldState();
}

class _CustomAnswerFieldState extends State<_CustomAnswerField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.draft.customText)
      ..selection = TextSelection.collapsed(
        offset: widget.draft.customText.length,
      );
  }

  @override
  void didUpdateWidget(covariant _CustomAnswerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.draft.customText != _controller.text) {
      _controller.text = widget.draft.customText;
      _controller.selection = TextSelection.collapsed(
        offset: widget.draft.customText.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _controller,
      minLines: 2,
      maxLines: 4,
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context)!.typeYourAnswerHint,
        hintStyle: TextStyle(
          color: scheme.outline,
          fontSize: 14,
          height: 24 / 14,
        ),
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kShapeChip),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kShapeChip),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
      ),
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 14,
        height: 24 / 14,
      ),
      onChanged: (text) => widget.onDraftChange(
        QuestionDraft(selected: const <String>{}, customText: text),
      ),
    );
  }
}

/// Footer (web `.footer`): pager + validation feedback on one line, skip and
/// next/submit on the next.
class _QuestionCardFooter extends StatelessWidget {
  const _QuestionCardFooter({
    required this.total,
    required this.index,
    required this.error,
    required this.answered,
    required this.isLast,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
  });

  final int total;
  final int index;
  final String? error;
  final bool answered;
  final bool isLast;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _RoundIconButton(
                tooltip: l10n.questionPrev,
                icon: Icons.chevron_left,
                enabled: index > 0,
                onPressed: onBack,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '${index + 1} / $total',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _RoundIconButton(
                tooltip: l10n.questionNext,
                icon: Icons.chevron_right,
                enabled: index < total - 1,
                onPressed: onNext,
              ),
              Expanded(
                child: Text(
                  error ?? '',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 11,
                    height: 16 / 11,
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(onPressed: onSkip, child: Text(l10n.skip)),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: answered ? onNext : null,
                child: Text(
                  isLast ? l10n.questionSubmit : l10n.questionSubmitNext,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One 24×24 round icon button (web `.iconButton`): tertiary glyph on the
/// interactive hover fill; 36px+ touch target through padding. `DshTappable`
/// owns the tap and the press feedback — the hover fill is the whole visual
/// state, so the seat carries no ink.
class _RoundIconButton extends StatefulWidget {
  const _RoundIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  State<_RoundIconButton> createState() => _RoundIconButtonState();
}

class _RoundIconButtonState extends State<_RoundIconButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Material(
          color: _hovering && widget.enabled
              ? scheme.surfaceContainerHigh
              : Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: DshTappable(
            enabled: widget.enabled,
            enableHaptic: true,
            onTap: widget.enabled ? widget.onPressed : null,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Center(
                child: Icon(
                  widget.icon,
                  size: 18,
                  color: widget.enabled
                      ? scheme.onSurfaceVariant
                      : scheme.outline,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Plan-review decision row (the web `PlanReviewPanel` port, folded to its
/// own summary).
///
/// The reference keeps the document out of the card: the panel's body is the
/// plan's first line as a title and its first paragraph as a description
/// (`PlanReviewPanel.tsx:52-58`), and a `preview.full` link
/// (`PlanCard.tsx:81-82`) opens the whole document in the right sidebar. A
/// phone has no sidebar, so this row is those two lines — title, summary — with
/// the primary action still on it, and tapping it pushes the document as a
/// full-screen route ([showPlanDetail]) whose bottom bar pins the whole
/// decision. Opening the document answers nothing; only the actions do.
class _PlanReviewRow extends StatelessWidget {
  const _PlanReviewRow({
    required this.requestId,
    required this.review,
    required this.onAction,
  });

  final String requestId;
  final ({
    String id,
    String question,
    String plan,
    String approve,
    String? decline,
  })
  review;
  final void Function(ChatAction) onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final review = this.review;
    final summary = planSummary(review.plan);
    final args = PlanDetailArgs(
      requestId: requestId,
      questionId: review.id,
      title: summary.title.isEmpty ? l10n.planReview : summary.title,
      description: summary.description,
      plan: review.plan,
    );
    return CardDetailRow(
      icon: Icons.checklist_outlined,
      title: l10n.planReviewRequestedTitle,
      summary: args.title,
      trailing: FilledButton(
        onPressed: () => onAction(
          AnswerQuestionAction(
            requestId: requestId,
            answers: [
              QuestionAnswer(
                questionId: review.id,
                selectedOptions: [review.approve],
              ),
            ],
          ),
        ),
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(l10n.planApprove),
      ),
      onOpen: () => showPlanDetail(
        context,
        args: args,
        approveLabel: review.approve,
        declineLabel: review.decline,
        onAction: onAction,
      ),
    );
  }
}

final class QuestionDraft {
  const QuestionDraft({
    this.selected = const <String>{},
    this.customText = '',
    this.skipped = false,
  });

  final Set<String> selected;
  final String customText;
  final bool skipped;

  QuestionDraft copyWith({Set<String>? selected, String? customText}) {
    return QuestionDraft(
      selected: selected ?? this.selected,
      customText: customText ?? this.customText,
      skipped: skipped,
    );
  }
}

/// Dock width under which the composer's access chip drops its label,
/// keeping the mode glyph and the chevron (web `PermissionSelect.module.css`
/// `@container (max-width: 460px)`: "the 460px cut is the point where the row
/// (attach + modes + model + send) starts squeezing labels").
const double _kComposerLabelCut = 460;

/// Width at which the session sidebar may split off the chat pane, and the
/// height it must also clear.
///
/// 720dp is the width a phone in landscape reaches, and a phone in landscape
/// is ~390dp tall: splitting there spends 320dp of the width on a sidebar and
/// leaves the transcript a ~100dp slit. Both axes have to clear, so the split
/// arrives on a tablet and never on a rotated phone.
const double kTwoPaneMinWidth = 720;
const double kTwoPaneMinHeight = 500;

/// Reading measure the transcript column is capped at on a wide surface.
///
/// 760dp holds roughly 70-90 characters of the body face, the range a
/// paragraph stays readable in; a tablet pane wider than this gets margins
/// instead of longer lines. Below it the cap does nothing, so a phone lays
/// out exactly as it did.
const double kReadingMeasure = 760;

/// Dock widths under which the action row splits into two lines instead of
/// squeezing. One line has to cover the attach seat, the mic and the compact
/// access chip on the left (136dp) and the model seat, the meter and the
/// primary action on the right (136dp), plus the queue-send seat while a
/// draft waits on a running turn (186dp): 272dp idle, 322dp queued. The cuts
/// carry 8dp of slack over those measurements, and the dock's widget tests
/// hold them against the seats themselves. Below a cut the row wraps rather
/// than shrinking a seat below its M3 footprint (web `InputBar.module.css`
/// `.row { flex-wrap: wrap }`: "the trailing group moves to its own line
/// instead of the left group shrinking").
const double _kComposerRowWidth = 280;
const double _kComposerQueuedRowWidth = 330;

/// One attached file in the composer strip: its name, size, and Host upload
/// state.
///
/// The unary upload reports no byte progress, so the in-flight state is the
/// indeterminate bar; a failure replaces it with the Host's reason, which is
/// the fact the reader needs before deciding to remove the row or send
/// without it. The remove seat is always present — a failed attachment must
/// be able to leave.
class PendingFileChip extends StatelessWidget {
  const PendingFileChip({
    required this.file,
    required this.onRemove,
    super.key,
  });

  final PendingFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failed = file.status == PendingFileStatus.failed;
    final ready = file.status == PendingFileStatus.ready;
    final size = _formatFileSize(file.byteSize);
    final stateLabel = switch (file.status) {
      PendingFileStatus.uploading => l10n.fileUploading(size),
      PendingFileStatus.ready => l10n.fileUploaded(size),
      PendingFileStatus.failed => l10n.fileUploadFailed,
    };
    final foreground = failed ? scheme.onErrorContainer : scheme.onSurface;
    final secondary = failed
        ? scheme.onErrorContainer
        : scheme.onSurfaceVariant;
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: failed ? scheme.errorContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(kShapeChip),
        border: Border.all(
          color: failed ? scheme.error : scheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ready ? Icons.description_outlined : Icons.upload_file_outlined,
            size: 16,
            color: secondary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  stateLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: secondary),
                ),
                if (file.status == PendingFileStatus.uploading) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      borderRadius: BorderRadius.circular(kShapePill),
                    ),
                  ),
                ],
                if (failed)
                  if (file.failureReason case final reason?) ...[
                    const SizedBox(height: 2),
                    Text(
                      reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary,
                      ),
                    ),
                  ],
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 16),
            tooltip: l10n.removeFile(file.name),
          ),
        ],
      ),
    );
  }
}

/// One file size as the strip states it: whole bytes under a kibibyte, then
/// one decimal on the binary scale.
String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(1)} KB';
  return '${(kib / 1024).toStringAsFixed(1)} MB';
}

class ComposerBar extends ConsumerStatefulWidget {
  const ComposerBar({
    required this.enabled,
    required this.isSending,
    required this.running,
    required this.pendingImages,
    required this.imageLimits,
    required this.pendingFiles,
    required this.skills,
    required this.onAction,
    required this.onSend,
    super.key,
    this.commands,
    this.onPickFile,
    this.fileReferences,
    this.onStop,
    this.plan,
    this.models,
    this.onSelectModel,
    this.onRefreshModels,
    this.modelPrefs,
    this.contextPressure,
    this.contextBreakdown,
    this.sessionId,
    this.sessionState,
    this.permissions,
    this.sandboxMode,
    this.loadPermissionCatalog,
  });

  final bool enabled;
  final bool isSending;
  final bool running;
  final List<PendingImage> pendingImages;
  final ImageLimits imageLimits;

  /// Composer files attached for the next send, each with its Host upload
  /// state ([PendingFile.status]); a failed row keeps its reason.
  final List<PendingFile> pendingFiles;

  /// The document pick the attach-file affordance performs; null uses the
  /// platform's system picker ([pickDocument]). Injected so widget tests
  /// drive the outcome without a platform channel.
  final DocumentPicker? onPickFile;
  final List<SkillEntry> skills;
  final void Function(ChatAction) onAction;

  /// The selected session's live host-command roster (`commands/list`);
  /// null keeps the static built-ins standing in (see [command_roster]).
  final List<CommandDescriptor>? commands;

  /// The selected session's last resolved `@` mention query and its
  /// candidates from both families — paths (`fileReferences/list`) and
  /// sessions (`sessionReferenceResolver/candidates`); null while no token is
  /// open. The composer renders only the holder whose query equals the live
  /// token (see [FileReferenceCandidates]).
  final FileReferencePickerState? fileReferences;

  /// Submit [text] and resolve with the host's acceptance: the composer
  /// keeps the draft (and its persisted value) until this future settles
  /// true, and never clears on false.
  final Future<bool> Function(String text) onSend;
  final VoidCallback? onStop;

  /// The session whose draft this composer edits; drives draft
  /// persistence alongside [sessionState].
  final String? sessionId;

  /// Repository seam the access-mode seat reads its preset list through;
  /// null leaves the seat's sheet stating that the modes could not be read.
  final PermissionCatalogLoader? loadPermissionCatalog;

  /// Draft persistence for [sessionId]; null keeps the draft in memory
  /// only.
  final ChatSessionLocalState? sessionState;

  /// Permission-preset projection (web conversation.input.access);
  /// null hides the access chip.
  final PermissionSelect? permissions;

  /// The selected session's decoded sandbox-mode fact; null means no
  /// `sandbox/mode` event has folded, and the composer states that rather
  /// than showing a mode the host never reported.
  final SandboxModeFact? sandboxMode;

  /// Plan collaboration state (web input.plan): while the target is plan
  /// mode the placeholder swaps and the warn pill rides the tools row.
  final PlanState? plan;

  /// Composer model seat (web conversation.input.model): the ModelSelect
  /// pill + selection dispatch.
  final SessionModels? models;
  final void Function(ModelSelection selection)? onSelectModel;
  final VoidCallback? onRefreshModels;

  /// Remembered model-seat preferences: the effort the reader last chose
  /// for a route prefills that model's pick; null leaves each model on
  /// its own default.
  final ModelSeatPreferences? modelPrefs;
  final ContextPressure? contextPressure;

  final ContextBreakdown? contextBreakdown;

  @override
  ConsumerState<ComposerBar> createState() => _ComposerBarState();
}

class _ComposerBarState extends ConsumerState<ComposerBar> {
  final TextEditingController _draftController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _preRecordingDraft = '';

  /// Whether the dock's first band is the hold-to-talk bar rather than the
  /// draft field. Local to the composer — a way of using this control, not a
  /// session fact — and it survives a session switch the way the reader's
  /// keyboard preference does.
  bool _voiceMode = false;

  /// Counts reader keystrokes on the field (the [TextField] onChanged
  /// path; programmatic writes never touch it), so an in-flight draft
  /// read can tell "untouched" from "the reader is already typing here"
  /// — see [_restoreDraft].
  int _draftEdits = 0;

  /// The `@` query this composer last asked the controller for; null while
  /// no token is live. One dispatch per distinct query: the controller
  /// debounces and drops superseded answers itself.
  String? _fileReferenceQuery;

  @override
  void initState() {
    super.initState();
    _restoreDraft();
  }

  @override
  void didUpdateWidget(covariant ComposerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Drafts are session-scoped: switching sessions swaps the draft for
    // the target session's saved one (the leaving draft was persisted on
    // change).
    if (oldWidget.sessionId != widget.sessionId ||
        oldWidget.sessionState != widget.sessionState) {
      _restoreDraft();
    }
  }

  @override
  void dispose() {
    _draftController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Load the selected session's saved draft into the field; an absent
  /// draft clears it. The read is async, so the answer can land after the
  /// reader moved on: a later session switch or any keystroke (the edit
  /// counter) voids the restore instead of clobbering live input.
  void _restoreDraft() {
    final sessionState = widget.sessionState;
    final sessionId = widget.sessionId;
    if (sessionState == null || sessionId == null) {
      _draftController.clear();
      _syncFileReferences();
      setState(() {});
      return;
    }
    final editsAtStart = _draftEdits;
    unawaited(
      sessionState.readDraft().then((draft) {
        if (!mounted) return;
        if (widget.sessionId != sessionId || _draftEdits != editsAtStart) {
          return;
        }
        _draftEdits++;
        _draftController
          ..text = draft ?? ''
          ..selection = TextSelection.collapsed(
            offset: _draftController.text.length,
          );
        _syncFileReferences();
        setState(() {});
      }),
    );
  }

  void _handlePlusCommand(String name) {
    if (hostCommandIsBare('/$name', _commandRoster)) {
      widget.onAction(SendPrompt('/$name'));
      return;
    }
    _applyCommandToDraft(name);
  }

  void _applyCommandToDraft(String name) {
    final current = _draftController.text;
    final String newDraft;
    if (current.startsWith('/')) {
      final spaceIdx = current.indexOf(' ');
      final remainder = spaceIdx != -1 ? current.substring(spaceIdx + 1) : '';
      newDraft = remainder.isEmpty ? '/$name ' : '/$name $remainder';
    } else {
      final trimmed = current.trim();
      newDraft = trimmed.isEmpty ? '/$name ' : '/$name $trimmed';
    }
    _draftController.text = newDraft;
    _draftController.selection = TextSelection.collapsed(
      offset: newDraft.length,
    );
    _draftEdits++;
    _persistDraft();
    _syncFileReferences();
    _focusNode.requestFocus();
    setState(() {});
  }

  void _persistDraft() {
    unawaited(widget.sessionState?.writeDraft(_draftController.text));
  }

  /// The caret the draft's `@` token is read at: the field's own selection
  /// when it is valid, else the text end (a programmatic write can leave the
  /// selection stale for one frame).
  int _draftCaret() {
    final text = _draftController.text;
    final offset = _draftController.selection.isValid
        ? _draftController.selection.baseOffset
        : -1;
    if (offset >= 0 && offset <= text.length) return offset;
    return text.length;
  }

  /// Tell the controller which `@` token the draft now holds (null closes the
  /// picker). Every path that writes the draft calls this, because a
  /// programmatic write never fires the field's `onChanged`.
  void _syncFileReferences() {
    final token = activeFileReferenceToken(
      _draftController.text,
      _draftCaret(),
    );
    final query = token?.query;
    if (query == _fileReferenceQuery) return;
    _fileReferenceQuery = query;
    widget.onAction(UpdateFileReferences(query));
  }

  /// Insert one picked candidate over the live token: a file completes the
  /// mention, a directory leaves it open on the level just entered.
  void _applyFileReference(FileReferenceCandidate candidate) {
    final draft = _draftController.text;
    final cursor = _draftCaret();
    final token = activeFileReferenceToken(draft, cursor);
    if (token == null) return;
    _commitReferencePick(
      applyFileReferencePick(
        draft: draft,
        cursor: cursor,
        token: token,
        candidate: candidate,
      ),
    );
  }

  /// Insert one picked session over the live token: the host's canonical
  /// `@[label](dsh-session:…)` mention replaces the `@` token — the exact
  /// text the host parses back out of the prompt
  /// (`reference/deepseek-harness/packages/context/session-reference/src/
  /// uri.ts` `formatSessionReferenceMention`).
  void _applySessionReference(SessionReferenceCandidate candidate) {
    final draft = _draftController.text;
    final cursor = _draftCaret();
    final token = activeFileReferenceToken(draft, cursor);
    if (token == null) return;
    _commitReferencePick(
      applySessionReferencePick(
        draft: draft,
        cursor: cursor,
        token: token,
        candidate: candidate,
      ),
    );
  }

  /// Write one accepted `@` candidate into the draft and re-sync the token,
  /// so the menu follows the text it was inserted into.
  void _commitReferencePick(({String text, int caret})? applied) {
    if (applied == null) return;
    _draftController
      ..text = applied.text
      ..selection = TextSelection.collapsed(offset: applied.caret);
    _draftEdits++;
    _persistDraft();
    _focusNode.requestFocus();
    _syncFileReferences();
    setState(() {});
  }

  /// Swaps the draft field for the hold-to-talk bar, and back.
  ///
  /// Leaving text mode drops the keyboard, which would otherwise stand over a
  /// bar it cannot type into; returning opens the field, because a mode the
  /// reader asked for should be ready to use.
  void _toggleVoiceMode() {
    setState(() => _voiceMode = !_voiceMode);
    if (_voiceMode) {
      _focusNode.unfocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _pickImages() async {
    final l10n = AppLocalizations.of(context)!;
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty) return;
    final loaded = <PendingImage>[];
    String? failure;
    for (final file in picked) {
      final name = file.path.split('/').last;
      try {
        final mediaType = file.mimeType ?? guessImageMediaType(file.path);
        if (mediaType == null) {
          failure = l10n.unknownImageType(name);
          continue;
        }
        final bytes = await file.readAsBytes();
        loaded.add(
          PendingImage(
            id: file.path,
            mediaType: mediaType,
            base64Data: base64Encode(bytes),
            name: name,
            byteSize: bytes.length,
          ),
        );
      } catch (error) {
        failure = error.toString();
      }
    }
    if (loaded.isNotEmpty) widget.onAction(ImagesLoaded(loaded));
    if (failure != null) widget.onAction(ImagePickError(failure));
  }

  /// Opens the system document picker and hands the chosen file to the
  /// controller for upload.
  ///
  /// The pick carries the phone's upload cap so an oversized document fails
  /// before its bytes are read. A cancelled pick does nothing; a pick failure
  /// lands on the shared error strip, while an upload failure stays on the
  /// attachment's own row with the Host's reason.
  Future<void> _pickFile() async {
    final l10n = AppLocalizations.of(context)!;
    final picker = widget.onPickFile ?? pickDocument;
    try {
      final picked = await picker(maxBytes: FileUploadLimits.maxFileBytes);
      if (picked == null || !mounted) return;
      widget.onAction(FilePicked(name: picked.name, bytes: picked.bytes));
    } on DocumentPickException catch (error) {
      if (!mounted) return;
      widget.onAction(
        FilePickError(
          error.code == 'too_large'
              ? l10n.fileTooLarge(
                  FileUploadLimits.maxFileBytes ~/ (1024 * 1024),
                )
              : error.message,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final attachAllowed =
        widget.enabled &&
        widget.pendingImages.length < widget.imageLimits.maxImagesPerMessage;
    // Files have no count limit on the Host; the composer admits one document
    // per pick and refuses while an earlier upload has not settled, so a
    // half-uploaded row cannot be buried under a newer one.
    final attachFileAllowed =
        widget.enabled &&
        !widget.pendingFiles.any(
          (file) => file.status == PendingFileStatus.uploading,
        );

    // Display roster: the host's live names with the localized static
    // descriptions wherever this client knows the name.
    final displayCommands = widget.commands == null
        ? hostCommands(l10n)
        : hostCommandsFor(l10n, widget.commands!);

    final voiceController = ref.watch(voiceInputControllerProvider);
    final voiceInputState =
        ref.watch(voiceInputUiStateProvider).value ?? voiceController.state;

    ref.listen(voiceInputUiStateProvider, (prev, next) {
      final text = next.value?.liveTranscription ?? '';
      final prevText = prev?.value?.liveTranscription ?? '';
      if (text.isNotEmpty && text != prevText) {
        _draftController.text = _preRecordingDraft.isEmpty
            ? text
            : '$_preRecordingDraft $text';
        _draftController.selection = TextSelection.collapsed(
          offset: _draftController.text.length,
        );
        _persistDraft();
        _syncFileReferences();
        setState(() {});
      }
      final error = next.value?.errorMessage;
      if (error != null && error != prev?.value?.errorMessage) {
        // A capture that dies mid-session is the one voice event the reader
        // may not be looking at, so it lands on the skin as well as the
        // screen — the same weight the dock uses for its own boundaries.
        unawaited(HapticFeedback.heavyImpact());
        if (error == 'PERMISSION_DENIED') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.voiceInputPermissionDenied)),
          );
        } else if (error == 'RECORD_START_FAILED') {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.voiceInputRecordFailed)));
        } else if (error == 'RECORD_SILENT_INPUT') {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.voiceInputSilentInput)));
        } else if (error == 'RECORD_INPUT_FAILED') {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.voiceInputInputFailed)));
        } else if (error == 'RUNTIME_NOT_INSTALLED') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.voiceInputRuntimeNotInstalled)),
          );
        } else if (error == 'MODEL_UNSUPPORTED') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.voiceInputModelUnsupported)),
          );
        } else if (error == 'ONLINE_NOT_CONFIGURED') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.voiceInputCloudNotConfigured)),
          );
        } else if (error == 'ONLINE_CONNECT_FAILED') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.voiceInputCloudConnectFailed)),
          );
        } else if (error == 'ONLINE_ASR_FAILED') {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.voiceInputCloudFailed)));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    });

    // Web InputBar parity: the draft owns the card's top band and every
    // control rides one action row under it (`InputBar.module.css` `.card`:
    // "textarea on top, action row below, primary action controls
    // bottom-right"). One shared row cannot hold both on a phone — the seats
    // alone are wider than a 360dp dock, so the field's `Expanded` collapsed
    // to zero width and the reader had nowhere to type. The bands are
    // independent: no seat count can squeeze the field again.
    return Padding(
      // 4dp of side clearance: the action row's seats need the width on a
      // 360dp phone (see [_kComposerRowWidth]).
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.pendingImages.isNotEmpty || widget.pendingFiles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SizedBox(
                width: double.infinity,
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final image in widget.pendingImages)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PendingImageThumbnail(image: image),
                            Text(
                              image.name ?? image.id.split('/').last,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  widget.onAction(RemovePendingImage(image.id)),
                              icon: const Icon(Icons.close, size: 16),
                              tooltip: l10n.removeImage(
                                image.name ?? l10n.attachmentName,
                              ),
                            ),
                          ],
                        ),
                      ),
                    for (final file in widget.pendingFiles)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: PendingFileChip(
                          file: file,
                          onRemove: () =>
                              widget.onAction(RemovePendingFile(file.id)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (_planTarget)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PlanChip(
                    plan: widget.plan,
                    locked: !widget.enabled,
                    onExit: () =>
                        widget.onAction(const SendPrompt('/plan off')),
                  ),
                ],
              ),
            ),
          SlashSkillCandidates(
            draft: _draftController.text,
            skills: widget.skills,
            commands: displayCommands,
            enabled: widget.enabled,
            onPick: _applyCommandToDraft,
          ),
          // The `@` mention menu. A live slash token owns the band above the
          // draft, so the two composer sources never stack.
          FileReferenceCandidates(
            token: activeFileReferenceToken(
              _draftController.text,
              _draftCaret(),
            ),
            picker: widget.fileReferences,
            enabled:
                widget.enabled &&
                !(_draftController.text.startsWith('/') &&
                    !_draftController.text.contains(' ')),
            onPick: _applyFileReference,
            onPickSession: _applySessionReference,
          ),
          // Band 1 — the draft, edge to edge, or the hold-to-talk bar that
          // stands in for it while the dock is in voice mode. Which one it is
          // is the mode seat's state, never a surprise: the band does not
          // change unless the reader changed it.
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
            child: _voiceMode
                ? VoiceHoldBar(
                    enabled: widget.enabled,
                    busy: voiceInputState.isWaitingOnEngine,
                    uiState: voiceInputState,
                    onStart: () {
                      _preRecordingDraft = _draftController.text;
                      unawaited(voiceController.startRecording());
                    },
                    onFinish: () => unawaited(voiceController.stopRecording()),
                    onCancel: () {
                      unawaited(voiceController.cancelRecording());
                      _draftController.text = _preRecordingDraft;
                      _draftController.selection = TextSelection.collapsed(
                        offset: _draftController.text.length,
                      );
                      _persistDraft();
                      _syncFileReferences();
                      setState(() {});
                    },
                    onOpenSettings: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (ctx) => const AsrModelsRoute(),
                        ),
                      );
                    },
                  )
                : TextField(
                    controller: _draftController,
                    focusNode: _focusNode,
                    enabled: widget.enabled,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    onChanged: (_) {
                      _draftEdits++;
                      _persistDraft();
                      _syncFileReferences();
                      setState(() {});
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      hintText: _planTarget
                          ? l10n.planPlaceholder
                          : l10n.messagePlaceholder,
                    ),
                  ),
          ),
          // Band 2 — the action row (web `.row`): attaches and the access
          // mode on the left, the model seat, context meter and the primary
          // action on the right, so the send thumb lands on the bottom-right
          // corner. The access chip is the row's only elastic seat: it takes
          // the slack and drops its label on a narrow dock. When even that
          // does not fit — a 320dp phone with a draft waiting on a running
          // turn — the trailing group moves to its own line rather than
          // shrinking a seat below its M3 footprint.
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 2),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // The queue-send seat only exists while a draft waits on a
                // running turn, and it is the difference between a row that
                // fits a phone and one that does not.
                final queueSeat =
                    widget.running &&
                    widget.enabled &&
                    !widget.isSending &&
                    _canSend();
                final rowWidth = queueSeat
                    ? _kComposerQueuedRowWidth
                    : _kComposerRowWidth;
                final tools = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The mode seat leads the row, where the field it swaps
                    // sits above it: the reader changes the mode on the control
                    // that names it, and the bar or field appears in place.
                    // Changing it mid-capture would unmount the very control
                    // holding the microphone, so a live session locks it.
                    _VoiceModeToggle(
                      enabled:
                          widget.enabled && !voiceInputState.isSessionActive,
                      voiceMode: _voiceMode,
                      onToggle: _toggleVoiceMode,
                    ),
                    _PlusButton(
                      enabled: widget.enabled,
                      onPickImages: attachAllowed ? _pickImages : null,
                      onPickFile: attachFileAllowed ? _pickFile : null,
                      skills: widget.skills,
                      commands: displayCommands,
                      onPickCommand: _handlePlusCommand,
                    ),
                    if (widget.permissions case final permissions?)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 135),
                        child: PermissionSelectChip(
                          value: permissions,
                          locked: !widget.enabled,
                          onAction: widget.onAction,
                          loadCatalog: widget.loadPermissionCatalog,
                          compact: constraints.maxWidth < _kComposerLabelCut,
                          // The session's real confinement level rides this
                          // seat's tooltip: a preset composes a sandbox mode
                          // with an approval policy, so the effective
                          // `sandbox/mode` fact can differ from the preset's
                          // own name and must be stated separately. A
                          // dedicated chip was rejected — a second chip does
                          // not fit a 320dp dock's action row, and a hidden
                          // seat cannot state an unreported mode.
                          tooltipDetail: widget.sessionId == null
                              ? null
                              : sandboxModeDetail(
                                  widget.sandboxMode,
                                  AppLocalizations.of(context)!,
                                ),
                        ),
                      ),
                  ],
                );
                final actions = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onSelectModel != null)
                      ModelSelect(
                        models: widget.models,
                        locked: !widget.enabled,
                        onSelect: widget.onSelectModel!,
                        onRefresh: widget.onRefreshModels ?? () {},
                        modelPrefs: widget.modelPrefs,
                      ),
                    const SizedBox(width: 2),
                    ContextRing(
                      pressure: widget.contextPressure,
                      breakdown: widget.contextBreakdown,
                    ),
                    const SizedBox(width: 2),
                    if (queueSeat) ...[
                      _PrimarySendButton(
                        running: false,
                        sending: false,
                        enabled: true,
                        onSend: _send,
                      ),
                      const SizedBox(width: 2),
                    ],
                    _PrimarySendButton(
                      running: widget.running,
                      sending: widget.isSending,
                      enabled: widget.enabled && _canSend(),
                      onStop: widget.onStop,
                      onSend: _send,
                    ),
                  ],
                );
                if (constraints.maxWidth < rowWidth) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      tools,
                      Align(alignment: Alignment.centerRight, child: actions),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: tools),
                    actions,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Web `planActive`: the folded host value, not client optimism.
  bool get _planTarget {
    final plan = widget.plan;
    if (plan == null) return false;
    return plan.pending ? !plan.active : plan.active;
  }

  /// The slash-decision facts this composer consults: the live roster once
  /// a pull settled, the static built-ins before that.
  List<HostCommand> get _commandRoster => widget.commands == null
      ? kHostCommandNames
      : hostCommandFacts(widget.commands!);

  bool _canSend() =>
      _draftController.text.trim().isNotEmpty ||
      widget.pendingImages.isNotEmpty ||
      widget.pendingFiles.any((file) => file.status == PendingFileStatus.ready);

  void _send([String? text]) {
    // Web envelope policy: an enter submission carrying attachments resolves
    // only through a command declaring attachment acceptance (the Host's one
    // flag governs images and staged files alike). Refuse before anything is
    // consumed — the draft and the attachments stay in place and nothing
    // executes.
    if (widget.pendingImages.isNotEmpty || widget.pendingFiles.isNotEmpty) {
      final refused = hostCommandImageRefusal(
        _draftController.text.trim(),
        _commandRoster,
      );
      if (refused != null) {
        final l10n = AppLocalizations.of(context)!;
        widget.onAction(
          CommandImageRefusal(
            // The row's copy names the kind the reader actually attached; the
            // Host's acceptance flag is the same for both kinds.
            widget.pendingImages.isEmpty
                ? l10n.commandFilesUnsupported(refused)
                : l10n.commandImagesUnsupported(refused),
          ),
        );
        return;
      }
    }
    // A file whose upload has not settled ready would be dropped from the
    // submission, and its receipt would never reach the Host. Say so and keep
    // the draft; the row itself already states a failure's reason.
    final unsettled = widget.pendingFiles
        .where((file) => file.status != PendingFileStatus.ready)
        .firstOrNull;
    if (unsettled != null) {
      widget.onAction(
        FilePickError(
          AppLocalizations.of(context)!.fileAttachmentNotReady(unsettled.name),
        ),
      );
      return;
    }
    final submitted = _draftController.text;
    unawaited(() async {
      final accepted = await widget.onSend(submitted);
      if (!mounted || !accepted) return;
      // A host acceptance consumes the draft: clear the field and persist
      // the cleared marker so a remount does not resurrect it. A failed
      // send never reaches this line — the reader's words stay in the
      // field, already persisted. If the field moved on while the send
      // was in flight (a detached command dispatch never holds the
      // composer), the reader's newer text wins and stays.
      if (_draftController.text != submitted) return;
      _draftController.clear();
      _persistDraft();
      _syncFileReferences();
      setState(() {});
    }());
  }
}

/// `/` composer source: while the draft is a single slash token, offer
/// the session's skill catalog filtered by prefix; picking lands the
/// literal `/name ` text, matching the Web plain-text-reference decision.
class SlashSkillCandidates extends StatelessWidget {
  const SlashSkillCandidates({
    required this.draft,
    required this.skills,
    required this.commands,
    required this.enabled,
    required this.onPick,
    super.key,
  });

  final String draft;
  final List<SkillEntry> skills;

  /// Display roster for the host commands the candidate list offers.
  final List<HostCommand> commands;
  final bool enabled;
  final void Function(String name) onPick;

  @override
  Widget build(BuildContext context) {
    if (!enabled || !draft.startsWith('/') || draft.contains(' ')) {
      return const SizedBox.shrink();
    }
    final query = draft.substring(1).toLowerCase();
    final matchingCommands = commands
        .where(
          (cmd) => query.isEmpty || cmd.name.toLowerCase().startsWith(query),
        )
        .take(5)
        .toList();
    final matchingSkills = skills
        .where(
          (skill) =>
              query.isEmpty || skill.name.toLowerCase().startsWith(query),
        )
        .take(5)
        .toList();
    if (matchingCommands.isEmpty && matchingSkills.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 220),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(kShapeMenuSheet),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(4),
          children: [
            for (final cmd in matchingCommands)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(kShapeChip),
                  onTap: () => onPick(cmd.name),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.terminal, size: 16, color: scheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          '/${cmd.name}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (cmd.hint != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            cmd.hint!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            cmd.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            for (final skill in matchingSkills)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(kShapeChip),
                  onTap: () => onPick(skill.name),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 16,
                          color: scheme.secondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '/${skill.name}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            skill.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Photo-picker fallback when the file reports no MIME type.
String? guessImageMediaType(String path) {
  switch (path.split('.').last.toLowerCase()) {
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    default:
      return null;
  }
}

/// Compact delivery-mode picker for narrow composer rows.
class PopupMenuEntryShim extends StatelessWidget {
  const PopupMenuEntryShim({
    required this.running,
    required this.enabled,
    required this.effectiveMode,
    required this.onModeChange,
    super.key,
  });

  final bool running;
  final bool enabled;
  final PromptMode effectiveMode;
  final void Function(PromptMode) onModeChange;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final isSteer = effectiveMode == PromptMode.steer;
    final label = isSteer ? l10n.steer : l10n.queue;
    return Tooltip(
      message: l10n.delivery,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(kShapeChip),
          onTap: enabled ? () => _open(context) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSteer ? Icons.bolt_outlined : Icons.schedule_send_outlined,
                  size: 14,
                  color: isSteer ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: isSteer ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: isSteer ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) {
    return showMenuSheet<void>(
      context,
      maxHeight: 240,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        final theme = Theme.of(sheetContext);
        final l10n = AppLocalizations.of(sheetContext)!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Text(l10n.delivery, style: theme.textTheme.titleSmall),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(kShapeChip),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onModeChange(PromptMode.queue);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.schedule_send_outlined,
                        size: 18,
                        color: effectiveMode == PromptMode.queue
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.queue,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: effectiveMode == PromptMode.queue
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (effectiveMode == PromptMode.queue)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: scheme.primary,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(kShapeChip),
                onTap: running
                    ? () {
                        Navigator.of(sheetContext).pop();
                        onModeChange(PromptMode.steer);
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.bolt_outlined,
                        size: 18,
                        color: !running
                            ? scheme.outline
                            : effectiveMode == PromptMode.steer
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.steer,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: !running ? scheme.outline : scheme.onSurface,
                            fontWeight: effectiveMode == PromptMode.steer
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (effectiveMode == PromptMode.steer)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: scheme.primary,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The composer's mode seat: the draft field on one side, hold-to-talk on the
/// other. It is the only place the mode changes, so the band above it is never
/// a surprise, and it carries the active mode in its own tone rather than in
/// chrome the reader has to hunt for.
class _VoiceModeToggle extends StatelessWidget {
  const _VoiceModeToggle({
    required this.enabled,
    required this.voiceMode,
    required this.onToggle,
  });

  final bool enabled;
  final bool voiceMode;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return DshTappable(
      enabled: enabled,
      enableHaptic: true,
      child: IconButton(
        tooltip: voiceMode ? l10n.voiceModeKeyboard : l10n.voiceInputTooltip,
        onPressed: enabled ? onToggle : null,
        icon: Icon(
          voiceMode ? Icons.keyboard_alt_outlined : Icons.mic_none,
          size: 22,
        ),
        // The seat is the 40px the tools row gives the attach button beside it,
        // so swapping the mic for the mode switch moves no other seat and the
        // row's measured width holds.
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(kVoiceSeatBox),
          foregroundColor: voiceMode ? scheme.primary : scheme.onSurfaceVariant,
          disabledForegroundColor: scheme.outline,
          hoverColor: scheme.surfaceContainerHigh,
          highlightColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          enableFeedback: false,
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}

/// The composer's ➕ — web form (InputBar `.add`): a 28px circle on the
/// selector fill with a 14px plus glyph. It opens the slash-command menu
/// as a menu-surface sheet seated above the dock, listing the host
/// command roster and the session's skills, with the mobile-only
/// Attach-images row at the tail (web relies on paste/drop, which mobile
/// keyboards cannot do). The web roster's search box is not ported:
/// mobile's roster is short and an autofocused query box raises the
/// keyboard onto the rows it filters.
class _PlusButton extends StatelessWidget {
  const _PlusButton({
    required this.enabled,
    required this.onPickImages,
    required this.onPickFile,
    required this.skills,
    required this.commands,
    required this.onPickCommand,
  });

  final bool enabled;
  final VoidCallback? onPickImages;
  final VoidCallback? onPickFile;
  final List<SkillEntry> skills;
  final List<HostCommand> commands;
  final void Function(String name) onPickCommand;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return DshTappable(
      enabled: enabled,
      enableHaptic: true,
      child: IconButton(
        tooltip: l10n.commandsTooltip,
        onPressed: enabled ? () => _open(context) : null,
        icon: const Icon(Icons.add, size: 22),
        // Native tool control: a standard 40px M3 icon button drawn straight
        // on the dock surface, with the interactive fill kept for hover and
        // the splash suppressed — the seat's press feedback is DshTappable's
        // scale and its one haptic, not a second ripple.
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          disabledForegroundColor: scheme.outline,
          hoverColor: scheme.surfaceContainerHigh,
          highlightColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          enableFeedback: false,
          shape: const CircleBorder(),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) {
    // The house menu sheet (PopupSelectView .card family), seated above
    // the composer dock so the roster never covers or competes with the
    // field the reader stands in.
    return showMenuSheet<void>(
      context,
      maxHeight: 440,
      builder: (sheetContext) => _CommandSheet(
        canPickImages: onPickImages != null,
        canPickFile: onPickFile != null,
        skills: skills,
        commands: commands,
        onPickCommand: (name) {
          Navigator.of(sheetContext).pop();
          onPickCommand(name);
        },
        onPickImagesNow: () {
          Navigator.of(sheetContext).pop();
          onPickImages?.call();
        },
        onPickFileNow: () {
          Navigator.of(sheetContext).pop();
          onPickFile?.call();
        },
      ),
    );
  }
}

/// One option row in the mobile selector form: 36px icon tile + bold label
/// + secondary detail subtitle, matching the workspace / speech-model
/// selector sheets.
class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(kShapeChip),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(kShapeChip),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: enabled ? scheme.onSurfaceVariant : scheme.outline,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        color: enabled
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    if (detail case final text?) ...[
                      const SizedBox(height: 2),
                      Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The roster is the real command set — host slash commands first (web
/// slash-menu sources), then the session's skills — with the
/// mobile-only Attach-images row demoted to the tail (web relies on
/// paste/drop). No search field: the roster is short, and the old
/// autofocused query box raised the keyboard straight onto the thumb's
/// own target list (the sheet-float decision note records the removal).
class _CommandSheet extends StatelessWidget {
  const _CommandSheet({
    required this.canPickImages,
    required this.canPickFile,
    required this.skills,
    required this.commands,
    required this.onPickCommand,
    required this.onPickImagesNow,
    required this.onPickFileNow,
  });

  final bool canPickImages;
  final bool canPickFile;
  final List<SkillEntry> skills;
  final List<HostCommand> commands;
  final void Function(String name) onPickCommand;
  final VoidCallback onPickImagesNow;
  final VoidCallback onPickFileNow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final int visibleCount = commands.length + skills.length + 2;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sheet header: primary glyph + title + count pill, the same
        // header family as the workspace and speech-model selectors.
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.terminal, size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    l10n.commandsTooltip,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              if (visibleCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(kShapeChip),
                  ),
                  child: Text(
                    '$visibleCount',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final command in commands)
                _CommandRow(
                  icon: Icons.terminal,
                  label: '/${command.name}',
                  detail: command.hint ?? command.description,
                  onTap: () => onPickCommand(command.name),
                ),
              for (final skill in skills)
                _CommandRow(
                  icon: Icons.auto_awesome,
                  label: '/${skill.name}',
                  detail: skill.description.isEmpty ? null : skill.description,
                  onTap: () => onPickCommand(skill.name),
                ),
              // Mobile-only tail rows: attachment intake (web uses paste/drop
              // and its own attach control) — demoted below the command
              // roster. Images and files are separate picks because the
              // gallery picker and the document picker are different system
              // surfaces.
              _CommandRow(
                icon: Icons.image_outlined,
                label: l10n.attachImages,
                detail: l10n.pickFromGallery,
                enabled: canPickImages,
                onTap: onPickImagesNow,
              ),
              _CommandRow(
                icon: Icons.attach_file,
                label: l10n.attachFile,
                detail: l10n.pickFileFromDevice,
                enabled: canPickFile,
                onTap: onPickFileNow,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A tactile FAB: `DshTappable` supplies the seat's only press feedback, so
/// the FAB's pressed overlay (the theme's `highlightColor`) is switched off
/// around it. The FAB's own splash and pressed lift are off at the call site
/// (`splashColor: Colors.transparent`, `highlightElevation == elevation`),
/// and [enabled] mirrors the FAB's `onPressed`, so a disabled seat does not
/// scale or click.
Widget _tactileFab(BuildContext context, Widget fab, {required bool enabled}) {
  return DshTappable(
    enabled: enabled,
    enableHaptic: true,
    child: Theme(
      data: Theme.of(context).copyWith(highlightColor: Colors.transparent),
      child: fab,
    ),
  );
}

/// Primary control, commercial-app form: a 34px circle that stays NEUTRAL
/// (selector fill, tertiary glyph) while the draft is empty — no idle
/// blue — and takes the primaryContainer fill with its onPrimaryContainer
/// glyph only when actionable: the up arrow while sendable, the stop
/// square while the turn runs. Ink rides the M3 contrast pair, never a
/// hardcoded white. The 40px tap target around the 34px visual keeps the
/// primary gesture thumb-sized on touch screens.
class _PrimarySendButton extends StatelessWidget {
  const _PrimarySendButton({
    required this.running,
    required this.sending,
    required this.enabled,
    this.onStop,
    this.onSend,
  });

  final bool running;
  final bool sending;
  final bool enabled;
  final VoidCallback? onStop;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final active = running
        ? onStop != null
        : enabled && !sending && onSend != null;
    final fill = active ? scheme.primaryContainer : scheme.surfaceContainerLow;
    final glyph = active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Tooltip(
      message: running
          ? l10n.stopTooltip
          : sending
          ? l10n.sending
          : l10n.send,
      // Native primary submit: an M3 small FAB. primaryContainer fill
      // with its onPrimaryContainer glyph when actionable; the neutral
      // selector fill with a tertiary glyph when idle — the composer's
      // "no idle blue" rule carried into the component. heroTag is
      // disabled so sibling send/stop FABs do not fight over the shared
      // hero.
      child: _tactileFab(
        context,
        enabled: active,
        FloatingActionButton.small(
          heroTag: null,
          shape: const CircleBorder(),
          backgroundColor: fill,
          foregroundColor: glyph,
          elevation: 2,
          // The press is the wrapper's scale; a lift on top of it would be
          // a second animation on the same gesture.
          highlightElevation: 2,
          hoverElevation: 3,
          focusElevation: 3,
          disabledElevation: 0,
          splashColor: Colors.transparent,
          enableFeedback: false,
          onPressed: active ? (running ? onStop : onSend) : null,
          child: running
              // Stop glyph: 10x10 rounded-3 square.
              ? Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: glyph,
                    borderRadius: BorderRadius.circular(kShapeChip),
                  ),
                )
              // Send glyph: the up arrow.
              : const Icon(Icons.arrow_upward, size: 22),
        ),
      ),
    );
  }
}

class ModeChip extends StatelessWidget {
  const ModeChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onClick,
    super.key,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    final button = selected
        ? FilledButton(onPressed: enabled ? onClick : null, child: Text(label))
        : OutlinedButton(
            onPressed: enabled ? onClick : null,
            child: Text(label),
          );
    return Padding(padding: const EdgeInsets.only(right: 4), child: button);
  }
}

/// One timeline item's durable identity: its kind and its own id.
///
/// Never its position, and never its transient state: a message that stops
/// streaming and a call that settles are the same row, and an element keyed on
/// the status would be recycled — losing the fold, the scroll or the clock it
/// holds — every time the status moved.
String timelineKey(TimelineItem item) => switch (item) {
  // One wire step renders as two rows when it reasoned and answered: the
  // thought (empty text) and the reply. They share the step's id, so the row
  // kind is part of the identity — otherwise the two rows collide, and the
  // second would take the first's element.
  TimelineMessage(:final value)
      when value.text.trim().isEmpty &&
          (value.reasoning?.trim().isNotEmpty ?? false) =>
    'reasoning:${value.id}',
  TimelineMessage(:final value) => 'message:${value.id}',
  TimelineTurnBoundary(:final turn) => 'turn:$turn',
  TimelineCompaction(:final id) => 'compaction:$id',
  TimelineCommand(:final commandId) => 'command:$commandId',
  TimelineContextInjection(:final id) => 'context:$id',
  TimelineToolCall(:final id) => 'tool:$id',
  TimelineApprovalRequest(:final requestId) => 'approval:$requestId',
  TimelineQuestionRequest(:final requestId) => 'question:$requestId',
  TimelineQueue() => 'queue',
  TimelineJobs() => 'jobs',
  // The envelope seq of the `hook/invoked` event is the one per-invocation
  // discriminator the wire carries: the payload has only `handlerId`, which two
  // invocations of one handler inside a window would share, and the result path
  // settles the earliest still-unsettled invocation rather than the first by
  // `handlerId`. A hand-built item without a seq falls back to the id.
  TimelineHookAudit(:final audit, :final seq) =>
    seq >= 0 ? 'hook:$seq' : 'hook:${audit.handlerId}',
  TimelineWorkflowRun(:final runId) => 'workflow:$runId',
  TimelineError(:final id) => 'error:$id',
};

/// The element key of one rendered transcript row.
///
/// The list matches children by this key rather than by index, so an insert
/// above keeps every element below — and the fold, the clock and the timer each
/// of those elements holds — instead of recycling them.
Key transcriptRowKey(Object row) {
  if (identical(row, _olderHistorySlot)) {
    return const ValueKey<String>('older-history');
  }
  if (identical(row, _turnStatusSlot)) {
    return const ValueKey<String>('turn-status');
  }
  if (row is TurnProcessSection) {
    // The block's ordinal in the window, not its Turn number: a page that
    // reaches the boundary turns an implicit block into turn 1 without adding
    // one, and a key that followed the number would remount the block and every
    // fold inside it.
    return ValueKey<String>('turn-process:${row.windowOrdinal}');
  }
  // The phase's own id (its first member's), never its entry count: a phase
  // that gains a member is the same fold.
  if (row is TimelineActivityGroup) {
    return ValueKey<String>('activity-group:${row.id}');
  }
  if (row is TimelineItem) return ValueKey<String>('item:${timelineKey(row)}');
  if (row is SessionQueueItem) {
    return ValueKey<String>('steering:${row.itemId}');
  }
  return ValueKey<String>('row:${row.runtimeType}');
}

/// Indexes rendered rows by their identity key, failing loud when two rows
/// share one.
///
/// A shared identity means the list hands the second row the first row's
/// element, so its fold, its clock or its scroll bleeds across the pair; a
/// silent mismatch is worse than a loud one, and this is the one place both the
/// transcript and a group's member list can notice it.
Map<Key, int> indexRowsByKey(List<Object> rows) {
  final Map<Key, int> index = <Key, int>{};
  for (var i = 0; i < rows.length; i++) {
    final Key key = transcriptRowKey(rows[i]);
    final int? seenAt = index[key];
    if (seenAt != null) {
      throw FlutterError(
        'Two transcript rows share the identity $key:\n'
        '  row $seenAt: ${rows[seenAt]}\n'
        '  row $i: ${rows[i]}',
      );
    }
    index[key] = i;
  }
  return index;
}

/// Ledger-style turn divider: a left-aligned micro label (14px hairline
/// tick + letterspaced caption text) marking where a turn begins — quiet
/// enough to read as a boundary notice, not conversation content.
class TurnBoundaryRow extends StatelessWidget {
  const TurnBoundaryRow({required this.turn, super.key});

  final int turn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        height: 20,
        child: Row(
          children: [
            Container(width: 14, height: 1, color: scheme.outlineVariant),
            const SizedBox(width: 10),
            Text(
              l10n.turnNumberLabel(turn),
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: scheme.outline, letterSpacing: 0.8),
            ),
          ],
        ),
      ),
    );
  }
}

/// Context-compaction marker — port of the web CompactionItem: one dim
/// row (leading context icon + title + count/summary caption), expandable to
/// markdown body when summary text is present.
class CompactionRow extends StatefulWidget {
  const CompactionRow({required this.compaction, super.key});

  final TimelineCompaction compaction;

  @override
  State<CompactionRow> createState() => _CompactionRowState();
}

class _CompactionRowState extends State<CompactionRow> {
  /// The marker opens to its summary on a tap; the reference's compaction row
  /// starts collapsed.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final expandable = widget.compaction.isExpandable;

    final String caption;
    if (widget.compaction.shadowedCount != null &&
        widget.compaction.shadowedTokens != null) {
      caption = l10n.compactionCompleted(
        widget.compaction.shadowedCount!,
        widget.compaction.shadowedTokens!,
      );
    } else if (expandable) {
      caption = l10n.compactionViewSummary;
    } else {
      caption = l10n.compactionSummaryUnavailable;
    }

    // The reference's `.compactionButton` wears the tertiary label tone and
    // steps to the secondary one on hover; its leading icon, title, and
    // summary all inherit that colour.
    return DisclosureRow(
      open: _expanded,
      expandable: expandable,
      onToggle: () => setState(() => _expanded = !_expanded),
      semanticLabel: l10n.contextCompacted,
      header: (BuildContext context, Color color) => Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: Center(
              child: Icon(Icons.layers_outlined, size: 14, color: color),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            l10n.contextCompacted,
            style: DshType.chatRowTitle.style(color: color),
          ),
          Container(
            width: 2,
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: scheme.labelCaption,
              shape: BoxShape.circle,
            ),
          ),
          Flexible(
            child: Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DshType.chatRowTitle.style(color: color),
            ),
          ),
        ],
      ),
      // The body takes the reference's own indent under the title
      // (`DisclosureRow`'s leading box plus its 6px gap).
      body: Padding(
        padding: const EdgeInsets.only(left: 22, right: 8, top: 2, bottom: 4),
        child: widget.compaction.summary == null
            ? const SizedBox.shrink()
            : MarkdownText(text: widget.compaction.summary!),
      ),
    );
  }
}

/// Host slash-command card — port of the reference's `GenericCommandCard`.
/// A running command shows the activity dot under the shared sweep while the
/// host text is still pending; a settled one shows the lifecycle glyph and the
/// host's own result text. The row names no colour of its own: the title and
/// the summary wear the shared disclosure tones — tertiary at rest, secondary
/// on hover — and a failed run wears the error role. No UI copy is composed
/// here: the name and text are host facts.
class CommandRow extends StatefulWidget {
  const CommandRow({required this.command, super.key});

  final TimelineCommand command;

  @override
  State<CommandRow> createState() => _CommandRowState();
}

class _CommandRowState extends State<CommandRow>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;

  /// The row's activity clock. [SweepHighlight] reads the pinned
  /// [kSweepCycle] off this clock's elapsed time, so the controller only has to
  /// repeat.
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: kSweepCycle,
  );

  @override
  void initState() {
    super.initState();
    if (widget.command.status == CommandRunStatus.running) _sweep.repeat();
  }

  @override
  void didUpdateWidget(covariant CommandRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final running = widget.command.status == CommandRunStatus.running;
    if (running && oldWidget.command.status != CommandRunStatus.running) {
      _sweep.repeat();
    }
    if (!running && oldWidget.command.status == CommandRunStatus.running) {
      _sweep.stop(canceled: true);
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final command = widget.command;
    final status = command.status;
    final running = status == CommandRunStatus.running;
    final failed = status == CommandRunStatus.failed;
    final text = command.text;
    final summaryText = switch (status) {
      CommandRunStatus.running =>
        command.name == 'compact' ? l10n.compactionRunning : text,
      CommandRunStatus.success || CommandRunStatus.failed => text,
    };
    // The reference's `GenericCommandCard` names no colour of its own: the
    // enclosing disclosure row wears the tertiary tone at rest and the
    // secondary one on hover, and the title and summary inherit it. Only a
    // failed run keeps a role of its own — the reference's `[data-error]`.
    final color = failed
        ? scheme.error
        : _hovered
        ? scheme.labelSecondary
        : scheme.labelTertiary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: ClipRect(
        child: SweepHighlight(
          controller: running && !DshMotion.isReducedMotion(context)
              ? _sweep
              : null,
          child: SizedBox(
            height: 24,
            child: Row(
              children: [
                if (running)
                  const ActivityDot()
                else
                  Icon(
                    failed ? Icons.error_outline : Icons.check_circle_outline,
                    size: 14,
                    color: failed ? scheme.error : scheme.primary,
                  ),
                const SizedBox(width: 6),
                Text('/${command.name}', style: _textStyle(theme, color)),
                if (summaryText != null && summaryText.isNotEmpty) ...[
                  // Inside the swept child, so the band tints the separator the
                  // way the reference's `data-shimmer-decoration` makes its
                  // background follow the highlight.
                  Container(
                    width: 2,
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: scheme.labelCaption,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      summaryText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _textStyle(theme, color),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle? _textStyle(ThemeData theme, Color color) =>
      theme.textTheme.bodySmall?.copyWith(color: color);
}

/// Logged non-user context (web ContextInjectionRow): a disclosure row in
/// the Tool-call chrome — the header names the role this context plays
/// ("Context injection", or "Recall" for cross-session material) beside
/// the durable producer the source identifies; the expanded body carries
/// the injected content.
class ContextInjectionRow extends StatefulWidget {
  const ContextInjectionRow({
    required this.injection,
    super.key,
    this.inline = false,
  });

  final TimelineContextInjection injection;

  /// Render the header and the body without a disclosure of this row's own:
  /// the activity card already opened for this phase.
  final bool inline;

  @override
  State<ContextInjectionRow> createState() => _ContextInjectionRowState();
}

class _ContextInjectionRowState extends State<ContextInjectionRow> {
  bool _expanded = false;

  /// The row header: glyph, the role this context plays, the durable
  /// producer, and the optional summary, in the tone the row wears.
  Widget _headerRow(BuildContext context, Color tone) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final injection = widget.injection;
    return Row(
      children: [
        // The reference's disclosure header: a 16px leading box holding the
        // 14px glyph, then a 6px gap (`DisclosureRow.module.css:47-69`), with
        // the role title on the row's own 13/24 step in `label-tertiary`.
        SizedBox(
          width: 16,
          height: 16,
          child: Center(
            child: Icon(
              Icons.travel_explore,
              size: 14,
              color: scheme.labelTertiary,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          injection.isRecall ? l10n.recallLabel : l10n.contextInjectionLabel,
          style: DshType.chatRowTitle.style(color: scheme.labelTertiary),
        ),
        if (injection.producerLabel case final label?) ...[
          Container(
            width: 2,
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: scheme.labelCaption,
              shape: BoxShape.circle,
            ),
          ),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // The producer name is the reference's `.source`: the secondary
              // size on the 24px line, `label-tertiary`
              // (`ContextInjectionRow.module.css:27-34`).
              style: DshType.chatRowTitle.style(color: scheme.labelTertiary),
            ),
          ),
        ],
        if (injection.summary case final summary?) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DshType.chatRowTitle.style(color: scheme.labelTertiary),
            ),
          ),
        ],
      ],
    );
  }

  /// The injected content: the reference's capped code panel
  /// (`ContextInjectionRow.module.css` `.body`, :44-58) — the indent under the
  /// title, the code-block surface on the `radius-md` step, a 141px cap and
  /// its own scroll.
  Widget _body(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 22, top: 4),
      constraints: const BoxConstraints(maxHeight: 141),
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 12),
      decoration: BoxDecoration(
        color: scheme.markdownCodeBlock,
        borderRadius: BorderRadius.circular(kRadiusMd),
      ),
      child: SingleChildScrollView(
        child: MarkdownText(text: widget.injection.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.inline) {
      // The activity card already opened for this phase: the injection shows
      // its header and content with no disclosure of its own.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _headerRow(context, Theme.of(context).colorScheme.labelTertiary),
            if (widget.injection.text.trim().isNotEmpty) _body(context),
          ],
        ),
      );
    }
    final hasBody = widget.injection.text.trim().isNotEmpty;
    // The same one-line disclosure chrome as a tool or thought row: a 24px
    // line carrying the role title, with a chevron only while there is
    // injected content to open (web rule).
    final l10n = AppLocalizations.of(context)!;
    return DisclosureRow(
      open: _expanded,
      expandable: hasBody,
      onToggle: () => setState(() => _expanded = !_expanded),
      semanticLabel: widget.injection.isRecall
          ? l10n.recallLabel
          : l10n.contextInjectionLabel,
      header: _headerRow,
      body: _body(context),
    );
  }
}

class _RenameSessionDialog extends StatefulWidget {
  const _RenameSessionDialog({required this.onSave});

  final void Function(String title) onSave;

  @override
  State<_RenameSessionDialog> createState() => _RenameSessionDialogState();
}

class _RenameSessionDialogState extends State<_RenameSessionDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.renameSession),
      content: TextField(
        controller: _controller,
        autofocus: true,
        onSubmitted: (_) => Navigator.of(context).pop(),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            widget.onSave(_controller.text);
            Navigator.of(context).pop();
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? get lastOrNull => isEmpty ? null : last;
}

/// Web `workspaceLabel`: basename of the cwd, raw path when separator-only.
String? _workspaceLabel(String? cwd) {
  if (cwd == null || cwd.isEmpty) return null;
  final segments = cwd
      .split(RegExp(r'[/\\]'))
      .where((s) => s.trim().isNotEmpty);
  return segments.isEmpty ? cwd : segments.last;
}
