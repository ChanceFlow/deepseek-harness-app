/// Subagents screen — Flutter port of the legacy SubagentScreen.kt.
library;

import 'package:domain/model/subagent.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import 'subagent_ui_state.dart';

class SubagentRoute extends ConsumerWidget {
  const SubagentRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(subagentControllerProvider);
    return StreamBuilder<SubagentUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder: (context, snapshot) {
        final uiState = snapshot.data ?? const SubagentUiState();
        return SubagentScreen(
            uiState: uiState, onAction: controller.onAction);
      },
    );
  }
}

class SubagentScreen extends StatefulWidget {
  const SubagentScreen({
    super.key,
    required this.uiState,
    required this.onAction,
  });

  final SubagentUiState uiState;
  final void Function(SubagentAction) onAction;

  @override
  State<SubagentScreen> createState() => _SubagentScreenState();
}

class _SubagentScreenState extends State<SubagentScreen> {
  final TextEditingController _draftController = TextEditingController();

  @override
  void dispose() {
    _draftController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiState = widget.uiState;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Subagents', style: theme.textTheme.titleLarge),
              if (uiState.errorMessage case final error?)
                Text(error,
                    style: TextStyle(color: theme.colorScheme.error)),
              Text('Parent session', style: theme.textTheme.labelLarge),
              SizedBox(
                height: 150,
                child: ListView(
                  children: [
                    for (final session in uiState.sessions)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: session.id == uiState.selectedParentId
                              ? null
                              : () =>
                                  widget.onAction(SelectParent(session.id)),
                          child: Text(session.displayTitle),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('Children', style: theme.textTheme.labelLarge),
              if (!uiState.catalog.parentAvailable)
                Text('Parent is not available for continuation.',
                    style: theme.textTheme.bodySmall),
              Expanded(
                flex: 70,
                child: ListView(
                  children: [
                    for (final entry in uiState.catalog.entries)
                      SubagentEntryRow(
                        key: ValueKey(entry.id),
                        entry: entry,
                        selected: entry.id == uiState.selectedChildId,
                        onOpen: () =>
                            widget.onAction(OpenChild(entry.id)),
                        onInterrupt: () =>
                            widget.onAction(InterruptSubagent(entry.id)),
                      ),
                  ],
                ),
              ),
              if (uiState.selectedChildId != null) ...[
                const SizedBox(height: 12),
                Text('Child timeline', style: theme.textTheme.labelLarge),
                Expanded(
                  flex: 35,
                  child: ChildTimeline(timeline: uiState.childTimeline),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _draftController,
                        enabled: !uiState.isSendingChild,
                        decoration: const InputDecoration(
                          hintText: 'Message selected subagent',
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: FilledButton(
                        onPressed:
                            _draftController.text.trim().isNotEmpty &&
                                    !uiState.isSendingChild
                                ? () {
                                    widget.onAction(SendSubagentPrompt(
                                        _draftController.text));
                                    _draftController.clear();
                                    setState(() {});
                                  }
                                : null,
                        child: Text(
                            uiState.isSendingChild ? 'Sending' : 'Send'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SubagentEntryRow extends StatelessWidget {
  const SubagentEntryRow({
    super.key,
    required this.entry,
    required this.selected,
    required this.onOpen,
    required this.onInterrupt,
  });

  final SubagentEntry entry;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onInterrupt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'child ${entry.id.substring(0, entry.id.length >= 8 ? 8 : entry.id.length)}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (entry.kind == 'child' && entry.mode == 'continuable') ...[
                FilledButton(
                  onPressed: selected ? null : onOpen,
                  child: const Text('Open'),
                ),
                if (entry.activity == 'running')
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: FilledButton(
                      onPressed: onInterrupt,
                      child: const Text('Stop'),
                    ),
                  ),
              ],
            ],
          ),
          Text(
            'kind=${entry.kind} mode=${entry.mode ?? ''} '
            'activity=${entry.activity ?? ''} children=${entry.hasChildren}',
            style: theme.textTheme.bodySmall,
          ),
          if (entry.label case final String label?)
            Text('label=$label', style: theme.textTheme.bodySmall),
          if (entry.reason case final String reason?)
            Text(reason, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class ChildTimeline extends StatelessWidget {
  const ChildTimeline({super.key, required this.timeline});

  final List<TimelineItem> timeline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subdued = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return ListView(
      children: [
        for (final item in timeline)
          switch (item) {
            TimelineMessage(:final value) => SizedBox(
                width: double.infinity,
                child: Text('${value.role.name}: ${value.text}'),
              ),
            TimelineTurnBoundary(:final turn) => SizedBox(
                width: double.infinity,
                child: Text(
                  'Turn $turn',
                  style: theme.textTheme.labelSmall?.merge(subdued),
                ),
              ),
            TimelineCompaction(:final shadowedCount) => SizedBox(
                width: double.infinity,
                child: Text(
                  '▤ Compacted $shadowedCount messages',
                  style: theme.textTheme.labelSmall?.merge(subdued),
                ),
              ),
            TimelineToolCall() => SizedBox(
                width: double.infinity,
                child: Text(
                  'Tool ${item.name}: ${item.result ?? item.arguments ?? ''}',
                ),
              ),
            TimelineApprovalRequest(:final toolName) => SizedBox(
                width: double.infinity,
                child: Text('Approval: $toolName'),
              ),
            TimelineQuestionRequest(:final questions) => SizedBox(
                width: double.infinity,
                child: Text(
                    'Question: ${questions.isEmpty ? '' : questions.first.question}'),
              ),
            TimelineQueue(:final items) => SizedBox(
                width: double.infinity,
                child: Text('Queue: ${items.length}'),
              ),
            TimelineJobs(:final jobs) => SizedBox(
                width: double.infinity,
                child: Text('Jobs: ${jobs.length}'),
              ),
            TimelineError(:final message) => SizedBox(
                width: double.infinity,
                child: Text(
                  message,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          },
      ],
    );
  }
}
