/// Chat screen — Flutter port of the legacy Compose `ChatScreen.kt`.
///
/// Stateless rows stay stateless; interactive rows (queue editing,
/// question drafts, composer, attachments) own their local state, exactly
/// like the Compose `remember` blocks they replace.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:domain/model/attachment.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/connection_state.dart';
import 'package:domain/model/goal.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/todo.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/skills.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../di/providers.dart';
import 'chat_ui_state.dart';
import 'circle_button.dart';
import 'command_roster.dart';
import 'markdown/markdown_text.dart';
import 'job_list_action.dart';
import 'message_icon_actions.dart';
import 'model_select.dart';
import 'session_panel.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../goal/goal_controller.dart';
import '../models/models_controller.dart';
import '../subagents/subagent_controller.dart';
import 'approval_panel.dart';
import '../goal/goal_screen.dart';
import '../subagents/subagent_screen.dart';

import 'context_ring.dart';
import 'stats_line.dart';
import 'empty_hero.dart';
import 'reasoning_row.dart';
import 'sweep_highlight.dart';
import 'timeline_grouping.dart';
import 'todo_panel.dart';
import 'tool_row_model.dart';
import '../theme/deepsuite_extension.dart'
    show dsOf, kDsShadowLv2, kDsShadowLv3;
import '../theme/deepsuite_tokens.dart' show kDsDuration, kFontFamilyMonospace;

// The sidebar widget lives in session_panel.dart; re-exported so existing
// importers of this library keep resolving `SessionPanel` unchanged.
export 'session_panel.dart';

/// Decodes one durable attachment lazily; returns null on any failure.
typedef AttachmentLoader = Future<Uint8List?> Function(
  String sessionId,
  AttachmentRef ref,
);

class ChatRoute extends ConsumerWidget {
  const ChatRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(chatControllerProvider);
    return ref
        .watch(chatUiStateProvider)
        .when(
          data: (uiState) => ChatScreen(
            uiState: uiState,
            onAction: controller.onAction,
            loadAttachment: controller.loadAttachmentBytes,
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
    super.key,
    required this.uiState,
    required this.onAction,
    this.loadAttachment = _noAttachment,
    this.onRefreshModels,
  });

  final ChatUiState uiState;
  final void Function(ChatAction) onAction;
  final AttachmentLoader loadAttachment;

  /// Composer model seat refresh (re-pulls the session directory).
  final VoidCallback? onRefreshModels;

  static Future<Uint8List?> _noAttachment(String sessionId, AttachmentRef ref) {
    return Future<Uint8List?>.value();
  }

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  bool _rail = false;
  bool _outline = false;

  /// Session-scoped tool pages (web embeds them into conversation context;
  /// mobile pushes them as full routes with the current session preloaded).
  void _openSessionTool(Widget Function(String? sessionId) page) {
    final sessionId = widget.uiState.selectedSessionId;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => sessionId == null
            ? page(null)
            : ProviderScope(
                overrides: [
                  modelsControllerProvider.overrideWith(
                    (ref) => ModelsController(
                      ref.watch(chatRepositoryProvider),
                      initialSessionId: sessionId,
                    ),
                  ),
                  goalControllerProvider.overrideWith(
                    (ref) => GoalController(
                      ref.watch(chatRepositoryProvider),
                      initialSessionId: sessionId,
                    ),
                  ),
                  subagentControllerProvider.overrideWith(
                    (ref) => SubagentController(
                      ref.watch(chatRepositoryProvider),
                      initialSessionId: sessionId,
                    ),
                  ),
                ],
                child: page(sessionId),
              ),
      ),
    );
  }

  PreferredSizeWidget _chatAppBar(
    BuildContext context,
    ChatUiState uiState,
    void Function(ChatAction) onAction, {
    required bool compact,
  }) {
    final sessionId = uiState.selectedSessionId;
    final session = uiState.sessions
        .where((item) => item.id == sessionId)
        .firstOrNull;
    final title = session?.displayTitle ?? 'DeepSeek Harness';
    final connection = uiState.connection;
    final hostVersion = connection.hostDescription?.version ?? '';
    final subtitle = switch (connection.phase) {
      ConnectionPhase.connected =>
        hostVersion.isEmpty ? 'connected' : 'connected $hostVersion',
      ConnectionPhase.connecting => 'connecting',
      ConnectionPhase.reconnecting => 'reconnecting',
      ConnectionPhase.disconnected => 'disconnected',
    };
    return AppBar(
      title: Text(title),
      actions: [
        ChatHeaderActions(
          uiState: uiState,
          onAction: onAction,
          outline: _outline,
          onToggleOutline: () => setState(() => _outline = !_outline),
          onOpenSubagents: () => _openSessionTool((_) => const SubagentRoute()),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(16),
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              subtitle,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
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
                          duration: kDsDuration,
                          curve: Curves.easeInOut,
                          width: _rail ? 56 : 320,
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
          appBar: AppBar(title: const Text('DeepSeek Harness')),
          drawer: Drawer(
            width: 320,
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
              ),
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                ConnectionBanner(uiState: uiState),
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

class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key, required this.uiState});

  final ChatUiState uiState;

  @override
  Widget build(BuildContext context) {
    final connection = uiState.connection;
    final hostVersion = connection.hostDescription?.version ?? '';
    final text = switch (connection.phase) {
      ConnectionPhase.connected => 'connected $hostVersion',
      ConnectionPhase.connecting => 'connecting',
      ConnectionPhase.reconnecting => 'reconnecting',
      ConnectionPhase.disconnected => 'disconnected',
    };
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Icon actions for the chat header (web header-action form).
class ChatHeaderActions extends StatelessWidget {
  const ChatHeaderActions({
    super.key,
    required this.uiState,
    required this.onAction,
    required this.onToggleOutline,
    required this.outline,
    this.onOpenSubagents,
  });

  final ChatUiState uiState;
  final void Function(ChatAction) onAction;
  final VoidCallback onToggleOutline;
  final bool outline;

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
      builder: (context) => AlertDialog(
        title: const Text('Archive session'),
        content: const Text(
          'The session log and its workspace seat are kept; '
          'this row is hidden from all grouping surfaces.',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              onAction(ArchiveSession(sessionId));
              Navigator.of(context).pop();
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = uiState.selectedSessionId;
    if (sessionId == null) {
      return const SizedBox.shrink();
    }
    final selectedSession = uiState.sessions
        .where((session) => session.id == sessionId)
        .firstOrNull;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        JobListAction(jobs: uiState.jobs),
        IconButton(
          tooltip: 'Outline',
          isSelected: outline,
          onPressed: onToggleOutline,
          icon: const Icon(Icons.view_list_outlined),
          selectedIcon: const Icon(Icons.view_list),
        ),
        if (onOpenSubagents != null)
          IconButton(
            tooltip: 'Subagents',
            onPressed: onOpenSubagents,
            icon: const Icon(Icons.account_tree_outlined),
          ),
        IconButton(
          tooltip: 'Rename session',
          onPressed: () => _rename(context, sessionId),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Fork session',
          onPressed: () => onAction(ForkSession(sessionId)),
          icon: const Icon(Icons.call_split_outlined),
        ),
        IconButton(
          tooltip: 'Archive session',
          onPressed: selectedSession?.blank == true
              ? null
              : () => _archive(context, sessionId),
          icon: const Icon(Icons.archive_outlined),
        ),
      ],
    );
  }
}

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.uiState,
    required this.onAction,
    required this.loadAttachment,
    this.outline = false,
    this.onOpenGoal,
    this.models,
    this.onSelectModel,
    this.onRefreshModels,
  });

  final ChatUiState uiState;
  final void Function(ChatAction) onAction;
  final AttachmentLoader loadAttachment;

  final bool outline;
  final VoidCallback? onOpenGoal;
  final SessionModels? models;
  final void Function(ModelSelection selection)? onSelectModel;
  final VoidCallback? onRefreshModels;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  Set<int> _collapsedTurns = const <int>{};

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

  @override
  void initState() {
    super.initState();
    _timelineScroll.addListener(_onTimelineScroll);
    // First mount lands at the bottom like the web's restore-or-bottom.
    _needsInitialJump = true;
    _scheduleFollow();
  }

  @override
  void dispose() {
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
      _collapsedTurns = const <int>{};
      _pinned = true;
      _lastFollowSignature = null;
      _lastTrailingUserKey = null;
      _needsInitialJump = true;
      _scheduleFollow();
      return;
    }
    if (widget.outline) return;
    // Own words must be visible: a new trailing user node force-scrolls
    // (send lives in the composer, so arrival is detected here).
    final trailingUser = _trailingUserKey;
    final appendedUser =
        trailingUser != null && trailingUser != _lastTrailingUserKey;
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
  /// row's identity, and the streaming text length.
  String? _followSignature() {
    final items = _timelineItems;
    if (items.isEmpty) return null;
    final last = items.last;
    final growth = last is TimelineMessage ? ':${last.value.text.length}' : '';
    return '${items.length}:${timelineKey(last)}$growth';
  }

  /// The displayed tail is a user message (web `lastNode.kind === 'user'`).
  String? get _trailingUserKey {
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
  }

  void _scheduleFollow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToBottom();
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
    final jump = _needsInitialJump;
    _needsInitialJump = false;
    // A jump (session switch, first mount) pins without ceremony; growth
    // follows with a short ease so streaming glides instead of snapping.
    _pinned = true;
    _followDepth++;
    try {
      if (jump) {
        _timelineScroll.jumpTo(target);
        return;
      }
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

  /// Timeline without the queue rows (they ride the composer dock) and the
  /// approval that took over the composer seat.
  List<TimelineItem> get _timelineItems => widget.uiState.timeline
      .where(
        (item) =>
            item is! TimelineQueue &&
            item is! TimelineJobs &&
            item != _pendingApproval,
      )
      .toList();

  Widget _timelineBody(ChatUiState uiState, SessionSummary? session) {
    return uiState.timeline.isEmpty
        ? EmptyHero(
            workspaces: uiState.workspaces,
            currentWorkspaceLabel: _workspaceLabel(session?.cwd),
            onPickWorkspace: (workspaceId) =>
                widget.onAction(CreateSessionInWorkspace(workspaceId)),
          )
        : widget.outline
        ? OutlineTimeline(
            timeline: uiState.timeline,
            collapsedTurns: _collapsedTurns,
            onToggle: (turn) => setState(() {
              final next = Set<int>.of(_collapsedTurns);
              if (!next.add(turn)) next.remove(turn);
              _collapsedTurns = next;
            }),
            onAction: widget.onAction,
            loadAttachment: widget.loadAttachment,
          )
        : ListView.separated(
            controller: _timelineScroll,
            itemCount: _timelineItems.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = _timelineItems[index];
              return TimelineRow(
                key: ValueKey(timelineKey(item)),
                item: item,
                onAction: widget.onAction,
                loadAttachment: widget.loadAttachment,
              );
            },
          );
  }

  @override
  Widget build(BuildContext context) {
    final uiState = widget.uiState;
    final selectedSessionId = uiState.selectedSessionId;
    final selectedSession = uiState.sessions
        .where((session) => session.id == selectedSessionId)
        .firstOrNull;
    final isSessionRunning = selectedSession?.running ?? false;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          if (uiState.errorMessage case final error?) ...[
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          if (widget.outline && _collapsedTurns.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    setState(() => _collapsedTurns = const <int>{}),
                child: const Text('Expand all'),
              ),
            ),
          Expanded(child: _timelineBody(uiState, selectedSession)),
          // Web input-dock order 0: the plan strip before the goal and
          // queue entries.
          TodoPanel(todos: uiState.todos ?? const <TodoItem>[]),
          GoalBarStrip(
            goal: uiState.goal,
            onAction: widget.onAction,
            onOpen: widget.onOpenGoal,
          ),
          StatsLine(stats: uiState.sessionStats),
          if (_pendingApproval case final approval?)
            ApprovalPanel(request: approval, onAction: widget.onAction)
          else if (uiState.timeline.whereType<TimelineQueue>().any(
            (dock) => dock.items.isNotEmpty,
          ))
            QueueDock(
              items: [
                for (final dock in uiState.timeline.whereType<TimelineQueue>())
                  ...dock.items,
              ],
              onAction: widget.onAction,
            ),
          if (_pendingApproval == null)
            Row(
              children: [
                Expanded(
                  child: ComposerBar(
                    onStop: selectedSessionId == null
                        ? null
                        : () => widget.onAction(const CancelTurnAction()),
                    enabled: selectedSessionId != null && !uiState.isSending,
                    isSending: uiState.isSending,
                    running: isSessionRunning,
                    plan: uiState.plan,
                    models: widget.models,
                    onSelectModel: widget.onSelectModel,
                    onRefreshModels: widget.onRefreshModels,
                    pendingImages: uiState.pendingImages,
                    imageLimits: uiState.imageLimits,
                    skills: uiState.skills,
                    contextPressure: uiState.contextPressure,
                    contextBreakdown: uiState.contextBreakdown,
                    onAction: widget.onAction,
                    // Web: Enter while running queues; steering rides the
                    // queue dock's per-item action.
                    onSend: (text) => widget.onAction(
                      SendPrompt(text, mode: PromptMode.queue),
                    ),
                  ),
                ),
              ],
            ),
        ],
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
    super.key,
    required this.plan,
    required this.onExit,
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

    final ds = dsOf(context);
    // Web .chip:hover — the label deepens toward warn-primary.
    final label = _hovering ? ds.warnPrimary : ds.warnLabel;
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
                color: ds.warnTertiary,
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
                    // Design literal, not copy: the chip wordmark stays
                    // 'Plan' in every locale.
                    child: const Text('Plan'),
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
    super.key,
    required this.item,
    required this.onAction,
    required this.loadAttachment,
  });

  final TimelineItem item;
  final void Function(ChatAction) onAction;
  final AttachmentLoader loadAttachment;

  @override
  Widget build(BuildContext context) {
    return switch (item) {
      TimelineMessage(:final value) => MessageRow(
        message: value,
        loadAttachment: loadAttachment,
      ),
      TimelineTurnBoundary(:final turn) => TurnBoundaryRow(turn: turn),
      TimelineCompaction(:final shadowedCount) => CompactionRow(
        shadowedCount: shadowedCount,
      ),
      TimelineContextInjection() => ContextInjectionRow(
        injection: item as TimelineContextInjection,
      ),
      TimelineToolCall() => ToolCallRow(call: item as TimelineToolCall),
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
      TimelineQueue(:final items) => QueueRow(items: items, onAction: onAction),
      TimelineJobs() => const SizedBox.shrink(),
      TimelineError(:final message) => SizedBox(
        width: double.infinity,
        child: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    };
  }
}

class MessageRow extends StatelessWidget {
  const MessageRow({
    super.key,
    required this.message,
    required this.loadAttachment,
  });

  final ChatMessage message;
  final AttachmentLoader loadAttachment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ds = dsOf(context);
    if (message.role == MessageRole.user) {
      // figma User_Bubble 659:38813 — right-aligned r22 bubble, 82% cap.
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
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: ds.bubble,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: message.text.isEmpty
                      ? const SizedBox.shrink()
                      : Text(
                          message.text,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurface,
                            height: 24 / 16,
                          ),
                        ),
                ),
              ),
            ),
          ),
          for (final ref in message.images)
            AttachmentImageRow(
              sessionId: message.sessionId,
              ref: ref,
              loadAttachment: loadAttachment,
            ),
          if (message.streaming)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (message.text.isNotEmpty)
            MessageIconActions(
              text: message.text,
              timeEpochMs: message.createdAtEpochMs,
              clockAtStart: true,
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
        if (message.streaming)
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (message.text.isNotEmpty)
          MessageIconActions(
            text: message.text,
            timeEpochMs: message.createdAtEpochMs,
            clockAtStart: false,
          ),
      ],
    );
  }
}

/// Draft-image thumbnail: decode the pending base64 payload once per
/// image, downsampled to icon size. The name chip stays if the bytes
/// fail to decode.
class PendingImageThumbnail extends StatefulWidget {
  const PendingImageThumbnail({super.key, required this.image});

  final PendingImage image;

  @override
  State<PendingImageThumbnail> createState() => _PendingImageThumbnailState();
}

class _PendingImageThumbnailState extends State<PendingImageThumbnail> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    Future<void>(() {
      try {
        final bytes = base64Decode(widget.image.base64Data);
        if (mounted) setState(() => _bytes = bytes);
      } catch (_) {
        // The name chip stays when the bytes fail to decode.
      }
    });
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
    super.key,
    required this.sessionId,
    required this.ref,
    required this.loadAttachment,
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
    widget.loadAttachment(widget.sessionId, widget.ref).then((bytes) {
      if (mounted) setState(() => _bytes = bytes);
    });
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
    final ref = widget.ref;
    final nameSuffix = ref.name == null ? '' : ' · ${ref.name}';
    return Row(
      children: [
        Expanded(
          child: Text(
            'image ${ref.width}×${ref.height} (${ref.bytes} bytes)'
            '$nameSuffix',
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
          child: const Text('Retry'),
        ),
      ],
    );
  }
}

/// Tool summary row — port of the web ToolRow (figma 122:9479): one 24px
/// line [leading state slot] gap6 [title] dot [summary FILL truncate]; the
/// details (arguments + result) expand below on tap. Running rows carry the
/// shared sweep glare.
class ToolCallRow extends StatefulWidget {
  const ToolCallRow({super.key, required this.call});

  final TimelineToolCall call;

  @override
  State<ToolCallRow> createState() => _ToolCallRowState();
}

class _ToolCallRowState extends State<ToolCallRow>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
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
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final call = widget.call;
    final model = deriveToolRowModel(call);
    final running = model.state == ToolRowState.running;
    final failed = model.state == ToolRowState.error;
    final hasDetails = model.body != null || model.output != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: running
              ? 'Running'
              : failed
              ? 'Failed'
              : null,
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: hasDetails
                ? () => setState(() => _expanded = !_expanded)
                : null,
            child: ClipRect(
              child: SweepHighlight(
                controller: running && !MediaQuery.disableAnimationsOf(context)
                    ? _sweep
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      // A product row may carry its own glyph (the todo
                      // checklist); otherwise the shared variant chrome.
                      model.leading != null
                          ? Icon(
                              model.leading,
                              size: 14,
                              color: ds.labelSecondary,
                            )
                          : _leading(context, failed),
                      const SizedBox(width: 6),
                      Text(model.title, style: theme.textTheme.bodyMedium),
                      Container(
                        width: 2,
                        height: 2,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: ds.labelCaption,
                          shape: BoxShape.circle,
                        ),
                      ),
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
                            color: failed
                                ? theme.colorScheme.error
                                : ds.labelTertiary,
                          ),
                        ),
                      ),
                      // The todo parallel-active count rides a
                      // non-shrinking suffix beside the truncatable text.
                      if (model.summarySuffix case final suffix?) ...[
                        const SizedBox(width: 4),
                        Text(
                          suffix,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ds.labelSecondary,
                          ),
                        ),
                      ],
                      if (hasDetails)
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 14,
                          color: ds.labelSecondary,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_expanded && hasDetails)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 2, left: 22),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ds.bgLayer1,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (model.body case final body?)
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: kFontFamilyMonospace,
                    ),
                  ),
                if (model.output case final output?)
                  Text(
                    output,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: failed ? theme.colorScheme.error : null,
                      fontFamily: kFontFamilyMonospace,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _leading(BuildContext context, bool failed) {
    if (failed) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error,
          shape: BoxShape.circle,
        ),
      );
    }
    return Icon(
      Icons.terminal_outlined,
      size: 14,
      color: dsOf(context).labelSecondary,
    );
  }
}

String toolRunStatusLabel(ToolRunStatus status) => switch (status) {
  ToolRunStatus.running => 'running...',
  ToolRunStatus.completed => 'done',
  ToolRunStatus.failed => 'failed',
};

class GoalBarStrip extends StatelessWidget {
  const GoalBarStrip({
    super.key,
    required this.goal,
    required this.onAction,
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
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final phaseLabel = switch (snapshot.phase) {
      GoalPhase.active => 'Active',
      GoalPhase.paused => 'Paused',
      GoalPhase.blocked => 'Blocked',
      GoalPhase.complete => '',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: ds.tip,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          border: Border(
            top: BorderSide(color: ds.divider),
            left: BorderSide(color: ds.divider),
            right: BorderSide(color: ds.divider),
          ),
        ),
        child: Row(
          children: [
            Text(
              phaseLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: snapshot.phase == GoalPhase.active
                    ? theme.colorScheme.secondary
                    : ds.labelSecondary,
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
                  ? 'Pause goal'
                  : 'Resume goal',
              onPressed: () => onAction(const ToggleGoalPause()),
              icon: Icon(
                snapshot.phase == GoalPhase.active
                    ? Icons.pause_outlined
                    : Icons.play_arrow_outlined,
                color: ds.labelSecondary,
              ),
            ),
            // Web GoalBar ships the trash action beside pause/resume —
            // deleting works from any phase (`/goal clear` semantics).
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 14,
              tooltip: 'Clear goal',
              onPressed: () => onAction(const ClearGoal()),
              icon: Icon(
                Icons.delete_outline,
                size: 14,
                color: ds.labelSecondary,
              ),
            ),
            if (onOpen != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 14,
                tooltip: 'Open goal',
                onPressed: onOpen,
                icon: Icon(Icons.chevron_right, color: ds.labelSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

/// Queue dock — port of the web QueueDock (FileContainerText 1:791): a
/// panel attached above the composer card, r12 top corners, tip fill,
/// l1 border (the composer card's own edge closes the bottom).
class QueueDock extends StatelessWidget {
  const QueueDock({super.key, required this.items, required this.onAction});

  final List<SessionQueueItem> items;
  final void Function(ChatAction) onAction;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final ds = dsOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: ds.tip,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(
          top: BorderSide(color: ds.divider),
          left: BorderSide(color: ds.divider),
          right: BorderSide(color: ds.divider),
        ),
      ),
      child: QueueRow(items: items, onAction: onAction),
    );
  }
}

class QueueRow extends StatelessWidget {
  const QueueRow({super.key, required this.items, required this.onAction});

  final List<SessionQueueItem> items;
  final void Function(ChatAction) onAction;

  Future<void> _edit(BuildContext context, SessionQueueItem item) {
    return showDialog<void>(
      context: context,
      builder: (context) => QueueEditDialog(
        itemId: item.itemId,
        initialText: item.text,
        onSave: (edited) => onAction(
          UpdateQueueAction(
            itemId: item.itemId,
            kind: QueueUpdateKind.edit,
            text: edited,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${queuePlacementLabel(item.placement)}: ${item.text}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (item.placement != QueuePlacement.context)
                  Row(
                    children: [
                      if (item.placement == QueuePlacement.queued &&
                          item.text.trim().isNotEmpty)
                        OutlinedButton(
                          onPressed: () => _edit(context, item),
                          child: const Text('Edit'),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: OutlinedButton(
                          onPressed: () => onAction(
                            UpdateQueueAction(
                              itemId: item.itemId,
                              kind: QueueUpdateKind.steer,
                            ),
                          ),
                          child: const Text('Steer'),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: OutlinedButton(
                          onPressed: () => onAction(
                            UpdateQueueAction(
                              itemId: item.itemId,
                              kind: QueueUpdateKind.remove,
                            ),
                          ),
                          child: const Text('Remove'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

String queuePlacementLabel(QueuePlacement placement) => switch (placement) {
  QueuePlacement.queued => 'Queued',
  QueuePlacement.steering => 'Steering',
  QueuePlacement.context => 'Context',
};

/// Queue text edit: blank text never dispatches (Save no-ops), matching
/// the Web composer's non-empty constraint for queue edits.
class QueueEditDialog extends StatefulWidget {
  const QueueEditDialog({
    super.key,
    required this.itemId,
    required this.initialText,
    required this.onSave,
  });

  final String itemId;
  final String initialText;
  final void Function(String text) onSave;

  @override
  State<QueueEditDialog> createState() => _QueueEditDialogState();
}

class _QueueEditDialogState extends State<QueueEditDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit queued message'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        onSubmitted: (_) => Navigator.of(context).pop(),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final text = _controller.text.trim();
            if (text.isNotEmpty) widget.onSave(text);
            Navigator.of(context).pop();
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class ApprovalRow extends StatelessWidget {
  const ApprovalRow({
    super.key,
    required this.requestId,
    required this.approvalId,
    required this.toolName,
    required this.reason,
    required this.onAction,
  });

  final String requestId;
  final String approvalId;
  final String toolName;
  final String? reason;
  final void Function(ChatAction) onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Approve tool: $toolName',
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
              child: const Text('Allow'),
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
                child: const Text('Reject'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class QuestionRow extends StatefulWidget {
  const QuestionRow({super.key, required this.request, required this.onAction});

  final TimelineQuestionRequest request;
  final void Function(ChatAction) onAction;

  @override
  State<QuestionRow> createState() => _QuestionRowState();
}

class _QuestionRowState extends State<QuestionRow> {
  Map<String, QuestionDraft> _drafts = const <String, QuestionDraft>{};

  @override
  void didUpdateWidget(covariant QuestionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Compose remembered drafts keyed by request id.
    if (oldWidget.request.requestId != widget.request.requestId) {
      _drafts = const <String, QuestionDraft>{};
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final answerEnabled =
        request.questions.isNotEmpty &&
        request.questions.every((question) {
          final draft = _drafts[question.id] ?? const QuestionDraft();
          return draft.skipped ||
              draft.selected.isNotEmpty ||
              draft.customText.trim().isNotEmpty;
        });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final question in request.questions)
          QuestionItemEditor(
            question: question,
            draft: _drafts[question.id] ?? const QuestionDraft(),
            onDraftChange: (updated) =>
                setState(() => _drafts = {..._drafts, question.id: updated}),
          ),
        FilledButton(
          onPressed: answerEnabled
              ? () {
                  final answers = [
                    for (final question in request.questions)
                      _answerFor(question, _drafts[question.id]),
                  ];
                  widget.onAction(
                    AnswerQuestionAction(
                      requestId: request.requestId,
                      answers: answers,
                    ),
                  );
                }
              : null,
          child: const Text('Answer'),
        ),
      ],
    );
  }

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

/// Plan-review decision card: the plan body renders as markdown, the
/// approve option is the primary action, and any other option stays
/// secondary. Answers use the same question channel.
class PlanReviewEditor extends StatelessWidget {
  const PlanReviewEditor({
    super.key,
    required this.question,
    required this.draft,
    required this.onDraftChange,
  });

  final QuestionItem question;
  final QuestionDraft draft;
  final void Function(QuestionDraft) onDraftChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final approve = question.intent?.approve;
    final chosen = draft.selected.length == 1 ? draft.selected.first : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question.header ?? 'Plan review',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        Text(question.question, style: theme.textTheme.titleSmall),
        if (question.detail case final String plan)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: dsOf(context).bgLayer1,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: MarkdownText(text: plan),
              ),
            ),
          ),
        Wrap(
          children: [
            for (final option in _orderedOptions(approve))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: option == (approve ?? _firstOption())
                    ? FilledButton(
                        onPressed: () =>
                            onDraftChange(draft.copyWith(selected: {option})),
                        child: Text(chosen == option ? '✓ $option' : option),
                      )
                    : OutlinedButton(
                        onPressed: () =>
                            onDraftChange(draft.copyWith(selected: {option})),
                        child: Text(chosen == option ? '✓ $option' : option),
                      ),
              ),
          ],
        ),
      ],
    );
  }

  String? _firstOption() =>
      question.options.isEmpty ? null : question.options.first;

  List<String> _orderedOptions(String? approve) {
    final approveOption =
        question.options.where((option) => option == approve).firstOrNull ??
        _firstOption();
    return [
      if (approveOption != null) approveOption,
      ...question.options.where((option) => option != approveOption),
    ];
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

class QuestionItemEditor extends StatelessWidget {
  const QuestionItemEditor({
    super.key,
    required this.question,
    required this.draft,
    required this.onDraftChange,
  });

  final QuestionItem question;
  final QuestionDraft draft;
  final void Function(QuestionDraft) onDraftChange;

  @override
  Widget build(BuildContext context) {
    if (question.intent?.kind == 'plan-review') {
      return PlanReviewEditor(
        question: question,
        draft: draft,
        onDraftChange: onDraftChange,
      );
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (question.header case final String header)
          Text(header, style: theme.textTheme.labelLarge),
        Text(question.question, style: theme.textTheme.titleSmall),
        if (question.detail case final String detail)
          Text(detail, style: theme.textTheme.bodySmall),
        if (draft.skipped) ...[
          Text(
            'Skipped',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          OutlinedButton(
            onPressed: () => onDraftChange(
              const QuestionDraft(
                selected: <String>{},
                customText: '',
                skipped: false,
              ),
            ),
            child: const Text('Answer instead'),
          ),
        ] else ...[
          for (final option in question.options)
            if (draft.selected.contains(option))
              FilledButton(
                onPressed: () => onDraftChange(
                  QuestionDraft(
                    selected: _selectedWithout(
                      draft.selected,
                      option,
                      question.multiSelect,
                    ),
                    customText: draft.customText,
                  ),
                ),
                child: Text(option),
              )
            else
              OutlinedButton(
                onPressed: () => onDraftChange(
                  QuestionDraft(
                    selected: _selectedWith(
                      draft.selected,
                      option,
                      question.multiSelect,
                    ),
                    customText: question.multiSelect ? draft.customText : '',
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option),
                    if (question.optionDescriptions[option]
                        case final String description)
                      Text(description, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
          SizedBox(
            width: double.infinity,
            child: TextField(
              controller: TextEditingController(text: draft.customText)
                ..selection = TextSelection.collapsed(
                  offset: draft.customText.length,
                ),
              decoration: const InputDecoration(
                hintText: 'Type your answer',
                isDense: true,
              ),
              onChanged: (text) => onDraftChange(
                QuestionDraft(
                  selected: text.trim().isNotEmpty && !question.multiSelect
                      ? const <String>{}
                      : draft.selected,
                  customText: text,
                ),
              ),
            ),
          ),
          OutlinedButton(
            onPressed: () => onDraftChange(
              const QuestionDraft(
                selected: <String>{},
                customText: '',
                skipped: true,
              ),
            ),
            child: const Text('Skip'),
          ),
        ],
      ],
    );
  }
}

Set<String> _selectedWith(Set<String> current, String option, bool multi) =>
    multi ? {...current, option} : {option};

Set<String> _selectedWithout(Set<String> current, String option, bool multi) =>
    multi ? current.difference({option}) : const <String>{};

class ComposerBar extends StatefulWidget {
  const ComposerBar({
    super.key,
    required this.enabled,
    required this.isSending,
    required this.running,
    required this.pendingImages,
    required this.imageLimits,
    required this.skills,
    required this.onAction,
    required this.onSend,
    this.onStop,
    this.plan,
    this.models,
    this.onSelectModel,
    this.onRefreshModels,
    this.contextPressure,
    this.contextBreakdown,
  });

  final bool enabled;
  final bool isSending;
  final bool running;
  final List<PendingImage> pendingImages;
  final ImageLimits imageLimits;
  final List<SkillEntry> skills;
  final void Function(ChatAction) onAction;
  final void Function(String text) onSend;
  final VoidCallback? onStop;

  /// Plan collaboration state (web input.plan): while the target is plan
  /// mode the placeholder swaps and the warn pill rides the tools row.
  final PlanState? plan;

  /// Composer model seat (web conversation.input.model): the ModelSelect
  /// pill + selection dispatch.
  final SessionModels? models;
  final void Function(ModelSelection selection)? onSelectModel;
  final VoidCallback? onRefreshModels;
  final ContextPressure? contextPressure;

  final ContextBreakdown? contextBreakdown;

  @override
  State<ComposerBar> createState() => _ComposerBarState();
}

class _ComposerBarState extends State<ComposerBar> {
  final TextEditingController _draftController = TextEditingController();

  @override
  void dispose() {
    _draftController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty) return;
    final loaded = <PendingImage>[];
    String? failure;
    for (final file in picked) {
      final name = file.path.split('/').last;
      try {
        final mediaType = file.mimeType ?? guessImageMediaType(file.path);
        if (mediaType == null) {
          failure = 'unknown image type for $name';
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
    final attachAllowed =
        widget.enabled &&
        widget.pendingImages.length < widget.imageLimits.maxImagesPerMessage;
    // figma Input 75:8208 — floating capsule card: textarea on top, action
    // row below, primary actions bottom-right.
    final ds = dsOf(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
      decoration: BoxDecoration(
        color: ds.inputMajor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ds.borderThin),
        boxShadow: kDsShadowLv2,
      ),
      child: Column(
        children: [
          TextField(
            controller: _draftController,
            enabled: widget.enabled,
            minLines: 1,
            maxLines: 5,
            textInputAction: TextInputAction.send,
            onChanged: (_) => setState(() {}),
            onSubmitted: _send,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              // Web swaps the placeholder while the plan target is active
              // (InputBar: planActive ? t('placeholder.plan') : ...).
              hintText: _planTarget
                  ? 'describe your task to generate plan'
                  : 'Message DeepSeek Harness',
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
                              tooltip: 'Remove ${image.name ?? "attachment"}',
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
          Row(
            children: [
              _PlusButton(
                enabled: widget.enabled,
                onPickImages: attachAllowed ? _pickImages : null,
                skills: widget.skills,
                onInsertCommand: (name) {
                  _draftController.text = '/$name ';
                  setState(() {});
                },
              ),
              const SizedBox(width: 12),
              // Web conversation.input.plan seat: the warn pill renders only
              // while the plan target is active and exits via `/plan off`.
              PlanChip(
                plan: widget.plan,
                locked: !widget.enabled,
                onExit: () => widget.onAction(const SendPrompt('/plan off')),
              ),
              const Spacer(),
              // Web trailing group (gap 12): model seat, context ring,
              // primary control.
              if (widget.onSelectModel != null) ...[
                ModelSelect(
                  models: widget.models,
                  locked: !widget.enabled,
                  onSelect: widget.onSelectModel!,
                  onRefresh: widget.onRefreshModels ?? () {},
                ),
                const SizedBox(width: 12),
              ],
              ContextRing(
                pressure: widget.contextPressure,
                breakdown: widget.contextBreakdown,
              ),
              const SizedBox(width: 12),
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
    widget.onSend(_draftController.text);
    _draftController.clear();
    setState(() {});
  }
}

/// `/` composer source: while the draft is a single slash token, offer
/// the session's skill catalog filtered by prefix; picking lands the
/// literal `/name ` text, matching the Web plain-text-reference decision.
class SlashSkillCandidates extends StatelessWidget {
  const SlashSkillCandidates({
    super.key,
    required this.draft,
    required this.skills,
    required this.enabled,
    required this.onPick,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: dsOf(context).bgLayer1,
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
    super.key,
    required this.running,
    required this.enabled,
    required this.effectiveMode,
    required this.onModeChange,
  });

  final bool running;
  final bool enabled;
  final PromptMode effectiveMode;
  final void Function(PromptMode) onModeChange;

  @override
  Widget build(BuildContext context) {
    final label = effectiveMode == PromptMode.steer ? 'Steer' : 'Queue';
    return PopupMenuButton<PromptMode>(
      tooltip: 'Delivery',
      enabled: enabled,
      initialValue: effectiveMode,
      onSelected: onModeChange,
      itemBuilder: (context) => [
        const PopupMenuItem(value: PromptMode.queue, child: Text('Queue')),
        PopupMenuItem(
          value: PromptMode.steer,
          enabled: running,
          child: const Text('Steer'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const Icon(Icons.arrow_drop_down, size: 16),
          ],
        ),
      ),
    );
  }
}

/// The composer's ➕ — web form (InputBar `.add`): a 28px circle on the
/// selector fill with a 14px plus glyph. It opens the slash-command menu
/// (web `toggleCommandMenu` seeds the '/' trigger with an empty query):
/// a menu-surface bottom sheet listing the host command roster and the
/// session's skills, with the mobile-only Attach-images row at the tail
/// (web relies on paste/drop, which mobile keyboards cannot do).
class _PlusButton extends StatelessWidget {
  const _PlusButton({
    required this.enabled,
    required this.onPickImages,
    required this.skills,
    required this.onInsertCommand,
  });

  final bool enabled;
  final VoidCallback? onPickImages;
  final List<SkillEntry> skills;
  final void Function(String name) onInsertCommand;

  @override
  Widget build(BuildContext context) {
    return DsCircleButton(
      tooltip: 'Commands',
      enabled: enabled,
      onTap: () => _open(context),
      // Web .add: the glyph rides --dsw-alias-label-primary.
      child: Icon(
        Icons.add,
        size: 14,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  Future<void> _open(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Menu-surface sheet (PopupSelectView .card): menu fill, 12px radius,
      // lv3 elevation, 4px inner padding.
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: dsOf(sheetContext).menu,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: dsOf(sheetContext).borderInverted),
            boxShadow: kDsShadowLv3,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 440),
            child: _CommandSheet(
              canPickImages: onPickImages != null,
              skills: skills,
              onInsertCommand: (name) {
                Navigator.of(sheetContext).pop();
                onInsertCommand(name);
              },
              onPickImagesNow: () {
                Navigator.of(sheetContext).pop();
                onPickImages?.call();
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Web PopupSelectView body: search input on top, filtered option rows
/// below (13px label-primary + 12px label-tertiary detail, check mark on
/// the active row), status line when empty. The roster is the real
/// command set — host slash commands first (web slash-menu sources),
/// then the session's skills — with the mobile-only Attach-images row
/// demoted to the tail (web relies on paste/drop).
class _CommandSheet extends StatefulWidget {
  const _CommandSheet({
    required this.canPickImages,
    required this.skills,
    required this.onInsertCommand,
    required this.onPickImagesNow,
  });

  final bool canPickImages;
  final List<SkillEntry> skills;
  final void Function(String name) onInsertCommand;
  final VoidCallback onPickImagesNow;

  @override
  State<_CommandSheet> createState() => _CommandSheetState();
}

class _CommandSheetState extends State<_CommandSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final query = _search.trim().toLowerCase();
    bool matches(String label, String detail) =>
        query.isEmpty ||
        label.toLowerCase().contains(query) ||
        detail.toLowerCase().contains(query);
    final commands = kHostCommands
        .where((command) => matches(command.name, command.description))
        .toList();
    final skills = widget.skills
        .where((skill) => matches(skill.name, skill.description))
        .toList();
    final showAttach = query.isEmpty || 'attach images'.contains(query);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The web search box (PopupSelectView .search): hairline border,
        // no focus accent — focus never repaints it.
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 4),
          child: TextField(
            autofocus: true,
            onChanged: (value) => setState(() => _search = value),
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search commands',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: ds.borderInverted),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: ds.borderInverted),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: ds.borderInverted),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
            ),
          ),
        ),
        Flexible(
          child: (commands.isEmpty && skills.isEmpty && !showAttach)
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  // PopupSelectView .status: the empty roster line.
                  child: Text(
                    'No matching commands',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: ds.labelTertiary),
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final command in commands)
                      _CommandRow(
                        label: '/${command.name}',
                        detail: command.hint ?? command.description,
                        onTap: () => widget.onInsertCommand(command.name),
                      ),
                    for (final skill in skills)
                      _CommandRow(
                        label: '/${skill.name}',
                        detail: skill.description.isEmpty
                            ? null
                            : skill.description,
                        onTap: () => widget.onInsertCommand(skill.name),
                      ),
                    // Mobile-only tail row: image intake (web uses
                    // paste/drop) — demoted below the command roster.
                    if (showAttach)
                      _CommandRow(
                        label: 'Attach images',
                        detail: 'Pick from gallery',
                        enabled: widget.canPickImages,
                        onTap: widget.onPickImagesNow,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// One option row (PopupSelectView .row): 6x8 padding, 8px radius, hover
/// fill, ellipsized label + trailing detail.
class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.label,
    required this.onTap,
    this.detail,
    this.enabled = true,
  });

  final String label;
  final String? detail;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: enabled
                        ? Theme.of(context).colorScheme.onSurface
                        : ds.labelTertiary,
                  ),
                ),
              ),
              if (detail case final text?) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(fontSize: 12, color: ds.labelTertiary),
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

/// Primary control, commercial-app form: a 34px circle that stays NEUTRAL
/// (selector fill, tertiary glyph) while the draft is empty — no idle
/// blue — and takes the info fill with a static-white glyph only when
/// actionable: the up arrow while sendable, the stop square while the
/// turn runs.
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
    final ds = dsOf(context);
    final active = running
        ? onStop != null
        : enabled && !sending && onSend != null;
    final fill = active ? ds.buttonInfoFill : ds.specificSelector;
    final glyph = active ? Colors.white : ds.labelTertiary;
    return Tooltip(
      message: running
          ? 'Stop'
          : sending
          ? 'Sending'
          : 'Send',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: active ? (running ? onStop : onSend) : null,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
            alignment: Alignment.center,
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
                // Send glyph: the 16px up arrow.
                : Icon(Icons.arrow_upward, size: 16, color: glyph),
          ),
        ),
      ),
    );
  }
}

class ModeChip extends StatelessWidget {
  const ModeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onClick,
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
    super.key,
    required this.timeline,
    required this.collapsedTurns,
    required this.onToggle,
    required this.onAction,
    required this.loadAttachment,
  });

  final List<TimelineItem> timeline;
  final Set<int> collapsedTurns;
  final void Function(int turn) onToggle;
  final void Function(ChatAction) onAction;
  final AttachmentLoader loadAttachment;

  @override
  Widget build(BuildContext context) {
    // Queue rides the composer dock, not the timeline body.
    final groups = groupTimelineByTurn(
      timeline
          .where(
            (item) =>
                item is! TimelineQueue && item is! TimelineApprovalRequest,
          )
          .toList(),
    );
    final slivers = <Widget>[];
    for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
      final group = groups[groupIndex];
      final turn = group.turn;
      final collapsed = turn != null && collapsedTurns.contains(turn);
      slivers.add(
        TurnGroupHeader(
          key: ValueKey('group-${turn ?? groupIndex}'),
          turn: turn,
          items: group.items,
          collapsed: collapsed,
          onToggle: onToggle,
        ),
      );
      if (!collapsed) {
        slivers.addAll([
          for (final item in group.items)
            TimelineRow(
              key: ValueKey(timelineKey(item)),
              item: item,
              onAction: onAction,
              loadAttachment: loadAttachment,
            ),
        ]);
      }
    }
    return ListView.separated(
      itemCount: slivers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => slivers[index],
    );
  }
}

class TurnGroupHeader extends StatelessWidget {
  const TurnGroupHeader({
    super.key,
    required this.turn,
    required this.items,
    required this.collapsed,
    required this.onToggle,
  });

  final int? turn;
  final List<TimelineItem> items;
  final bool collapsed;
  final void Function(int turn) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messages = items.whereType<TimelineMessage>().length;
    final tools = items.whereType<TimelineToolCall>().toList();
    final label = turn == null
        ? 'Before first turn · $messages messages'
        : 'Turn $turn · $messages messages · ${tools.length} tools';

    final statusByName = <String, List<ToolRunStatus>>{};
    for (final tool in tools) {
      statusByName.putIfAbsent(tool.name, () => []).add(tool.status);
    }
    final names = statusByName.keys.toList()..sort();
    final toolSummary = names
        .map((name) {
          final statuses = statusByName[name]!;
          final completed = statuses
              .where((status) => status == ToolRunStatus.completed)
              .length;
          final failed = statuses
              .where((status) => status == ToolRunStatus.failed)
              .length;
          final running = statuses
              .where((status) => status == ToolRunStatus.running)
              .length;
          final buffer = StringBuffer('$name $completed✓');
          if (failed > 0) buffer.write(' $failed✗');
          if (running > 0) buffer.write(' $running…');
          return buffer.toString();
        })
        .join(' · ');

    final resolvedTurn = turn;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: resolvedTurn == null ? null : () => onToggle(resolvedTurn),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(collapsed ? '▸ $label' : '▾ $label'),
            if (promptPreview(items) case final String prompt)
              Text(
                '“$prompt”',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (toolSummary.isNotEmpty)
              Text(
                toolSummary,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: collapsed ? 2 : 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

/// Ledger-style turn divider, the first slice of the Web trajectory
/// grouping.
class TurnBoundaryRow extends StatelessWidget {
  const TurnBoundaryRow({super.key, required this.turn});

  final int turn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Expanded(child: Divider(height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Turn $turn',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Expanded(child: Divider(height: 1)),
        ],
      ),
    );
  }
}

/// Context-compaction marker — port of the web CompactionItem: one dim
/// 24px row (leading context icon + title + count), a boundary notice
/// rather than conversation content.
class CompactionRow extends StatelessWidget {
  const CompactionRow({super.key, required this.shadowedCount});

  final int shadowedCount;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    return SizedBox(
      height: 24,
      child: Row(
        children: [
          Icon(Icons.layers_outlined, size: 14, color: ds.labelSecondary),
          const SizedBox(width: 6),
          Text(
            'Context compacted',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: ds.labelPrimaryDimmed),
          ),
          Container(
            width: 2,
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: ds.labelCaption,
              shape: BoxShape.circle,
            ),
          ),
          Flexible(
            child: Text(
              'Compacted $shadowedCount history items',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: ds.labelTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Logged non-user context (web ContextInjectionRow): a disclosure row in
/// the Tool-call chrome — the header names the role this context plays
/// ("Context injection", or "Recall" for cross-session material) beside
/// the durable producer the source identifies; the expanded body carries
/// the injected content.
class ContextInjectionRow extends StatefulWidget {
  const ContextInjectionRow({super.key, required this.injection});

  final TimelineContextInjection injection;

  @override
  State<ContextInjectionRow> createState() => _ContextInjectionRowState();
}

class _ContextInjectionRowState extends State<ContextInjectionRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final injection = widget.injection;
    final hasBody = injection.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: hasBody ? () => setState(() => _expanded = !_expanded) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(Icons.travel_explore, size: 14, color: ds.labelSecondary),
                const SizedBox(width: 6),
                Text(
                  injection.isRecall ? 'Recall' : 'Context injection',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ds.labelPrimaryDimmed,
                  ),
                ),
                if (injection.producerLabel case final label?) ...[
                  Container(
                    width: 2,
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: ds.labelCaption,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ds.labelSecondary,
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ds.labelTertiary,
                      ),
                    ),
                  ),
                ],
                if (hasBody)
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 14,
                    color: ds.labelSecondary,
                  ),
              ],
            ),
          ),
        ),
        if (_expanded && hasBody)
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 2, bottom: 4),
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
    return AlertDialog(
      title: const Text('Rename session'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        onSubmitted: (_) => Navigator.of(context).pop(),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            widget.onSave(_controller.text);
            Navigator.of(context).pop();
          },
          child: const Text('Save'),
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
