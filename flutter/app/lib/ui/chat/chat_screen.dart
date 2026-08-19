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
import 'package:domain/model/plan.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/skills.dart';
import 'package:domain/model/jobs.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../di/providers.dart';
import 'chat_ui_state.dart';
import 'markdown/markdown_text.dart';
import 'empty_hero.dart';
import 'reasoning_row.dart';
import 'timeline_grouping.dart';
import '../theme/deepsuite_extension.dart' show dsOf;

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

class ChatScreen extends StatelessWidget {
  const ChatScreen({
    super.key,
    required this.uiState,
    required this.onAction,
    this.loadAttachment = _noAttachment,
  });

  final ChatUiState uiState;
  final void Function(ChatAction) onAction;
  final AttachmentLoader loadAttachment;

  static Future<Uint8List?> _noAttachment(String sessionId, AttachmentRef ref) {
    return Future<Uint8List?>.value();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoPanes = constraints.maxWidth >= 720;
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                ConnectionBanner(uiState: uiState),
                if (useTwoPanes)
                  Expanded(
                    child: Row(
                      children: [
                        SizedBox(
                          width: 320,
                          child: SessionPanel(
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
                            loadAttachment: loadAttachment,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Expanded(
                    child: Column(
                      children: [
                        SizedBox(
                          height: 160,
                          child: SessionPanel(
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
                            loadAttachment: loadAttachment,
                          ),
                        ),
                      ],
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

class SessionPanel extends StatefulWidget {
  const SessionPanel({
    super.key,
    required this.sessions,
    required this.workspaces,
    required this.searchResults,
    required this.selectedSessionId,
    required this.onSelectSession,
    required this.onCreateSession,
    required this.onSearchSessions,
  });

  final List<SessionSummary> sessions;
  final List<WorkspaceSummary> workspaces;
  final List<SessionSearchResult> searchResults;
  final String? selectedSessionId;
  final void Function(String sessionId) onSelectSession;
  final void Function(String? workspaceId) onCreateSession;
  final void Function(String query) onSearchSessions;

  @override
  State<SessionPanel> createState() => _SessionPanelState();
}

class _SessionPanelState extends State<SessionPanel> {
  final TextEditingController _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _showNewSessionDialog() {
    return showDialog<void>(
      context: context,
      builder: (context) => _NewSessionDialog(
        workspaces: widget.workspaces,
        onCreateSession: widget.onCreateSession,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    return ColoredBox(
      color: ds.sidebarFill,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: _showNewSessionDialog,
                child: const Text('New session'),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    decoration: const InputDecoration(
                      hintText: 'Search sessions',
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: widget.onSearchSessions,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: FilledButton(
                    onPressed: _queryController.text.trim().isEmpty
                        ? null
                        : () => widget.onSearchSessions(_queryController.text),
                    child: const Text('Go'),
                  ),
                ),
              ],
            ),
            for (final result in widget.searchResults)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => widget.onSelectSession(result.sessionId),
                  child: Text(
                    'Search: ${result.snippet}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: widget.sessions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final session = widget.sessions[index];
                  final selected = session.id == widget.selectedSessionId;
                  final displayTitle = session.blank
                      ? 'New session'
                      : session.displayTitle;
                  final status = !session.blank && session.running ? ' ●' : '';
                  // Web sidebar nav-item: active fill + brand-accent edge.
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected ? ds.sidebarNavItemActive : null,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: selected
                          ? null
                          : () => widget.onSelectSession(session.id),
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            if (selected)
                              VerticalDivider(
                                thickness: 3,
                                width: 3,
                                color: ds.sidebarNavItemActiveAccent,
                              ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                                child: Text(
                                  displayTitle + status,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewSessionDialog extends StatelessWidget {
  const _NewSessionDialog({
    required this.workspaces,
    required this.onCreateSession,
  });

  final List<WorkspaceSummary> workspaces;
  final void Function(String? workspaceId) onCreateSession;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New session'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (workspaces.isEmpty) ...[
            const Text('No workspaces registered.'),
            Text(
              'Use the Workspaces tab to register a directory first, '
              'or choose Default to create an unaccounted session.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else ...[
            Text(
              'Choose a workspace or keep the default.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final workspace in workspaces)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    onCreateSession(workspace.workspaceId);
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    '${workspace.title} — ${workspace.path}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            onCreateSession(null);
            Navigator.of(context).pop();
          },
          child: const Text('Default'),
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
  });

  final ChatUiState uiState;
  final void Function(ChatAction) onAction;
  final AttachmentLoader loadAttachment;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  PromptMode _promptMode = PromptMode.queue;
  bool _outline = false;
  Set<int> _collapsedTurns = const <int>{};

  @override
  void didUpdateWidget(covariant ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Compose remembered these with selectedSessionId as the key.
    if (oldWidget.uiState.selectedSessionId !=
        widget.uiState.selectedSessionId) {
      _promptMode = PromptMode.queue;
      _outline = false;
      _collapsedTurns = const <int>{};
    }
  }

  Future<void> _showRenameDialog(String sessionId) {
    return showDialog<void>(
      context: context,
      builder: (context) => _RenameSessionDialog(
        onSave: (title) => widget.onAction(RenameSession(sessionId, title)),
      ),
    );
  }

  Future<void> _showArchiveDialog(String sessionId) {
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
              widget.onAction(ArchiveSession(sessionId));
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
          if (selectedSessionId != null) ...[
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => _showRenameDialog(selectedSessionId),
                  child: const Text('Rename'),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: OutlinedButton(
                    onPressed: () =>
                        widget.onAction(ForkSession(selectedSessionId)),
                    child: const Text('Fork'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: OutlinedButton(
                    onPressed: selectedSession?.blank == true
                        ? null
                        : () => _showArchiveDialog(selectedSessionId),
                    child: const Text('Archive'),
                  ),
                ),
                if (uiState.plan != null) ...[
                  const SizedBox(width: 8),
                  PlanChip(plan: uiState.plan!),
                ],
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (uiState.errorMessage case final error?) ...[
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _outline = !_outline),
                child: Text(_outline ? 'Outline: on' : 'Outline: off'),
              ),
              if (_outline && _collapsedTurns.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: OutlinedButton(
                    onPressed: () =>
                        setState(() => _collapsedTurns = const <int>{}),
                    child: const Text('Expand all'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: uiState.timeline.isEmpty
                ? EmptyHero(
                    workspaces: uiState.workspaces,
                    currentWorkspaceLabel: _workspaceLabel(
                      selectedSession?.cwd,
                    ),
                    onPickWorkspace: (workspaceId) =>
                        widget.onAction(CreateSessionInWorkspace(workspaceId)),
                  )
                : _outline
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
                    itemCount: uiState.timeline.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = uiState.timeline[index];
                      return TimelineRow(
                        key: ValueKey(timelineKey(item)),
                        item: item,
                        onAction: widget.onAction,
                        loadAttachment: widget.loadAttachment,
                      );
                    },
                  ),
          ),
          Row(
            children: [
              Expanded(
                child: ComposerBar(
                  enabled: selectedSessionId != null && !uiState.isSending,
                  isSending: uiState.isSending,
                  running: isSessionRunning,
                  mode: _promptMode,
                  onModeChange: (mode) => setState(() => _promptMode = mode),
                  pendingImages: uiState.pendingImages,
                  imageLimits: uiState.imageLimits,
                  skills: uiState.skills,
                  onAction: widget.onAction,
                  onSend: (text) => widget.onAction(
                    SendPrompt(
                      text,
                      mode: isSessionRunning ? _promptMode : PromptMode.queue,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: FilledButton(
                  onPressed: selectedSessionId == null
                      ? null
                      : () => widget.onAction(const CancelTurnAction()),
                  child: const Text('Stop'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Plan collaboration state; `/plan` in the composer toggles it.
class PlanChip extends StatelessWidget {
  const PlanChip({super.key, required this.plan});

  final PlanState plan;

  @override
  Widget build(BuildContext context) {
    final label = plan.pending
        ? 'Plan: switching…'
        : plan.active
        ? 'Plan: active'
        : 'Plan: off';
    final highlight = plan.active || plan.pending;
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: highlight
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
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
      TimelineJobs(:final jobs) => JobsRow(jobs: jobs),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message.role == MessageRole.user ? 'You' : 'Assistant',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
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

class ToolCallRow extends StatelessWidget {
  const ToolCallRow({super.key, required this.call});

  final TimelineToolCall call;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${call.name} ${toolRunStatusLabel(call.status)}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        if (call.arguments case final String arguments)
          Text(arguments, style: Theme.of(context).textTheme.bodySmall),
        if (call.result case final String result)
          Text(result, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

String toolRunStatusLabel(ToolRunStatus status) => switch (status) {
  ToolRunStatus.running => 'running...',
  ToolRunStatus.completed => 'done',
  ToolRunStatus.failed => 'failed',
};

class JobsRow extends StatelessWidget {
  const JobsRow({super.key, required this.jobs});

  final List<JobView> jobs;

  @override
  Widget build(BuildContext context) {
    final bodySmall = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Background jobs',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          for (final job in jobs) ...[
            Text(
              '${job.kind} · ${job.label} · ${job.status.name}',
              style: bodySmall,
            ),
            if (job.detail case final String detail)
              Text(detail, style: bodySmall),
            if (job.finishedAt != null)
              Text('finished @ ${job.finishedAt}', style: bodySmall),
          ],
        ],
      ),
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
    required this.mode,
    required this.onModeChange,
    required this.pendingImages,
    required this.imageLimits,
    required this.skills,
    required this.onAction,
    required this.onSend,
  });

  final bool enabled;
  final bool isSending;
  final bool running;
  final PromptMode mode;
  final void Function(PromptMode) onModeChange;
  final List<PendingImage> pendingImages;
  final ImageLimits imageLimits;
  final List<SkillEntry> skills;
  final void Function(ChatAction) onAction;
  final void Function(String text) onSend;

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
    final effectiveMode = widget.running ? widget.mode : PromptMode.queue;
    final attachAllowed =
        widget.enabled &&
        widget.pendingImages.length < widget.imageLimits.maxImagesPerMessage;
    return Column(
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                'Delivery',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            ModeChip(
              label: 'Queue',
              selected: effectiveMode == PromptMode.queue,
              enabled: widget.enabled,
              onClick: () => widget.onModeChange(PromptMode.queue),
            ),
            ModeChip(
              label: 'Steer',
              selected: effectiveMode == PromptMode.steer,
              enabled: widget.enabled && widget.running,
              onClick: () => widget.onModeChange(PromptMode.steer),
            ),
          ],
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
            IconButton(
              onPressed: attachAllowed ? _pickImages : null,
              icon: const Icon(Icons.add),
              tooltip: 'Attach images',
            ),
            Expanded(
              child: TextField(
                controller: _draftController,
                enabled: widget.enabled,
                onChanged: (_) => setState(() {}),
                onSubmitted: _send,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: effectiveMode == PromptMode.steer
                      ? 'Steer the running turn'
                      : 'Message DeepSeek Harness',
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: FilledButton(
                onPressed: widget.enabled && !widget.isSending && _canSend()
                    ? _send
                    : null,
                child: Text(widget.isSending ? 'Sending' : 'Send'),
              ),
            ),
          ],
        ),
      ],
    );
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
    final groups = groupTimelineByTurn(timeline);
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

/// Context-compaction marker: the summary replaced N older messages.
class CompactionRow extends StatelessWidget {
  const CompactionRow({super.key, required this.shadowedCount});

  final int shadowedCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          '▤ Compacted $shadowedCount messages',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
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
