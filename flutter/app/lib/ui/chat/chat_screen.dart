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
import 'package:domain/model/goal.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/permission_select.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/todo.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/skills.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../di/providers.dart';
import '../../local_state/local_state_providers.dart';
import 'chat_ui_state.dart';
import 'chat_local_state.dart';
import 'command_roster.dart';
import 'markdown/markdown_text.dart';
import 'job_list_action.dart';
import 'message_icon_actions.dart';
import 'model_select.dart';
import 'permission_select.dart';
import 'session_panel.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../goal/goal_controller.dart';
import '../models/models_controller.dart';
import '../subagents/subagent_controller.dart';
import 'approval_panel.dart';
import '../goal/goal_screen.dart';
import '../subagents/subagent_screen.dart';

import 'activity_dot.dart';
import 'context_ring.dart';
import 'stats_line.dart';
import '../shared/dock_anchor.dart';
import '../shared/menu_sheet.dart';
import 'empty_hero.dart';
import 'preset_seat.dart';
import 'reasoning_row.dart';
import 'sweep_highlight.dart';
import 'timeline_grouping.dart';
import 'todo_panel.dart';
import 'tool_row_model.dart';
import 'turn_status_row.dart';
import '../theme/theme.dart';
import '../shared/state_dot.dart';

// The sidebar widget lives in session_panel.dart; re-exported so existing
// importers of this library keep resolving `SessionPanel` unchanged.
export 'session_panel.dart';

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
    return ref
        .watch(chatUiStateProvider(resolved))
        .when(
          data: (uiState) => ChatScreen(
            uiState: uiState,
            onAction: controller.onAction,
            loadAttachment: controller.loadAttachmentBytes,
            backendId: resolved,
            backendSlices: slices,
            onRefreshModels: controller.refreshModels,
            onSelectBackend: (backendId) => ref
                .read(backendRegistryProvider.future)
                .then(
                  (registry) => registry.onAction(SelectBackend(backendId)),
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
                      (registry) => registry.onAction(SelectBackend(backendId)),
                    ),
              );
              ref
                  .read(chatControllerProvider(backendId))
                  .onAction(SelectSession(sessionId));
            },
            // Web SessionNodeItem session verbs (sidebar long-press):
            // dispatch on whichever backend owns the row.
            dispatchSessionAction: (backendId, action) =>
                ref.read(chatControllerProvider(backendId)).onAction(action),
          ),
          error: (error, _) =>
              Scaffold(body: Center(child: Text(error.toString()))),
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

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  bool _rail = false;
  bool _outline = false;

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

  /// Session-scoped tool pages (web embeds them into conversation context;
  /// mobile pushes them as full routes with the current session preloaded).
  void _openSessionTool(Widget Function(String? sessionId) page) {
    final sessionId = widget.uiState.selectedSessionId;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (scopeContext) {
          final backendId = widget.backendId;
          if (sessionId == null || backendId == null) {
            return page(sessionId);
          }
          return ProviderScope(
            overrides: [
              modelsControllerProvider(backendId).overrideWith(
                (ref) => ModelsController(
                  ref.watch(chatRepositoryProvider(backendId)),
                  initialSessionId: sessionId,
                ),
              ),
              goalControllerProvider(backendId).overrideWith(
                (ref) => GoalController(
                  ref.watch(chatRepositoryProvider(backendId)),
                  initialSessionId: sessionId,
                ),
              ),
              subagentControllerProvider(backendId).overrideWith(
                (ref) => SubagentController(
                  ref.watch(chatRepositoryProvider(backendId)),
                  initialSessionId: sessionId,
                ),
              ),
            ],
            child: page(sessionId),
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
          outline: _outline,
          onToggleOutline: () => setState(() => _outline = !_outline),
          onOpenSubagents: () => _openSessionTool((_) => const SubagentRoute()),
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
        final useTwoPanes = constraints.maxWidth >= 720;
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
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
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
                            outline: _outline,
                            onOpenGoal: () =>
                                _openSessionTool((_) => const GoalRoute()),
                            models: uiState.models,
                            onSelectModel: (selection) =>
                                onAction(SelectModelSeat(selection)),
                            onRefreshModels: widget.onRefreshModels,
                            localState: _effectiveLocalState,
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
                    outline: _outline,
                    onOpenGoal: () =>
                        _openSessionTool((_) => const GoalRoute()),
                    models: uiState.models,
                    onSelectModel: (selection) =>
                        onAction(SelectModelSeat(selection)),
                    onRefreshModels: widget.onRefreshModels,
                    localState: _effectiveLocalState,
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
    required this.onToggleOutline,
    required this.outline,
    super.key,
    this.onOpenSubagents,
    this.compact = false,
  });

  final ChatUiState uiState;
  final void Function(ChatAction) onAction;
  final VoidCallback onToggleOutline;
  final bool outline;

  /// Phone bars carry the two glanceable seats — running jobs and the
  /// outline — and fold the session verbs into an overflow menu; a 400dp
  /// bar cannot spend six icon seats and still name the session.
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        JobListAction(jobs: uiState.jobs),
        IconButton(
          tooltip: l10n.outlineTooltip,
          isSelected: outline,
          onPressed: onToggleOutline,
          icon: const Icon(Icons.view_list_outlined),
          selectedIcon: const Icon(Icons.view_list),
        ),
        if (compact)
          PopupMenuButton<_SessionVerb>(
            tooltip: l10n.sessionMenuTooltip,
            icon: const Icon(Icons.more_vert),
            onSelected: (verb) {
              switch (verb) {
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
enum _SessionVerb { subagents, rename, fork, archive }

/// Sentinel for the turn-status row in the transcript's row list: not a
/// timeline item, only a row the gap math and the builder dispatch on.
const Object _turnStatusSlot = Object();

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    required this.uiState,
    required this.onAction,
    required this.loadAttachment,
    super.key,
    this.outline = false,
    this.onOpenGoal,
    this.models,
    this.onSelectModel,
    this.onRefreshModels,
    this.localState,
  });

  final ChatUiState uiState;
  final void Function(ChatAction) onAction;
  final AttachmentLoader loadAttachment;

  final bool outline;
  final VoidCallback? onOpenGoal;
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
  Set<int> _collapsedTurns = const <int>{};

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
      _collapsedTurns = const <int>{};
      _pinned = true;
      _showJumpToBottom = false;
      _lastFollowSignature = null;
      _lastTrailingUserKey = null;
      _bindSession();
      _scheduleFollow();
      return;
    }
    // The outline is its own skim surface; the jump button's visibility
    // must not linger over it, and the list that remounts when outline
    // closes starts at the top (nothing pins it yet). Re-derive after the
    // frame so whichever body is live reports its true position.
    if (oldWidget.outline != widget.outline) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncJumpToBottomButton();
      });
      return;
    }
    if (widget.outline) return;
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
          ? ':${last.value.text.length}'
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
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
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
      sessionState.readCollapsedTurns().then((turns) {
        if (!mounted || _sessionState != sessionState) return;
        setState(() => _collapsedTurns = turns);
      }),
    );
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
          curve: Curves.easeOutCubic,
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
  /// steering ones the transcript tail below) and the approval that took
  /// over the composer seat.
  List<TimelineItem> get _timelineItems => widget.uiState.timeline
      .where(
        (item) =>
            item is! TimelineQueue &&
            item is! TimelineJobs &&
            item != _pendingApproval,
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

  /// Collapsed-turn set mutation: state and persistence move together.
  void _setCollapsedTurns(Set<int> next) {
    setState(() => _collapsedTurns = next);
    unawaited(_sessionState?.writeCollapsedTurns(next));
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
        (session?.running ?? false) ||
        uiState.timeline.any(
          (item) => item is TimelineMessage && item.value.streaming,
        );
    if (!busy || _pendingApproval != null) return false;
    return !uiState.timeline.any(
      (item) =>
          item is TimelineMessage &&
          item.value.streaming &&
          item.value.role == MessageRole.assistant &&
          item.value.text.isNotEmpty,
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
    final steering = _pendingSteering;
    // The status line rides the tail of the transcript: with nothing
    // visible to be a tail after (a queue-only window), it renders nothing
    // — the queue dock and the composer seat already carry the run.
    final showTurnStatus = _turnStatusVisible(uiState) && items.isNotEmpty;
    // The web's tail order: flow rows, the turn-status line, then the
    // pending steering bubbles (ChatView.tsx:446-460). Steering rides both
    // render modes the same way.
    final rows = <Object>[
      ...items,
      if (showTurnStatus) _turnStatusSlot,
      ...steering,
    ];
    return widget.outline
        ? OutlineTimeline(
            timeline: uiState.timeline,
            collapsedTurns: _collapsedTurns,
            onToggle: (turn) {
              final next = Set<int>.of(_collapsedTurns);
              if (!next.add(turn)) next.remove(turn);
              _setCollapsedTurns(next);
            },
            onAction: widget.onAction,
            loadAttachment: widget.loadAttachment,
            expansion: _sessionState,
            turnStatusVisible: showTurnStatus,
            pendingSteering: steering,
          )
        : ListView.separated(
            controller: _timelineScroll,
            itemCount: rows.length,
            separatorBuilder: (_, index) => SizedBox(
              height: _gapAfter(
                rows[index],
                index + 1 < rows.length ? rows[index + 1] : null,
              ),
            ),
            itemBuilder: (context, index) {
              final row = rows[index];
              if (row is TimelineItem) {
                return TimelineRow(
                  key: ValueKey(timelineKey(row)),
                  item: row,
                  onAction: widget.onAction,
                  loadAttachment: widget.loadAttachment,
                  expansion: _sessionState,
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

  static bool _opensBlock(Object row) =>
      row is TimelineMessage ||
      row is SessionQueueItem ||
      identical(row, _turnStatusSlot);

  /// The jump-to-bottom affordance: a native Material small FAB in the
  /// neutral selector fill (the composer's idle circle convention), so it
  /// never competes with the brand-filled send/stop seat. heroTag is off
  /// so sibling FABs cannot fight over the shared hero on route changes.
  Widget _jumpToBottomFab() {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: AppLocalizations.of(context)!.jumpToBottomTooltip,
      child: FloatingActionButton.small(
        heroTag: null,
        shape: const CircleBorder(),
        backgroundColor: scheme.surfaceContainerLow,
        foregroundColor: scheme.onSurfaceVariant,
        elevation: 2,
        highlightElevation: 3,
        hoverElevation: 3,
        focusElevation: 3,
        disabledElevation: 0,
        onPressed: _jumpToBottom,
        child: const Icon(Icons.arrow_downward, size: 22),
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
            if (uiState.errorMessage case final error?) ...[
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
            ] else if (uiState.commandFailed) ...[
              Text(
                l10n.commandFailed,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
            ],
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
            if (widget.outline && _collapsedTurns.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _setCollapsedTurns(const <int>{}),
                  child: Text(l10n.expandAll),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _timelineBody(uiState, selectedSession),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
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
            if (_pendingApproval == null)
              StatsLine(stats: uiState.sessionStats),
            // Web input-dock order 0: the plan strip before the goal and
            // queue entries. While an approval is pending the ApprovalPanel
            // takes the composer seat, so the todo/goal chrome stands down —
            // the decision moment keeps the transcript room instead of
            // stacking chrome above it. Every strip shares one raised
            // surface; the parts divide with hairlines, never with borders
            // of their own.
            _InputDock(
              key: _dockKey,
              children: [
                if (_pendingApproval == null) ...[
                  TodoPanel(todos: uiState.todos ?? const <TodoItem>[]),
                  GoalBarStrip(
                    goal: uiState.goal,
                    onAction: widget.onAction,
                    onOpen: widget.onOpenGoal,
                  ),
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
                if (_pendingApproval case final approval?)
                  ApprovalPanel(
                    request: approval,
                    command: _commandForApproval(approval),
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
                          contextPressure: uiState.contextPressure,
                          contextBreakdown: uiState.contextBreakdown,
                          onAction: widget.onAction,
                          sessionId: selectedSessionId,
                          sessionState: _sessionState,
                          permissions: uiState.permissions,
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
            borderRadius: BorderRadius.circular(999),
            onTap: widget.locked ? null : widget.onExit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(999),
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

class TimelineRow extends StatelessWidget {
  const TimelineRow({
    required this.item,
    required this.onAction,
    required this.loadAttachment,
    super.key,
    this.expansion,
  });

  final TimelineItem item;
  final void Function(ChatAction) onAction;
  final AttachmentLoader loadAttachment;

  /// Tool-row expansion persistence of the selected session; null keeps
  /// expansion in memory only.
  final ToolExpansionPersistence? expansion;

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
        expansion: expansion,
      ),
      TimelineApprovalRequest() => ApprovalRow(
        requestId: (item as TimelineApprovalRequest).requestId,
        approvalId: (item as TimelineApprovalRequest).approvalId,
        toolName: (item as TimelineApprovalRequest).toolName,
        reason: (item as TimelineApprovalRequest).reason,
        onAction: onAction,
      ),
      TimelineQuestionRequest() => QuestionRow(
        request: item as TimelineQuestionRequest,
        onAction: onAction,
      ),
      TimelineQueue() => const SizedBox.shrink(),
      TimelineJobs() => const SizedBox.shrink(),
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
  });

  final ChatMessage message;
  final AttachmentLoader loadAttachment;

  /// Cuts a new session at this message (host: the end of the turn that
  /// contains it). Null while the message carries no logged position —
  /// a locally composed row has nothing to anchor.
  final VoidCallback? onFork;

  @override
  Widget build(BuildContext context) {
    if (message.role == MessageRole.user) {
      // The reader's own words: a quiet container, right-aligned at 82%,
      // with the tail corner tightened so the bubble points at its author.
      // No action row rides under it — long-press copies, and the reply's
      // row already dates the turn.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 525),
              child: FractionallySizedBox(
                widthFactor: 0.82,
                alignment: Alignment.centerRight,
                child: _UserBubble(text: message.text, onFork: onFork),
              ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.reasoning case final String reasoning
            when reasoning.isNotEmpty)
          ReasoningRow(text: reasoning, running: message.streaming),
        if (message.text.isNotEmpty) MarkdownText(text: message.text),
        for (final ref in message.images)
          AttachmentImageRow(
            sessionId: message.sessionId,
            ref: ref,
            loadAttachment: loadAttachment,
          ),
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
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 525),
        child: FractionallySizedBox(
          widthFactor: 0.82,
          alignment: Alignment.centerRight,
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
        ),
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
      borderRadius: BorderRadius.circular(4),
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
  const ToolCallRow({required this.call, super.key, this.expansion});

  final TimelineToolCall call;

  /// Expansion persistence keyed by this row's [timelineKey] value;
  /// null keeps expansion in memory only.
  final ToolExpansionPersistence? expansion;

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
              controller: running && !MediaQuery.disableAnimationsOf(context)
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
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (model.body case final body?)
                      _ioSection(context, l10n.inputLabel, body, failed: false),
                    if (model.body != null && model.output != null)
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
                  ],
                ),
              ),
          ],
        ),
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

class GoalBarStrip extends StatelessWidget {
  const GoalBarStrip({
    required this.goal,
    required this.onAction,
    super.key,
    this.onOpen,
  });

  final GoalProjection? goal;
  final void Function(ChatAction) onAction;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final projection = goal;
    if (projection == null) return const SizedBox.shrink();
    final snapshot = projection.goal;
    if (snapshot.phase == GoalPhase.complete) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final phaseLabel = switch (snapshot.phase) {
      GoalPhase.active => l10n.chatGoalPhaseActive,
      GoalPhase.paused => l10n.chatGoalPhasePaused,
      GoalPhase.blocked => l10n.chatGoalPhaseBlocked,
      GoalPhase.complete => '',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          border: Border(
            top: BorderSide(color: scheme.outlineVariant),
            left: BorderSide(color: scheme.outlineVariant),
            right: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Text(
              phaseLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: snapshot.phase == GoalPhase.active
                    ? theme.colorScheme.secondary
                    : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                snapshot.objective,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 14,
              tooltip: snapshot.phase == GoalPhase.active
                  ? l10n.pauseGoal
                  : l10n.resumeGoal,
              onPressed: () => onAction(const ToggleGoalPause()),
              icon: Icon(
                snapshot.phase == GoalPhase.active
                    ? Icons.pause_outlined
                    : Icons.play_arrow_outlined,
                color: scheme.onSurfaceVariant,
              ),
            ),
            // Web GoalBar ships the trash action beside pause/resume —
            // deleting works from any phase (`/goal clear` semantics).
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 14,
              tooltip: l10n.clearGoal,
              onPressed: () => onAction(const ClearGoal()),
              icon: Icon(
                Icons.delete_outline,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (onOpen != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 14,
                tooltip: l10n.openGoal,
                onPressed: onOpen,
                icon: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
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
                borderRadius: BorderRadius.circular(8),
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
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                color: scheme.outlineVariant,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                color: scheme.outlineVariant,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
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
        borderRadius: BorderRadius.circular(20),
        boxShadow: kM3ShadowElevation1,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _QuestionCardHeader(question: question, onDismiss: onDismiss),
          Padding(
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
              borderRadius: BorderRadius.circular(6),
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
      borderRadius: BorderRadius.circular(12),
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
            borderRadius: BorderRadius.circular(4),
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
        borderRadius: BorderRadius.circular(6),
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
class _CustomAnswerRow extends StatelessWidget {
  const _CustomAnswerRow({
    required this.question,
    required this.draft,
    required this.onDraftChange,
  });

  final QuestionItem question;
  final QuestionDraft draft;
  final void Function(QuestionDraft) onDraftChange;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = draft.customText.trim().isNotEmpty;
    final controller = TextEditingController(text: draft.customText)
      ..selection = TextSelection.collapsed(offset: draft.customText.length);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      decoration: BoxDecoration(
        color: active ? scheme.surfaceContainerHigh : Colors.transparent,
        border: Border.all(
          color: active ? scheme.outlineVariant : Colors.transparent,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (question.multiSelect)
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
              controller: controller,
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
              onChanged: (text) => onDraftChange(
                QuestionDraft(
                  selected: question.multiSelect
                      ? draft.selected
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
class _CustomAnswerField extends StatelessWidget {
  const _CustomAnswerField({
    required this.question,
    required this.draft,
    required this.onDraftChange,
  });

  final QuestionItem question;
  final QuestionDraft draft;
  final void Function(QuestionDraft) onDraftChange;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = TextEditingController(text: draft.customText)
      ..selection = TextSelection.collapsed(offset: draft.customText.length);
    return TextField(
      controller: controller,
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
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
      ),
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 14,
        height: 24 / 14,
      ),
      onChanged: (text) => onDraftChange(
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
/// interactive hover fill; 36px+ touch target through padding.
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
          child: InkWell(
            onTap: widget.enabled ? widget.onPressed : null,
            child: SizedBox(
              width: 24,
              height: 24,
              child: Icon(
                widget.icon,
                size: 16,
                color: widget.enabled
                    ? scheme.onSurfaceVariant
                    : scheme.outline,
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
        border: Border.all(color: scheme.errorContainer),
        borderRadius: BorderRadius.circular(20),
        boxShadow: kM3ShadowElevation1,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: scheme.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.planReview,
                  style: TextStyle(
                    color: scheme.error,
                    fontSize: 13,
                    height: 18 / 13,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: MarkdownText(text: review.plan),
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
  });

  final bool enabled;
  final bool isSending;
  final bool running;
  final List<PendingImage> pendingImages;
  final ImageLimits imageLimits;
  final List<SkillEntry> skills;
  final void Function(ChatAction) onAction;

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
        }
      }
    });

    // Textarea on top, action row below, primary actions bottom-right.
    // The surface underneath belongs to the dock: drawing a second card
    // here is what made the input edge read as a box inside a box.
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Column(
        // The control row spans the dock so its two clusters can sit at
        // opposite edges; centered controls read as an accident.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _draftController,
            enabled: widget.enabled,
            minLines: 1,
            // Four-line cap: past it the field scrolls internally, so a
            // long draft cannot grow the dock tall enough to squeeze the
            // transcript off-screen on a phone.
            maxLines: 4,
            // Web sends on Enter and newlines on Shift+Enter; soft
            // keyboards have no reliable Shift+Enter, so the keyboard
            // action key inserts the newline and the send button is the
            // only submit gesture.
            textInputAction: TextInputAction.newline,
            onChanged: (_) {
              _draftEdits++;
              _persistDraft();
              setState(() {});
            },
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              // Web swaps the placeholder while the plan target is active
              // (InputBar: planActive ? t('placeholder.plan') : ...).
              hintText: _planTarget
                  ? l10n.planPlaceholder
                  : l10n.messagePlaceholder,
            ),
          ),
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
          SlashSkillCandidates(
            draft: _draftController.text,
            skills: widget.skills,
            enabled: widget.enabled,
            onPick: (name) {
              _draftController.text = '/$name ';
              setState(() {});
            },
          ),
          if (voiceInputState.isRecording)
            VoiceRecordingDock(
              uiState: voiceInputState,
              onCancel: () {
                unawaited(voiceController.cancelRecording());
                _draftController.text = _preRecordingDraft;
                _draftController.selection = TextSelection.collapsed(
                  offset: _draftController.text.length,
                );
                _persistDraft();
                setState(() {});
              },
              onDone: () => unawaited(voiceController.stopRecording()),
            ),
          // Space, not a rule, separates the draft from the control row:
          // the dock already spends one hairline on the plan strip, and a
          // second inside the same card reads as ruling for its own sake.
          const SizedBox(height: 8),
          // Web InputBar controls regrouped for touch: input tools and
          // contextual seats form the left cluster, the occupancy ring
          // and primary control the right. Wrap drops the primary
          // cluster to its own right-aligned run when a narrow phone
          // cannot fit both on one line.
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            runAlignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PlusButton(
                    enabled: widget.enabled,
                    onPickImages: attachAllowed ? _pickImages : null,
                    skills: widget.skills,
                    onPickCommand: (name) {
                      if (hostCommandIsBare('/$name')) {
                        widget.onAction(SendPrompt('/$name'));
                        return;
                      }
                      _draftController.text = '/$name ';
                      setState(() {});
                    },
                  ),
                  const SizedBox(width: 8),
                  VoiceMicButton(
                    enabled: widget.enabled && !voiceInputState.isBusy,
                    isRecording: voiceInputState.isRecording,
                    hasInstalledModels: voiceInputState.hasInstalledModels,
                    onTap: () {
                      if (voiceInputState.isRecording) {
                        unawaited(voiceController.stopRecording());
                      } else {
                        _preRecordingDraft = _draftController.text;
                        unawaited(voiceController.startRecording());
                      }
                    },
                    onOpenSettings: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (ctx) => const AsrModelsRoute(),
                        ),
                      );
                    },
                  ),
                  // Web trailing group: the model seat precedes the
                  // access seat in the tools cluster.
                  if (widget.onSelectModel != null) ...[
                    const SizedBox(width: 12),
                    ModelSelect(
                      models: widget.models,
                      locked: !widget.enabled,
                      onSelect: widget.onSelectModel!,
                      onRefresh: widget.onRefreshModels ?? () {},
                      modelPrefs: widget.modelPrefs,
                    ),
                  ],
                  // Web .modes order: the access seat precedes the plan
                  // pill.
                  if (widget.permissions case final permissions?) ...[
                    const SizedBox(width: 12),
                    PermissionSelectChip(
                      value: permissions,
                      locked: !widget.enabled,
                      onAction: widget.onAction,
                    ),
                  ],
                  // Web conversation.input.plan seat: the warn pill
                  // renders only while the plan target is active and
                  // exits via `/plan off`.
                  PlanChip(
                    plan: widget.plan,
                    locked: !widget.enabled,
                    onExit: () =>
                        widget.onAction(const SendPrompt('/plan off')),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ContextRing(
                    pressure: widget.contextPressure,
                    breakdown: widget.contextBreakdown,
                  ),
                  const SizedBox(width: 12),
                  // Web keeps Stop primary while a turn runs and lets
                  // keyboard Enter queue/steer; soft keyboards have no
                  // reliable Enter-as-send, so an explicit send control
                  // appears beside Stop whenever a draft is ready. Its
                  // delivery mode follows the busy-Enter preference.
                  if (widget.running &&
                      widget.enabled &&
                      !widget.isSending &&
                      _canSend()) ...[
                    _PrimarySendButton(
                      running: false,
                      sending: false,
                      enabled: true,
                      onSend: _send,
                    ),
                    const SizedBox(width: 12),
                  ],
                  _PrimarySendButton(
                    // Web primary: Send, or Stop while the turn runs.
                    running: widget.running,
                    sending: widget.isSending,
                    enabled: widget.enabled && _canSend(),
                    onStop: widget.onStop,
                    onSend: _send,
                  ),
                ],
              ),
            ],
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

  bool _canSend() =>
      _draftController.text.trim().isNotEmpty ||
      widget.pendingImages.isNotEmpty;

  void _send([String? text]) {
    // Web envelope policy: an enter submission carrying images resolves
    // only through a command declaring image acceptance. Refuse before
    // anything is consumed — the draft and the images stay in place and
    // nothing executes.
    if (widget.pendingImages.isNotEmpty) {
      final refused = hostCommandImageRefusal(_draftController.text.trim());
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
    required this.enabled,
    required this.onPick,
    super.key,
  });

  final String draft;
  final List<SkillEntry> skills;
  final bool enabled;
  final void Function(String name) onPick;

  @override
  Widget build(BuildContext context) {
    if (!enabled || !draft.startsWith('/') || draft.contains(' ')) {
      return const SizedBox.shrink();
    }
    final query = draft.substring(1).toLowerCase();
    final candidates = skills
        .where(
          (skill) =>
              query.isEmpty || skill.name.toLowerCase().startsWith(query),
        )
        .take(6)
        .toList();
    if (candidates.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            children: [
              for (final skill in candidates)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => onPick(skill.name),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '/${skill.name}',
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          skill.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
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
          borderRadius: BorderRadius.circular(6),
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
                borderRadius: BorderRadius.circular(8),
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
                borderRadius: BorderRadius.circular(8),
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
    required this.onPickCommand,
  });

  final bool enabled;
  final VoidCallback? onPickImages;
  final List<SkillEntry> skills;
  final void Function(String name) onPickCommand;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: l10n.commandsTooltip,
      onPressed: enabled ? () => _open(context) : null,
      icon: const Icon(Icons.add, size: 22),
      // Native tool control: a standard 40px M3 icon button drawn straight
      // on the dock surface, with the interactive fill kept for hover.
      style: IconButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        disabledForegroundColor: scheme.outline,
        hoverColor: scheme.surfaceContainerHigh,
        shape: const CircleBorder(),
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
        borderRadius: BorderRadius.circular(8),
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
                  borderRadius: BorderRadius.circular(8),
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
    required this.onPickCommand,
    required this.onPickImagesNow,
  });

  final bool canPickImages;
  final List<SkillEntry> skills;
  final void Function(String name) onPickCommand;
  final VoidCallback onPickImagesNow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final commands = hostCommands(l10n);
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
                    borderRadius: BorderRadius.circular(6),
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
      child: FloatingActionButton.small(
        heroTag: null,
        shape: const CircleBorder(),
        backgroundColor: fill,
        foregroundColor: glyph,
        elevation: 2,
        highlightElevation: 3,
        hoverElevation: 3,
        focusElevation: 3,
        disabledElevation: 0,
        onPressed: active ? (running ? onStop : onSend) : null,
        child: running
            // Stop glyph: 10x10 rounded-3 square.
            ? Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: glyph,
                  borderRadius: BorderRadius.circular(3),
                ),
              )
            // Send glyph: the up arrow.
            : const Icon(Icons.arrow_upward, size: 22),
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
  TimelineError(:final id) => 'error:$id',
};

/// Ledger-style outline: turn-group headers collapse their rows on tap.
class OutlineTimeline extends StatelessWidget {
  const OutlineTimeline({
    required this.timeline,
    required this.collapsedTurns,
    required this.onToggle,
    required this.onAction,
    required this.loadAttachment,
    required this.turnStatusVisible,
    super.key,
    this.expansion,
    this.pendingSteering = const <SessionQueueItem>[],
  });

  final List<TimelineItem> timeline;
  final Set<int> collapsedTurns;
  final void Function(int turn) onToggle;
  final void Function(ChatAction) onAction;
  final AttachmentLoader loadAttachment;

  /// Whether the session's turn is running and no louder tail signal (the
  /// streaming caret, the approval seat) owns the tail: the turn-status
  /// line rides after the last turn, visible even under collapsed groups.
  final bool turnStatusVisible;

  /// Tool-row expansion persistence of the selected session.
  final ToolExpansionPersistence? expansion;

  /// Transient steering rows riding the tail after the status line (the
  /// web's tail order), visible even under collapsed turns.
  final List<SessionQueueItem> pendingSteering;

  @override
  Widget build(BuildContext context) {
    // Queued rows ride the composer dock and steering rows the tail
    // below; the timeline body carries neither in its turn groups.
    final groups = groupTimelineByTurn(
      timeline
          .where(
            (item) =>
                item is! TimelineQueue && item is! TimelineApprovalRequest,
          )
          .toList(),
    );
    // One sliver per rendered element — the group header, then its rows.
    // Headers and rows are separate slivers so off-screen elements stay
    // unbuilt: a long outline materializes only the visible turn.
    final elements = <Widget>[];
    for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
      final group = groups[groupIndex];
      final turn = group.turn;
      final collapsed = turn != null && collapsedTurns.contains(turn);
      elements.add(
        SliverToBoxAdapter(
          key: ValueKey('group-${turn ?? groupIndex}'),
          child: TurnGroupHeader(
            turn: turn,
            items: group.items,
            collapsed: collapsed,
            onToggle: onToggle,
          ),
        ),
      );
      if (!collapsed) {
        elements.add(
          // Lazily built rows: only the visible slice is laid out, and a
          // collapsed turn contributes no row slivers at all.
          SliverList.separated(
            itemCount: group.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = group.items[index];
              return TimelineRow(
                key: ValueKey(timelineKey(item)),
                item: item,
                onAction: onAction,
                loadAttachment: loadAttachment,
                expansion: expansion,
              );
            },
          ),
        );
      }
    }
    // The turn-status line rides outside the groups: a collapsed turn
    // still shows its live signal, and the tail speaks once per turn.
    if (turnStatusVisible) {
      elements.add(
        const SliverToBoxAdapter(
          key: ValueKey('turn-status'),
          child: TurnStatusRow(),
        ),
      );
    }
    // Pending steering follows the status line — the web's tail order.
    for (final row in pendingSteering) {
      elements.add(
        SliverToBoxAdapter(
          key: ValueKey('steering:${row.itemId}'),
          child: PendingSteeringRow(text: row.text),
        ),
      );
    }
    // The ledger rhythm is one 8px gap between elements; the last element
    // sits flush at the bottom, matching the previous separator layout.
    final slivers = <Widget>[
      for (var i = 0; i < elements.length; i++)
        SliverPadding(
          padding: EdgeInsets.only(bottom: i == elements.length - 1 ? 0 : 8),
          sliver: elements[i],
        ),
    ];
    return CustomScrollView(slivers: slivers);
  }
}

/// The outline's ledger line for a turn group: the `TurnBoundaryRow`
/// voice — a 14px hairline tick, one line, no frame — as a plain
/// `ListTile`. The transcript is content and chrome wears no border
/// around it (two tones separate content from chrome), so this row takes
/// no outline the way the flow mode's boundary label takes none. The
/// group's run state rides the shared `StateDot` (failed outranks running
/// outranks done); the expanded subtitle echoes the prompt, the collapsed
/// subtitle trades the echo for plain per-tool counts with an error-ink
/// failure tail; the disclosure arrow swaps `chevron_right` ↔
/// `expand_more` the way the subagents page does, with no custom curve.
class TurnGroupHeader extends StatelessWidget {
  const TurnGroupHeader({
    required this.turn,
    required this.items,
    required this.collapsed,
    required this.onToggle,
    super.key,
  });

  final int? turn;
  final List<TimelineItem> items;
  final bool collapsed;
  final void Function(int turn) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final messages = items.whereType<TimelineMessage>().length;
    final tools = items.whereType<TimelineToolCall>().toList();
    final title = switch (turn) {
      null => l10n.beforeFirstTurnHeader(messages),
      final int value => l10n.turnHeader(messages, tools.length, value),
    };

    var failed = 0;
    var running = 0;
    final countByName = <String, int>{};
    for (final tool in tools) {
      countByName[tool.name] = (countByName[tool.name] ?? 0) + 1;
      switch (tool.status) {
        case ToolRunStatus.running:
          running++;
        case ToolRunStatus.completed:
          break;
        case ToolRunStatus.failed:
          failed++;
      }
    }
    final names = countByName.keys.toList()..sort();
    final toolSummary = names.map((n) => '$n ${countByName[n]}').join(' · ');
    final state = failed > 0
        ? StateDotState.error
        : running > 0
        ? StateDotState.ongoing
        : StateDotState.done;

    // The subtitle speaks once. Expanded, it echoes the prompt (the body
    // carries the rest); collapsed, the body is gone and the tool counts
    // are the useful facts — with the failure count kept on its own Text
    // so a crowded summary ellipsizes before the error ink does.
    final echo = promptPreview(items);
    final summaryVisible = collapsed && toolSummary.isNotEmpty;
    final subtitle = switch ((summaryVisible, echo)) {
      (true, _) => toolSummary,
      (false, final String? text) when text != null => '“$text”',
      _ => null,
    };

    final resolvedTurn = turn;
    return IconTheme.merge(
      data: const IconThemeData(size: 18),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        minTileHeight: 30,
        // The same 2px column the tool rows ride (their ExpansionTile's
        // tilePadding lands here as the inner ListTile's contentPadding).
        contentPadding: const EdgeInsets.symmetric(horizontal: 2),
        // The before-first-turn group has no turn to fold: no tap target,
        // no disclosure arrow — the tile is inert the way a boundary
        // notice is.
        onTap: resolvedTurn == null ? null : () => onToggle(resolvedTurn),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 14, height: 1, color: scheme.outlineVariant),
            const SizedBox(width: 10),
            // The dot states a tool fact; with no tools there is none.
            if (tools.isNotEmpty) StateDot(state: state),
          ],
        ),
        title: Text(
          title,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Row(
                children: [
                  Flexible(
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (summaryVisible && failed > 0)
                    Text(
                      ' · ${l10n.turnFailedCount(failed)}',
                      maxLines: 1,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                ],
              ),
        trailing: resolvedTurn == null
            ? null
            : Icon(collapsed ? Icons.chevron_right : Icons.expand_more),
      ),
    );
  }
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
        controller: running && !MediaQuery.disableAnimationsOf(context)
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
  const ContextInjectionRow({required this.injection, super.key});

  final TimelineContextInjection injection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final injection = this.injection;
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
      title: Row(
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
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 4),
          child: MarkdownText(text: injection.text),
        ),
      ],
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
