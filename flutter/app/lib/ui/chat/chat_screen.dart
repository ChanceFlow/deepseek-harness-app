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
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/command.dart';
import 'package:domain/model/cordis.dart';
import 'package:domain/model/goal.dart';
import 'package:domain/model/jobs.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/permission_select.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/sandbox.dart';
import 'package:domain/model/todo.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/skills.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/token_usage.dart';
import 'package:domain/model/workspace_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../di/providers.dart';
import '../../local_state/local_state_providers.dart';
import 'chat_error_banner.dart';
import 'chat_ui_state.dart';
import 'chat_local_state.dart';
import 'command_roster.dart';
import 'host_unreachable_banner.dart';
import 'file_preview_sheet.dart';
import 'markdown/markdown_text.dart';
import 'job_list_action.dart';
import 'message_icon_actions.dart';
import 'message_run_metrics.dart';
import 'model_select.dart';
import 'permission_select.dart';
import 'produced_files.dart';
import 'produced_files_row.dart';
import 'session_log_export_action.dart';
import 'session_panel.dart';

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
import '../trajectory/trajectory_entry.dart';
import 'timeline_folding.dart';
import 'todo_panel.dart';
import 'tool_group_summary.dart';
import 'tool_row_model.dart';
import 'turn_status_row.dart';
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
                  onAction: controller.onAction,
                  loadAttachment: controller.loadAttachmentBytes,
                  readWorkspaceFile: controller.readWorkspaceFile,
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
    this.readWorkspaceFile = _noWorkspaceFileRead,
    this.onRefreshModels,
    this.backendId,
    this.localState,
    this.backendSlices,
    this.onSelectBackend,
    this.onSelectBackendSession,
    this.dispatchSessionAction,
  });

  final ChatUiState uiState;
  final void Function(ChatAction) onAction;
  final AttachmentLoader loadAttachment;

  /// Repository seam for the file-preview sheet (`workspaceFiles/read`).
  final WorkspaceFileReader readWorkspaceFile;

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

  /// Web SessionNodeItem "Archive session" (sidebar long-press verb):
  /// commits directly (reference archive is non-destructive).
  void _dispatchArchiveSession(String backendId, String sessionId) {
    widget.dispatchSessionAction?.call(backendId, ArchiveSession(sessionId));
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
          onOpenSubagents: _openSubagents,
          compact: compact,
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
                          ),
                        ),
                        Expanded(
                          child: ChatPanel(
                            uiState: uiState,
                            onAction: onAction,
                            loadAttachment: widget.loadAttachment,
                            readWorkspaceFile: widget.readWorkspaceFile,
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
              child: SessionPanel(
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
                    onAction(CreateSessionInWorkspace(workspaceId)),
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
              ),
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ChatPanel(
                    uiState: uiState,
                    onAction: onAction,
                    loadAttachment: widget.loadAttachment,
                    readWorkspaceFile: widget.readWorkspaceFile,
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
    super.key,
    this.backendId,
    this.onOpenSubagents,
    this.compact = false,
  });

  final ChatUiState uiState;
  final void Function(ChatAction) onAction;

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

  Future<void> _rename(BuildContext context, String sessionId) {
    return showDialog<void>(
      context: context,
      builder: (context) => _RenameSessionDialog(
        onSave: (title) => onAction(RenameSession(sessionId, title)),
      ),
    );
  }

  Future<void> _archive(BuildContext context, String sessionId) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(l10n.archiveSession),
          content: Text(l10n.archiveSessionBody),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                onAction(ArchiveSession(sessionId));
                Navigator.of(context).pop();
              },
              child: Text(l10n.archive),
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
    final hasActiveJobs = uiState.jobs.any(
      (j) => j.status == JobStatus.running,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasActiveJobs || !compact) JobListAction(jobs: uiState.jobs),
        if (!compact) ...[
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
                case _SessionVerb.export:
                  onAction(ExportSessionLog(sessionId));
                case _SessionVerb.subagents:
                  onOpenSubagents?.call();
                case _SessionVerb.rename:
                  unawaited(_rename(context, sessionId));
                case _SessionVerb.fork:
                  onAction(ForkSession(sessionId));
                case _SessionVerb.archive:
                  unawaited(_archive(context, sessionId));
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
            onPressed: archivable ? () => _archive(context, sessionId) : null,
            icon: const Icon(Icons.archive_outlined),
          ),
        ],
      ],
    );
  }
}

/// Session verbs the phone bar keeps behind its overflow menu.
enum _SessionVerb { trajectory, export, subagents, rename, fork, archive }

/// Sentinel for the turn-status row in the transcript's row list: not a
/// timeline item, only a row the gap math and the builder dispatch on.
const Object _turnStatusSlot = Object();

class _OlderHistorySlot {
  const _OlderHistorySlot();
}

/// Sentinel for the older-history row at the head of the transcript: not a
/// timeline item, only a row the gap math and the builder dispatch on.
const Object _olderHistorySlot = _OlderHistorySlot();

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    required this.uiState,
    required this.onAction,
    required this.loadAttachment,
    required this.readWorkspaceFile,
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

  /// Repository seam the file-preview sheet reads through.
  final WorkspaceFileReader readWorkspaceFile;

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
    if (oldWidget.uiState.selectedSessionId !=
        widget.uiState.selectedSessionId) {
      _flushReadOffset();
      _readOffsetSave?.cancel();
      _readOffsetSave = null;
      _pinned = true;
      _showJumpToBottom = false;
      _lastFollowSignature = null;
      _lastTrailingUserKey = null;
      _anchorDistanceFromBottom = null;
      _autoLoadDispatched = false;
      _bindSession();
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
      buffer.write('${items.length}:${timelineKey(last)}$growth');
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
  void _bindSession() {
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
      child: ChatErrorBanner(
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
        initialDiff: diff,
      ),
    );
  }

  Widget _timelineBody(ChatUiState uiState, SessionSummary? session) {
    if (uiState.timeline.isEmpty) {
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
    final groupedItems = foldTimelineActivities(items);
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
    final producedByMessage = producedFilesByClosingMessage(
      items,
      latestTurnClosed: !sessionBusy,
    );
    // The status line rides the tail of the transcript: with nothing
    // visible to be a tail after (a queue-only window), it renders nothing
    // — the queue dock and the composer seat already carry the run.
    final showTurnStatus = _turnStatusVisible(uiState) && items.isNotEmpty;
    final showOlder = uiState.hasMoreOlder || uiState.isLoadingOlder;
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kReadingMeasure),
        child: ListView.separated(
          controller: _timelineScroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: rows.length,
          separatorBuilder: (_, index) => SizedBox(
            height: _gapAfter(
              rows[index],
              index + 1 < rows.length ? rows[index + 1] : null,
            ),
          ),
          itemBuilder: (context, index) {
            final row = rows[index];
            if (identical(row, _olderHistorySlot)) {
              return OlderHistoryRow(
                isLoading: uiState.isLoadingOlder,
                onLoadOlder: () {
                  _recordScrollAnchor();
                  _autoLoadDispatched = true;
                  widget.onAction(const LoadOlderHistoryAction());
                },
              );
            }
            if (row is TimelineActivityGroup) {
              return ActivityGroupRow(
                key: ValueKey('activity-group:${row.id}:${row.entries.length}'),
                group: row,
                onAction: widget.onAction,
                loadAttachment: widget.loadAttachment,
                onPreviewFile: _openFilePreview,
                expansion: _sessionState,
                onOpenChild: _openWorkflowMember,
              );
            }
            if (row is TimelineItem) {
              return TimelineRow(
                key: ValueKey(timelineKey(row)),
                item: row,
                onAction: widget.onAction,
                loadAttachment: widget.loadAttachment,
                onPreviewFile: _openFilePreview,
                expansion: _sessionState,
                onOpenChild: _openWorkflowMember,
                producedPaths: row is TimelineMessage
                    ? producedByMessage[row.value.id]
                    : null,
              );
            }
            if (row is SessionQueueItem) {
              return PendingSteeringRow(
                key: ValueKey('steering:${row.itemId}'),
                text: row.text,
              );
            }
            return const TurnStatusRow(key: ValueKey('turn-status'));
          },
        ),
      ),
    );
  }

  /// Vertical rhythm between two transcript rows. A run of steps is one
  /// paragraph and closes up; a message opens a new one. Equal gaps
  /// everywhere read as a list of unrelated lines, which is what the
  /// transcript stopped looking like a conversation. The tail signals —
  /// the turn-status line and a pending steering row — open their own
  /// block like a message does (steering is the reader's own words). A
  /// null `below` is the tail: block.
  static double _gapAfter(Object above, Object? below) {
    const double step = 6;
    const double block = 16;
    const double turn = 24;
    if (below == null) return block;
    if (below is TimelineTurnBoundary) return turn;
    final bool aboveIsStep = !_opensBlock(above);
    final bool belowIsStep = !_opensBlock(below);
    return aboveIsStep && belowIsStep ? step : block;
  }

  static bool _opensBlock(Object row) {
    if (row is TimelineMessage) {
      return row.value.text.trim().isNotEmpty;
    }
    return row is SessionQueueItem ||
        identical(row, _turnStatusSlot) ||
        identical(row, _olderHistorySlot);
  }

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
        FloatingActionButton.small(
          heroTag: null,
          shape: const CircleBorder(),
          backgroundColor: scheme.surfaceContainerLow,
          foregroundColor: scheme.onSurfaceVariant,
          elevation: 2,
          highlightElevation: 2,
          hoverElevation: 3,
          focusElevation: 3,
          disabledElevation: 0,
          splashColor: Colors.transparent,
          enableFeedback: false,
          onPressed: _jumpToBottom,
          child: const Icon(Icons.arrow_downward, size: 22),
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
    return DockAnchor(
      dockKey: _dockKey,
      child: Padding(
        // No inset at the top: the transcript runs to the bar and slides
        // under it. A gap there is a blank strip that also clips the first
        // row mid-line, which reads as a rendering fault.
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
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
                    NoImageRoom(:final room) => l10n.imageRejectionNoRoom(room),
                  },
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        final primaryFocus = FocusManager.instance.primaryFocus;
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
                        child: ScaleTransition(scale: animation, child: child),
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
              children: [
                if (!_hasPendingDecision) ...[
                  TodoPanel(todos: uiState.todos ?? const <TodoItem>[]),
                  GoalBarStrip(goal: uiState.goal, onAction: widget.onAction),
                  // The session's durable reminders: nothing else on this
                  // surface shows them (the pinned deployment composes no
                  // `schedule` projection), and the dock is where the rest
                  // of the session's standing state already lives. An
                  // unreported set states itself rather than disappearing.
                  if (selectedSessionId != null)
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
                  ApprovalPanel(
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
                else
                  Row(
                    children: [
                      Expanded(
                        child: ComposerBar(
                          onStop: selectedSessionId == null
                              ? null
                              : () => widget.onAction(const CancelTurnAction()),
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
                          skills: uiState.skills,
                          commands: uiState.commands,
                          contextPressure: uiState.contextPressure,
                          contextBreakdown: uiState.contextBreakdown,
                          onAction: widget.onAction,
                          sessionId: selectedSessionId,
                          sessionState: _sessionState,
                          permissions: uiState.permissions,
                          sandboxMode: uiState.sandboxMode,
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
    );
  }
}

/// The input dock: one raised surface carrying every strip that sits
/// between the transcript and the thumb — plan, goal, queue, composer.
/// Each strip used to draw its own border and radius, which stacked three
/// nested boxes at the screen's busiest edge; the surface belongs to the
/// dock, and the strips divide with hairlines.
class _InputDock extends StatelessWidget {
  const _InputDock({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final isKeyboardOpen = mediaQuery.viewInsets.bottom > 0;
    if (!isKeyboardOpen) {
      return Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(kShapeDock),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: kM3ShadowElevation1,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );
    }
    final availableHeight =
        mediaQuery.size.height -
        mediaQuery.viewInsets.bottom -
        mediaQuery.padding.top -
        mediaQuery.padding.bottom;
    final maxDockHeight = (availableHeight * 0.50).clamp(160.0, 360.0);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(kShapeDock),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: kM3ShadowElevation1,
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxDockHeight),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
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
    this.onPreviewFile,
    this.expansion,
    this.producedPaths,
    this.onOpenChild,
  });

  final TimelineItem item;
  final void Function(ChatAction) onAction;
  final AttachmentLoader loadAttachment;

  /// File-preview action for a tool row's generated/edited path.
  final void Function(String path, {EditDiffModel? diff})? onPreviewFile;

  /// Tool-row expansion persistence of the selected session; null keeps
  /// expansion in memory only.
  final ToolExpansionPersistence? expansion;

  /// Paths this turn's successful mutations produced; non-null only on the
  /// turn's closing assistant message.
  final List<String>? producedPaths;

  /// Jump target for a workflow member's child session; null renders the
  /// card read-only (a nested child record has no further navigation seat).
  final WorkflowMemberOpener? onOpenChild;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return switch (item) {
      TimelineMessage(:final value) => MessageRow(
        message: value,
        loadAttachment: loadAttachment,
        onFork: value.seq == null
            ? null
            : () => onAction(ForkSession(value.sessionId, atSeq: value.seq)),
        usage: (item as TimelineMessage).usage,
        firstTokenAtEpochMs: (item as TimelineMessage).firstTokenAtEpochMs,
        producedPaths: producedPaths,
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

class MessageRow extends StatelessWidget {
  const MessageRow({
    required this.message,
    required this.loadAttachment,
    super.key,
    this.onFork,
    this.usage,
    this.firstTokenAtEpochMs,
    this.producedPaths,
    this.onPreviewFile,
  });

  final ChatMessage message;
  final AttachmentLoader loadAttachment;

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

  /// Opens a produced path with the in-app preview sheet.
  final void Function(String path)? onPreviewFile;

  @override
  Widget build(BuildContext context) {
    if (message.role == MessageRole.user) {
      // The reader's own words: a quiet container, right-aligned,
      // with maxWidth capped at 82% (up to 525dp) so short messages fit
      // their content while long runs wrap cleanly, with the tail corner
      // tightened so the bubble points at its author.
      // No action row rides under it — long-press copies, and the reply's
      // row already dates the turn.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
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
        for (final ref in message.images)
          AttachmentImageRow(
            sessionId: message.sessionId,
            ref: ref,
            loadAttachment: loadAttachment,
          ),
        // The turn's produced files close the body, above the action row —
        // the reference turn-tail order (ProducedFiles, then
        // MessageIconActions). Streaming hides it: the row belongs to a
        // finished turn.
        if (!message.streaming &&
            paths != null &&
            paths.isNotEmpty &&
            onPreviewFile != null)
          ProducedFilesRow(paths: paths, onOpenFile: onPreviewFile!),
        if (message.streaming) ...[
          // Once text flows the streaming tail is the blinking caret;
          // the pre-first-token wait is said once, by the turn-status
          // line at the timeline tail — not a loader here too.
          if (message.text.isNotEmpty)
            const _StreamingCaret(key: ValueKey('streaming-caret')),
        ] else if (message.text.isNotEmpty)
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
    );
  }
}

/// The reader's message container: a neutral fill (the transcript's one
/// saturated seat is the send button), the shape scale's card radius, and
/// a tightened tail corner. Long-press copies the text — the gesture every
/// mobile transcript carries — so the bubble needs no chrome of its own.
class _UserBubble extends StatefulWidget {
  const _UserBubble({required this.text, this.onFork});

  final String text;
  final VoidCallback? onFork;

  @override
  State<_UserBubble> createState() => _UserBubbleState();
}

class _UserBubbleState extends State<_UserBubble> {
  /// Where the finger went down: [InkWell] reports the position on tap-down
  /// and the long press that follows carries none, so the menu anchors to
  /// the remembered point.
  Offset _pressed = Offset.zero;

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
  Future<void> _openMenu(BuildContext context, Offset globalPosition) async {
    final l10n = AppLocalizations.of(context)!;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final verb = await showMenu<_BubbleVerb>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<_BubbleVerb>(
          value: _BubbleVerb.copy,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.copy_outlined, size: 18),
            title: Text(l10n.copyTooltip),
          ),
        ),
        if (onFork != null)
          PopupMenuItem<_BubbleVerb>(
            value: _BubbleVerb.fork,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.alt_route, size: 18),
              title: Text(l10n.forkFromHere),
            ),
          ),
      ],
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
      color: theme.colorScheme.secondaryContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(kShapeDock),
          topRight: Radius.circular(kShapeDock),
          bottomLeft: Radius.circular(kShapeDock),
          bottomRight: Radius.circular(kShapeChip),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTapDown: (TapDownDetails details) =>
            _pressed = details.globalPosition,
        onLongPress: () => _openMenu(context, _pressed),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(text, style: theme.textTheme.bodyMedium),
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
/// [TurnStatusRow] at the timeline tail, so the transcript never carries
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
    this.onPreviewFile,
    this.expansion,
    this.onOpenChild,
  });

  final TimelineActivityGroup group;
  final void Function(ChatAction) onAction;
  final AttachmentLoader loadAttachment;

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
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  bool get _isRunning =>
      widget.group.calls.any((call) => call.status == ToolRunStatus.running) ||
      (widget.group.thought?.value.streaming ?? false);

  bool get _hasFailure =>
      widget.group.calls.any((call) => call.status == ToolRunStatus.failed);

  @override
  void initState() {
    super.initState();
    if (_hasFailure && !_isRunning) _expanded = true;
    if (_isRunning) _sweep.repeat();
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final entries = widget.group.entries;
    final calls = widget.group.calls;
    final thought = widget.group.thought;
    final firstInjection = entries
        .whereType<TimelineContextInjection>()
        .firstOrNull;

    final summary = deriveToolGroupSummary(calls, l10n);
    final running = summary.runningCalls;
    final failed = summary.failedCalls;
    final thoughtLabel = thought == null
        ? null
        : reasoningLabel(
            l10n,
            running: thought.value.streaming,
            elapsed: thought.value.reasoningDuration,
          );
    // The header names the phase: the tool summary while tools ran, and the
    // thought or the injection when the phase only reasoned or was handed
    // context. The thinking time rides the subtitle so a phase that both
    // thought and worked keeps both facts on its collapsed line.
    final title = calls.isNotEmpty
        ? summary.title
        : thoughtLabel ??
              (firstInjection?.isRecall ?? false
                  ? l10n.recallLabel
                  : firstInjection == null
                  ? ''
                  : l10n.contextInjectionLabel);
    final baseSubtitle = summary.subtitle;
    final showBaseSubtitle =
        running > 0 || (title.contains('operation') || title.contains('操作'));
    final subtitle = <String>[
      if (showBaseSubtitle && baseSubtitle.isNotEmpty && baseSubtitle != title)
        baseSubtitle,
      if (calls.isNotEmpty && thoughtLabel != null) thoughtLabel,
    ].join(' · ');

    final settledCount = calls.length - running - failed;
    final leadingWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (running > 0) const ActivityDot(),
        if (running > 0 && settledCount > 0) const SizedBox(width: 4),
        if (settledCount > 0 && running > 0)
          Icon(Icons.check, size: 14, color: scheme.success),
        if (running == 0)
          if (failed > 0)
            Icon(Icons.close, size: 14, color: scheme.error)
          else if (calls.isEmpty && thought != null)
            Icon(
              Icons.psychology_outlined,
              size: 14,
              color: scheme.onSurfaceVariant,
            )
          else if (calls.isEmpty)
            Icon(Icons.travel_explore, size: 14, color: scheme.onSurfaceVariant)
          else if (summary.filesExplored > 0 || summary.searches > 0)
            Icon(Icons.travel_explore, size: 14, color: scheme.onSurfaceVariant)
          else
            Icon(Icons.check, size: 14, color: scheme.success),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kShapeCard),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: SweepHighlight(
              controller: running > 0 && !DshMotion.isReducedMotion(context)
                  ? _sweep
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                child: Row(
                  children: [
                    leadingWidget,
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ] else ...[
                      const Spacer(),
                    ],
                    if (failed > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        l10n.turnFailedCount(failed),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    Icon(
                      _expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded) ...[
            Container(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 8, 8),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.4),
                      width: 1.2,
                    ),
                  ),
                ),
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entry in entries)
                      switch (entry) {
                        TimelineToolCall() => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: ToolCallRow(
                            key: ValueKey(timelineKey(entry)),
                            call: entry,
                            onPreviewFile: widget.onPreviewFile,
                            expansion: widget.expansion,
                          ),
                        ),
                        TimelineContextInjection() => Material(
                          type: MaterialType.transparency,
                          child: ContextInjectionRow(
                            key: ValueKey(timelineKey(entry)),
                            injection: entry,
                          ),
                        ),
                        TimelineMessage(:final value) => Material(
                          type: MaterialType.transparency,
                          child: ReasoningRow(
                            key: ValueKey(timelineKey(entry)),
                            text: value.reasoning ?? '',
                            running: value.streaming,
                            elapsedDuration: value.reasoningDuration,
                          ),
                        ),
                        TimelineHookAudit(:final audit) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: HookAuditRow(
                            key: ValueKey(timelineKey(entry)),
                            audit: audit,
                          ),
                        ),
                        final TimelineWorkflowRun run => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: WorkflowRunRow(
                            key: ValueKey(timelineKey(entry)),
                            run: run,
                            onOpenChild: widget.onOpenChild,
                          ),
                        ),
                        _ => const SizedBox.shrink(),
                      },
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
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
    this.expansion,
    this.onPreviewFile,
  });

  final TimelineToolCall call;

  /// Expansion persistence keyed by this row's [timelineKey] value;
  /// null keeps expansion in memory only.
  final ToolExpansionPersistence? expansion;
  final void Function(String path, {EditDiffModel? diff})? onPreviewFile;

  @override
  State<ToolCallRow> createState() => _ToolCallRowState();
}

class _ToolCallRowState extends State<ToolCallRow>
    with SingleTickerProviderStateMixin {
  late final ExpansibleController _tileController = ExpansibleController();
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
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
          if (mounted && restored && !_tileController.isExpanded) {
            _tileController.expand();
          }
        }),
      );
    }
    if (widget.call.status == ToolRunStatus.failed &&
        !_tileController.isExpanded) {
      _tileController.expand();
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
      if (widget.call.status == ToolRunStatus.failed &&
          !_tileController.isExpanded) {
        _tileController.expand();
      }
    }
  }

  @override
  void dispose() {
    _tileController.dispose();
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
    final hasDetails = model.body != null || model.output != null;
    return Semantics(
      label: running
          ? l10n.semanticsRunning
          : failed
          ? l10n.semanticsFailed
          : null,
      // A step is one line of text, so the row is one line tall. The
      // tile's stock trailing chevron is a 24px glyph that sets the row
      // height on its own; shrinking the ambient icon size brings it back
      // in scale with the 14px status glyph and keeps the rotation.
      child: IconTheme.merge(
        data: const IconThemeData(size: 18),
        child: ExpansionTile(
          controller: _tileController,
          // No payload means a non-interactive row: the native tile drops
          // its ripple and trailing arrow the same way the web row is inert.
          enabled: hasDetails,
          showTrailingIcon: hasDetails,
          dense: true,
          visualDensity: VisualDensity.compact,
          minTileHeight: 30,
          // An expanded tile rules itself off top and bottom by default;
          // the transcript's steps divide with space.
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 2),
          onExpansionChanged: (expanded) {
            if (hasDetails) {
              unawaited(
                widget.expansion?.setExpanded(
                  timelineKey(widget.call),
                  expanded,
                ),
              );
            }
          },
          title: ClipRect(
            child: SweepHighlight(
              controller: running && !DshMotion.isReducedMotion(context)
                  ? _sweep
                  : null,
              child: Padding(
                padding: EdgeInsets.zero,
                child: Row(
                  children: [
                    // A product row may carry its own glyph (the todo
                    // checklist); otherwise the state-colored variant
                    // chrome.
                    model.leading != null
                        ? Icon(
                            model.leading,
                            size: 14,
                            color: scheme.onSurfaceVariant,
                          )
                        : _leading(context, model.state),
                    const SizedBox(width: 8),
                    // Type carries the semantics: the verb is a label, the
                    // payload is data. Monospace on the payload also keeps
                    // paths and patterns legible at a glance.
                    Text(
                      model.title,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        // Web ToolRow: the summary is args-derived; the
                        // settled result text never reaches this slot.
                        failed && model.errorSummary != null
                            ? model.errorSummary!
                            : model.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: failed
                              ? theme.colorScheme.error
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    // The todo parallel-active count rides a
                    // non-shrinking suffix beside the truncatable text.
                    if (model.summarySuffix case final suffix?) ...[
                      const SizedBox(width: 4),
                      Text(
                        suffix,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // The theme's childrenPadding (left 20) carries the web IN/OUT
          // card's inset; the card keeps only its top gap.
          children: [
            if (hasDetails)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(kShapeCard),
                  border: Border.all(color: scheme.outlineVariant),
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
                      _fileActionBar(context, filePath, diff: model.diff),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fileActionBar(
    BuildContext context,
    String path, {
    EditDiffModel? diff,
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
                    fontFamily: 'monospace',
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
    final fullDiffText = [
      for (final line in diff.lines)
        '${line.kind == DiffLineKind.delete
            ? '-'
            : line.kind == DiffLineKind.insert
            ? '+'
            : ' '} ${line.text}',
    ].join('\n');

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
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in diff.lines)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: switch (line.kind) {
                              DiffLineKind.delete =>
                                scheme.errorContainer.withValues(alpha: 0.35),
                              DiffLineKind.insert =>
                                scheme.primaryContainer.withValues(alpha: 0.35),
                              DiffLineKind.equal => Colors.transparent,
                            },
                            borderRadius: BorderRadius.circular(kShapeChip),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 16,
                                child: Text(
                                  switch (line.kind) {
                                    DiffLineKind.delete => '-',
                                    DiffLineKind.insert => '+',
                                    DiffLineKind.equal => ' ',
                                  },
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: switch (line.kind) {
                                      DiffLineKind.delete => scheme.error,
                                      DiffLineKind.insert => scheme.primary,
                                      DiffLineKind.equal =>
                                        scheme.onSurfaceVariant,
                                    },
                                  ),
                                ),
                              ),
                              Text(
                                line.text,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  color: scheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
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

  Widget _leading(BuildContext context, ToolRowState state) {
    final scheme = Theme.of(context).colorScheme;
    switch (state) {
      case ToolRowState.running:
        return const ActivityDot();
      case ToolRowState.ok:
        return Icon(Icons.check, size: 14, color: scheme.success);
      case ToolRowState.error:
        return Icon(
          Icons.close,
          size: 14,
          color: Theme.of(context).colorScheme.error,
        );
    }
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
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

class ApprovalRow extends StatelessWidget {
  const ApprovalRow({
    required this.requestId,
    required this.approvalId,
    required this.toolName,
    required this.reason,
    required this.onAction,
    super.key,
  });

  final String requestId;
  final String approvalId;
  final String toolName;
  final String? reason;
  final void Function(ChatAction) onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.approveTool(toolName),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (reason case final String because)
          Text(because, style: Theme.of(context).textTheme.bodySmall),
        Row(
          children: [
            FilledButton(
              onPressed: () => onAction(
                RespondApproval(
                  requestId: requestId,
                  approvalId: approvalId,
                  allowed: true,
                ),
              ),
              child: Text(l10n.allow),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: OutlinedButton(
                onPressed: () => onAction(
                  RespondApproval(
                    requestId: requestId,
                    approvalId: approvalId,
                    allowed: false,
                  ),
                ),
                child: Text(l10n.reject),
              ),
            ),
          ],
        ),
      ],
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

  @override
  void didUpdateWidget(covariant QuestionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Compose remembered drafts keyed by request id.
    if (oldWidget.request.requestId != widget.request.requestId) {
      _drafts = const <String, QuestionDraft>{};
      _index = 0;
      _error = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final review = _planReviewOf(request.questions);
    if (review != null) {
      return _PlanReviewCard(
        requestId: request.requestId,
        review: review,
        onAction: widget.onAction,
      );
    }
    if (request.questions.isEmpty) return const SizedBox.shrink();
    final index = _index.clamp(0, request.questions.length - 1);
    return _QuestionCard(
      questions: request.questions,
      index: index,
      drafts: _drafts,
      error: _error,
      onChoose: _choose,
      onDraftChange: (id, draft) =>
          setState(() => _drafts = {..._drafts, id: draft}),
      onBack: () => setState(() {
        if (_index > 0) _index -= 1;
        _error = null;
      }),
      onNext: _continue,
      onSkip: _skip,
      onDismiss: () =>
          widget.onAction(DismissQuestionAction(requestId: request.requestId)),
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

/// Generic question flow card (the web QuestionComposer port): header with
/// eyebrow/title and a dismiss button, body with the markdown detail, option
/// rows (numbered single-select or checkbox multi-select with the
/// recommended badge), a custom-answer row or optionless textarea, and a
/// footer with the pager, validation feedback, and skip / next / submit.
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
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
    final scheme = Theme.of(context).colorScheme;
    final question = questions[index];
    final draft = drafts[question.id] ?? const QuestionDraft();
    final hasOptions = question.options.isNotEmpty;
    final answered =
        draft.selected.isNotEmpty || draft.customText.trim().isNotEmpty;
    final isLast = index == questions.length - 1;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(kShapeCard),
        boxShadow: kM3ShadowElevation1,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _QuestionCardHeader(question: question, onDismiss: onDismiss),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.45,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (question.detail case final String detail)
                    MarkdownText(text: detail),
                  if (hasOptions) ...[
                    const SizedBox(height: 8),
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
                          children: [
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
                ],
              ),
            ),
          ),
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

/// Plan-review decision card (the web PlanReviewPanel port): a warn-tinted
/// strip with a dot, the plan as the whole body (markdown), and a
/// right-aligned action row — discuss (dismiss), decline, and approve.
class _PlanReviewCard extends StatelessWidget {
  const _PlanReviewCard({
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
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    void decide(String label) {
      onAction(
        AnswerQuestionAction(
          requestId: requestId,
          answers: [
            QuestionAnswer(questionId: review.id, selectedOptions: [label]),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(kShapeCard),
        boxShadow: kM3ShadowElevation1,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: scheme.warning.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.warning,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.planReview,
                  style: TextStyle(
                    color: scheme.warning,
                    fontSize: 13,
                    height: 18 / 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.45,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: MarkdownText(text: review.plan),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () =>
                      onAction(DismissQuestionAction(requestId: requestId)),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurfaceVariant,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.edit_outlined, size: 14),
                      const SizedBox(width: 6),
                      Text(l10n.planDiscuss),
                    ],
                  ),
                ),
                if (review.decline case final String decline)
                  OutlinedButton(
                    onPressed: () => decide(decline),
                    child: Text(l10n.planDecline),
                  ),
                FilledButton(
                  onPressed: () => decide(review.approve),
                  child: Text(l10n.planApprove),
                ),
              ],
            ),
          ),
        ],
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

class ComposerBar extends ConsumerStatefulWidget {
  const ComposerBar({
    required this.enabled,
    required this.isSending,
    required this.running,
    required this.pendingImages,
    required this.imageLimits,
    required this.skills,
    required this.onAction,
    required this.onSend,
    super.key,
    this.commands,
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
  });

  final bool enabled;
  final bool isSending;
  final bool running;
  final List<PendingImage> pendingImages;
  final ImageLimits imageLimits;
  final List<SkillEntry> skills;
  final void Function(ChatAction) onAction;

  /// The selected session's live host-command roster (`commands/list`);
  /// null keeps the static built-ins standing in (see [command_roster]).
  final List<CommandDescriptor>? commands;

  /// Submit [text] and resolve with the host's acceptance: the composer
  /// keeps the draft (and its persisted value) until this future settles
  /// true, and never clears on false.
  final Future<bool> Function(String text) onSend;
  final VoidCallback? onStop;

  /// The session whose draft this composer edits; drives draft
  /// persistence alongside [sessionState].
  final String? sessionId;

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

  /// Counts reader keystrokes on the field (the [TextField] onChanged
  /// path; programmatic writes never touch it), so an in-flight draft
  /// read can tell "untouched" from "the reader is already typing here"
  /// — see [_restoreDraft].
  int _draftEdits = 0;

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
    _focusNode.requestFocus();
    setState(() {});
  }

  void _persistDraft() {
    unawaited(widget.sessionState?.writeDraft(_draftController.text));
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final attachAllowed =
        widget.enabled &&
        widget.pendingImages.length < widget.imageLimits.maxImagesPerMessage;

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
          if (widget.pendingImages.isNotEmpty)
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
          // Band 1 — the draft, edge to edge.
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
            child: TextField(
              controller: _draftController,
              focusNode: _focusNode,
              enabled: widget.enabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              onChanged: (_) {
                _draftEdits++;
                _persistDraft();
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
                    _PlusButton(
                      enabled: widget.enabled,
                      onPickImages: attachAllowed ? _pickImages : null,
                      skills: widget.skills,
                      commands: displayCommands,
                      onPickCommand: _handlePlusCommand,
                    ),
                    VoiceMicButton(
                      enabled:
                          widget.enabled && !voiceInputState.isWaitingOnEngine,
                      uiState: voiceInputState,
                      onStart: () {
                        _preRecordingDraft = _draftController.text;
                        unawaited(voiceController.startRecording());
                      },
                      onFinish: () =>
                          unawaited(voiceController.stopRecording()),
                      onCancel: () {
                        unawaited(voiceController.cancelRecording());
                        _draftController.text = _preRecordingDraft;
                        _draftController.selection = TextSelection.collapsed(
                          offset: _draftController.text.length,
                        );
                        _persistDraft();
                        setState(() {});
                      },
                      onOpenSettings: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (ctx) => const AsrModelsRoute(),
                          ),
                        );
                      },
                    ),
                    if (widget.permissions case final permissions?)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 135),
                        child: PermissionSelectChip(
                          value: permissions,
                          locked: !widget.enabled,
                          onAction: widget.onAction,
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
      widget.pendingImages.isNotEmpty;

  void _send([String? text]) {
    // Web envelope policy: an enter submission carrying images resolves
    // only through a command declaring image acceptance. Refuse before
    // anything is consumed — the draft and the images stay in place and
    // nothing executes.
    if (widget.pendingImages.isNotEmpty) {
      final refused = hostCommandImageRefusal(
        _draftController.text.trim(),
        _commandRoster,
      );
      if (refused != null) {
        widget.onAction(
          CommandImageRefusal(
            AppLocalizations.of(context)!.commandImagesUnsupported(refused),
          ),
        );
        return;
      }
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
    required this.skills,
    required this.commands,
    required this.onPickCommand,
  });

  final bool enabled;
  final VoidCallback? onPickImages;
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
    required this.skills,
    required this.commands,
    required this.onPickCommand,
    required this.onPickImagesNow,
  });

  final bool canPickImages;
  final List<SkillEntry> skills;
  final List<HostCommand> commands;
  final void Function(String name) onPickCommand;
  final VoidCallback onPickImagesNow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final int visibleCount = commands.length + skills.length + 1;
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
              // Mobile-only tail row: image intake (web uses paste/drop)
              // — demoted below the command roster.
              _CommandRow(
                icon: Icons.image_outlined,
                label: l10n.attachImages,
                detail: l10n.pickFromGallery,
                enabled: canPickImages,
                onTap: onPickImagesNow,
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

String timelineKey(TimelineItem item) => switch (item) {
  TimelineMessage(:final value) => 'message:${value.id}:${value.streaming}',
  TimelineTurnBoundary(:final turn) => 'turn:$turn',
  TimelineCompaction(:final id) => 'compaction:$id',
  TimelineCommand(:final commandId, :final status) =>
    'command:$commandId:$status',
  TimelineContextInjection(:final id) => 'context:$id',
  TimelineToolCall(:final id, :final status) => 'tool:$id:$status',
  TimelineApprovalRequest(:final requestId) => 'approval:$requestId',
  TimelineQuestionRequest(:final requestId) => 'question:$requestId',
  TimelineQueue() => 'queue',
  TimelineJobs() => 'jobs',
  TimelineHookAudit(:final audit) => 'hook:${audit.handlerId}:${audit.point}',
  TimelineWorkflowRun(:final runId, :final status) => 'workflow:$runId:$status',
  TimelineError(:final id) => 'error:$id',
};

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
class CompactionRow extends StatelessWidget {
  const CompactionRow({required this.compaction, super.key});

  final TimelineCompaction compaction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final expandable = compaction.isExpandable;

    final String caption;
    if (compaction.shadowedCount != null && compaction.shadowedTokens != null) {
      caption = l10n.compactionCompleted(
        compaction.shadowedCount!,
        compaction.shadowedTokens!,
      );
    } else if (expandable) {
      caption = l10n.compactionViewSummary;
    } else {
      caption = l10n.compactionSummaryUnavailable;
    }

    return IconTheme.merge(
      data: const IconThemeData(size: 18),
      child: ExpansionTile(
        enabled: expandable,
        showTrailingIcon: expandable,
        dense: true,
        visualDensity: VisualDensity.compact,
        minTileHeight: 28,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        title: Row(
          children: [
            Icon(
              Icons.layers_outlined,
              size: 14,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              l10n.contextCompacted,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            Container(
              width: 2,
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: scheme.outline,
                shape: BoxShape.circle,
              ),
            ),
            Flexible(
              child: Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        children: [
          if (expandable && compaction.summary != null)
            Padding(
              padding: const EdgeInsets.only(
                left: 20,
                right: 8,
                top: 2,
                bottom: 4,
              ),
              child: MarkdownText(text: compaction.summary!),
            ),
        ],
      ),
    );
  }
}

/// Host slash-command card — port of the web command flow node. The run
/// append renders the command name with the activity dot under the shared
/// sweep glare (web `dsh-command-row-sweep`); the done event resolves it
/// with the host's own result text (success in the label tone, an error
/// like "This operation was aborted" in the error tone). No UI copy is
/// composed here: the name and text are host facts.
class CommandRow extends StatefulWidget {
  const CommandRow({required this.command, super.key});

  final TimelineCommand command;

  @override
  State<CommandRow> createState() => _CommandRowState();
}

class _CommandRowState extends State<CommandRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
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
    return ClipRect(
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
              Text(
                '/${command.name}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: failed
                      ? scheme.error
                      : running
                      ? scheme.onSurfaceVariant
                      : scheme.onSurface,
                ),
              ),
              if (summaryText != null && summaryText.isNotEmpty) ...[
                Container(
                  width: 2,
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: scheme.outline,
                    shape: BoxShape.circle,
                  ),
                ),
                Flexible(
                  child: Text(
                    summaryText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: failed
                          ? scheme.error
                          : running
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface,
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

/// Logged non-user context (web ContextInjectionRow): a disclosure row in
/// the Tool-call chrome — the header names the role this context plays
/// ("Context injection", or "Recall" for cross-session material) beside
/// the durable producer the source identifies; the expanded body carries
/// the injected content.
class ContextInjectionRow extends StatelessWidget {
  const ContextInjectionRow({
    required this.injection,
    super.key,
    this.inline = false,
  });

  final TimelineContextInjection injection;

  /// Render the header and the body without a disclosure of this row's own:
  /// the activity card already opened for this phase.
  final bool inline;

  /// The row header: glyph, the role this context plays, the durable
  /// producer, and the optional summary.
  Widget _headerRow(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final injection = this.injection;
    return Row(
      children: [
        Icon(Icons.travel_explore, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          injection.isRecall ? l10n.recallLabel : l10n.contextInjectionLabel,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (injection.producerLabel case final label?) ...[
          Container(
            width: 2,
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: scheme.outline,
              shape: BoxShape.circle,
            ),
          ),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
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
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// The injected content.
  Widget _body(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2, bottom: 4),
    child: MarkdownText(text: injection.text),
  );

  @override
  Widget build(BuildContext context) {
    if (inline) {
      // The activity card already opened for this phase: the injection shows
      // its header and content with no disclosure of its own.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _headerRow(context),
            if (injection.text.trim().isNotEmpty) _body(context),
          ],
        ),
      );
    }
    final hasBody = injection.text.trim().isNotEmpty;
    return ExpansionTile(
      // No body means a non-interactive disclosure: the native tile drops
      // its ripple and trailing arrow (web rule).
      enabled: hasBody,
      showTrailingIcon: hasBody,
      dense: true,
      visualDensity: VisualDensity.compact,
      minTileHeight: 28,
      tilePadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      title: _headerRow(context),
      children: [_body(context)],
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
}

/// Web `workspaceLabel`: basename of the cwd, raw path when separator-only.
String? _workspaceLabel(String? cwd) {
  if (cwd == null || cwd.isEmpty) return null;
  final segments = cwd
      .split(RegExp(r'[/\\]'))
      .where((s) => s.trim().isNotEmpty);
  return segments.isEmpty ? cwd : segments.last;
}
