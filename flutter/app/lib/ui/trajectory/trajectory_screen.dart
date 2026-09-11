/// Trajectory screen: the turn-aware event ledger.
///
/// Port of the reference web client's `ui-trajectory` ledger to the phone
/// (`reference/.../ui-trajectory/src/client/TrajectoryTable.tsx`). The
/// reference shows a `Turn {n}` rule, `Step {n}` markers, selectable
/// User/Assistant/Tool/Sub-tool records, a per-record inspector of token
/// usage and timing, local search over the loaded window, and older-history
/// paging. Everything here is assembled from the `domain` timeline the
/// adapter already folds — the session log is the only source, and a figure
/// the log does not carry is stated as unavailable, never estimated.
///
/// Density decisions (360dp is the design width):
/// - 12sp content on the smallest M3 text roles; scan lines stay one line
///   and ellipsize rather than wrapping, so a row's height is fixed and the
///   turn/step structure stays visible while scrolling.
/// - Structure is carried by a 2dp primary rule at a turn and a
///   `Step {n}` chip at a step, not by cards or padding — rules are cheaper
///   than whitespace on a phone.
/// - A nested code-dispatch call indents one 16dp step per depth, over a
///   hairline `outlineVariant` rule, so parentage reads without a tree
///   widget.
/// - The inspector is a modal sheet (a phone cannot show the reference's
///   side-by-side split), and it holds the long payloads the scan lines
///   deliberately elide.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/token_usage.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'trajectory_ui_state.dart';

/// Row height budget: one 12sp line plus 6dp vertical padding.
const double _kRecordVerticalPadding = 4;
const double _kKindColumnWidth = 22;

class TrajectoryScreen extends StatefulWidget {
  const TrajectoryScreen({
    required this.uiState,
    required this.onAction,
    super.key,
  });

  final TrajectoryUiState uiState;
  final void Function(TrajectoryAction) onAction;

  @override
  State<TrajectoryScreen> createState() => _TrajectoryScreenState();
}

class _TrajectoryScreenState extends State<TrajectoryScreen> {
  late final TextEditingController _search = TextEditingController(
    text: widget.uiState.searchQuery,
  );

  /// The selection whose inspector is already open, so a rebuild after the
  /// sheet opens does not stack a second one.
  String? _inspectedId;

  @override
  void didUpdateWidget(TrajectoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The controller owns the query (a filter is state, not a draft), so an
    // external clear must reach the field back.
    if (widget.uiState.searchQuery != _search.text) {
      _search.text = widget.uiState.searchQuery;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final state = widget.uiState;
    final scheme = theme.colorScheme;
    // Selection opens the inspector as its own modal route, so the ledger
    // stays visible underneath and dismissal needs no screen state.
    final selected = state.selectedRecord;
    if (state.selectedId != _inspectedId && selected != null) {
      _inspectedId = state.selectedId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _inspectedId != state.selectedId) return;
        unawaited(
          showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            constraints: const BoxConstraints(maxHeight: 560),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(kShapeSheet),
              ),
            ),
            builder: (sheetContext) => TrajectoryInspector(record: selected),
          ),
        );
      });
    } else if (state.selectedId == null && _inspectedId != null) {
      _inspectedId = null;
    }
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surfaceContainer,
        title: Text(
          state.sessionTitle ?? l10n.trajectoryTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _search,
              onChanged: (value) => widget.onAction(SetTrajectorySearch(value)),
              textInputAction: TextInputAction.search,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                hintText: l10n.trajectorySearchHint,
                suffixIcon: state.hasSearch
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: l10n.trajectorySearchClear,
                        onPressed: () {
                          _search.clear();
                          widget.onAction(const SetTrajectorySearch(''));
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(kShapeChip),
                ),
              ),
            ),
          ),
        ),
        actions: [
          if (state.hasSearch)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  l10n.trajectorySearchMatches(
                    state.matchCount,
                    state.totalRecords,
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _body(context, l10n, state),
    );
  }

  Widget _body(
    BuildContext context,
    AppLocalizations l10n,
    TrajectoryUiState state,
  ) {
    if (state.rows.isEmpty) {
      return _emptyState(context, l10n, state);
    }
    // The older-history control is a list item, so the whole surface shares
    // one scroll position and keeps the ledger the tallest thing on screen.
    final leading =
        state.hasMoreOlder || state.isLoadingOlder || state.errorMessage != null
        ? 1
        : 0;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: state.rows.length + leading,
      itemBuilder: (context, index) {
        if (leading == 1 && index == 0) {
          return _olderHistoryRow(context, l10n, state);
        }
        final row = state.rows[index - leading];
        return switch (row) {
          TrajectoryTurnRow() => _TurnRule(row: row),
          TrajectoryStepRow() => _StepMarker(row: row),
          TrajectoryRecordRow() => _RecordRow(
            key: ValueKey<String>('trajectory-row-${row.record.id}'),
            record: row.record,
            selected: row.record.id == state.selectedId,
            onAction: widget.onAction,
          ),
        };
      },
    );
  }

  Widget _olderHistoryRow(
    BuildContext context,
    AppLocalizations l10n,
    TrajectoryUiState state,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final error = state.errorMessage;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: state.isLoadingOlder
                ? null
                : () => widget.onAction(const LoadOlderTrajectory()),
            icon: state.isLoadingOlder
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.history, size: 16),
            label: Text(
              state.isLoadingOlder
                  ? l10n.trajectoryLoadingOlder
                  : l10n.trajectoryLoadOlder,
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.trajectoryLoadOlderFailed,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyState(
    BuildContext context,
    AppLocalizations l10n,
    TrajectoryUiState state,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return switch (state.emptyState) {
      TrajectoryEmptyState.loading => const Center(
        child: CircularProgressIndicator(),
      ),
      TrajectoryEmptyState.noSearchMatches => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            l10n.trajectoryNoMatches,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      TrajectoryEmptyState.noRecords => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.route_outlined,
                size: 40,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.trajectoryEmpty,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    };
  }
}

/// Thick rule at a turn boundary: the ledger's strongest structural mark.
class _TurnRule extends StatelessWidget {
  const _TurnRule({required this.row});

  final TrajectoryTurnRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        // A 2dp primary rule is the decision that a new turn begins here;
        // space alone would read as an ordinary gap between records.
        Container(height: 2, color: scheme.primary),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  row.turn == null
                      ? l10n.trajectoryBeforeFirstTurn
                      : l10n.trajectoryTurnLabel(row.turn!),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Text(
                l10n.trajectoryTurnSummary(row.recordCount, row.toolCount),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (row.usage case final usage?)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Text(
              _usageSummary(l10n, usage),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// Inline marker opening a step inside a turn.
class _StepMarker extends StatelessWidget {
  const _StepMarker({required this.row});

  final TrajectoryStepRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Row(
        children: [
          Icon(Icons.subdirectory_arrow_right, size: 12, color: scheme.primary),
          const SizedBox(width: 4),
          Text(
            l10n.trajectoryStepLabel(row.step),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.trajectoryStepRecordCount(row.recordCount),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One selectable record row (and, when expanded, its nested calls).
class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.record,
    required this.selected,
    required this.onAction,
    super.key,
  });

  final TrajectoryRecord record;
  final bool selected;
  final void Function(TrajectoryAction) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final scheme = theme.colorScheme;
    final kindLabel = _kindLabel(l10n, record.kind);
    return Material(
      color: selected
          ? scheme.primaryContainer
          : (record.depth > 0 ? scheme.surfaceContainerLow : scheme.surface),
      child: InkWell(
        onTap: () => onAction(SelectTrajectoryRecord(record.id)),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            12 + record.depth * 16,
            _kRecordVerticalPadding,
            12,
            _kRecordVerticalPadding,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (record.depth > 0)
                const SizedBox(
                  width: 8,
                  child: Divider(height: 1, thickness: 1),
                ),
              SizedBox(
                width: _kKindColumnWidth,
                child: record.hasChildren
                    ? _expandToggle(context)
                    : Icon(
                        _kindIcon(record.kind),
                        size: 13,
                        color: record.isError
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                      ),
              ),
              SizedBox(
                width: 62,
                child: Text(
                  kindLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    // A failure tints the kind, not the body text: the reader
                    // scans the left rail first.
                    color: record.isError ? scheme.error : scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(child: _recordBody(context, theme, l10n, record)),
              if (record.usage != null || record.status != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    _recordTrailing(l10n, record),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _expandToggle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onAction(ToggleTrajectoryExpansion(record.id)),
      borderRadius: BorderRadius.circular(kShapeChip),
      child: Icon(
        record.expanded ? Icons.expand_more : Icons.chevron_right,
        size: 14,
        color: scheme.onSurfaceVariant,
      ),
    );
  }

  /// The scan line: a tool row leads with its name, everything else with its
  /// preview text. Results never ride the scan line — they are inspector
  /// material, and a phone row holds one fact.
  Widget _recordBody(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
    TrajectoryRecord record,
  ) {
    final scheme = theme.colorScheme;
    final style = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurface,
      height: 1.2,
    );
    final prompt = _promptLabel(l10n, record);
    if (record.kind == TrajectoryRecordKind.tool) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: record.label,
              style: style?.copyWith(
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
            if (record.text.isNotEmpty)
              TextSpan(
                text: '  ${record.text}',
                style: style?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    if (record.text.isEmpty) {
      return Text(
        prompt ?? '—',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style?.copyWith(
          color: scheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Text(
      prompt == null ? record.text : '$prompt · ${record.text}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

/// The modal inspector: every real metric the record carries, plus the full
/// payloads the scan line elides.
class TrajectoryInspector extends StatelessWidget {
  const TrajectoryInspector({required this.record, super.key});

  final TrajectoryRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final scheme = theme.colorScheme;
    final usage = record.usage;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(_kindIcon(record.kind), size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _kindLabel(l10n, record.kind),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _Fact(
              label: l10n.trajectoryFactTurn,
              value: record.turn == null
                  ? l10n.trajectoryFactUnavailable
                  : l10n.trajectoryTurnLabel(record.turn!),
            ),
            _Fact(
              label: l10n.trajectoryFactStep,
              value: record.step == 0
                  ? l10n.trajectoryFactOutsideStep
                  : l10n.trajectoryStepLabel(record.step),
            ),
            _Fact(
              label: l10n.trajectoryFactKind,
              value: _kindLabel(l10n, record.kind),
            ),
            if (record.parentId case final parentId?)
              _Fact(
                label: l10n.trajectoryFactParentCall,
                value: parentId,
                mono: true,
              ),
            _Fact(
              label: l10n.trajectoryFactStatus,
              value: record.status == null
                  ? l10n.trajectoryFactUnavailable
                  : _statusLabel(l10n, record.status!),
            ),
            _Fact(
              label: l10n.trajectoryFactStarted,
              value: record.startedAtEpochMs == null
                  ? l10n.trajectoryFactUnavailable
                  : _formatTimestamp(context, record.startedAtEpochMs!),
            ),
            // The recorded stream's first token is the only latency boundary
            // the session log carries; there is no separate timing record.
            _Fact(
              label: l10n.trajectoryFactFirstToken,
              value: record.firstTokenAtEpochMs == null
                  ? l10n.trajectoryTimingNotRecorded
                  : _formatTimestamp(context, record.firstTokenAtEpochMs!),
            ),
            _Fact(
              label: l10n.trajectoryFactDuration,
              value: l10n.trajectoryFactUnavailable,
              note: l10n.trajectoryDurationNotRecorded,
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: 8),
            Text(
              l10n.trajectoryUsageSection,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            if (usage == null)
              Text(
                l10n.trajectoryUsageNotReported,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else ...[
              _Fact(
                label: l10n.trajectoryUsageInput,
                value: _tokens(l10n, usage.billedInputTokens),
              ),
              if (usage.cacheReadTokens case final value?)
                _Fact(
                  label: l10n.trajectoryUsageCachedRead,
                  value: _tokens(l10n, value),
                  inset: true,
                ),
              if (usage.cacheWriteTokens case final value?)
                _Fact(
                  label: l10n.trajectoryUsageCacheWrite,
                  value: _tokens(l10n, value),
                  inset: true,
                ),
              _Fact(
                label: l10n.trajectoryUsageOutput,
                value: _tokens(l10n, usage.outputTokens),
              ),
              if (usage.reasoningTokens case final value?)
                _Fact(
                  label: l10n.trajectoryUsageReasoning,
                  value: _tokens(l10n, value),
                  inset: true,
                ),
            ],
            if (record.detail case final detail?) ...[
              const SizedBox(height: 8),
              Divider(height: 1, color: scheme.outlineVariant),
              const SizedBox(height: 8),
              _Payload(title: l10n.trajectoryInputSection, text: detail),
            ],
            if (record.result case final result?) ...[
              const SizedBox(height: 8),
              Divider(height: 1, color: scheme.outlineVariant),
              const SizedBox(height: 8),
              _Payload(title: l10n.trajectoryOutputSection, text: result),
            ],
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    this.note,
    this.mono = false,
    this.inset = false,
  });

  final String label;
  final String value;
  final String? note;
  final bool mono;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(inset ? 12 : 0, 2, 0, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  value,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                    fontFamily: mono ? 'monospace' : null,
                  ),
                ),
                if (note != null)
                  Text(
                    note!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Payload extends StatelessWidget {
  const _Payload({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          text.isEmpty ? '—' : text,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

String _kindLabel(AppLocalizations l10n, TrajectoryRecordKind kind) =>
    switch (kind) {
      TrajectoryRecordKind.user => l10n.trajectoryKindUser,
      TrajectoryRecordKind.context => l10n.trajectoryKindContext,
      TrajectoryRecordKind.assistant => l10n.trajectoryKindAssistant,
      TrajectoryRecordKind.tool => l10n.trajectoryKindTool,
      TrajectoryRecordKind.compaction => l10n.trajectoryKindCompaction,
      TrajectoryRecordKind.command => l10n.trajectoryKindCommand,
      TrajectoryRecordKind.error => l10n.trajectoryKindError,
    };

IconData _kindIcon(TrajectoryRecordKind kind) => switch (kind) {
  TrajectoryRecordKind.user => Icons.person_outline,
  TrajectoryRecordKind.context => Icons.info_outline,
  TrajectoryRecordKind.assistant => Icons.auto_awesome_outlined,
  TrajectoryRecordKind.tool => Icons.build_outlined,
  TrajectoryRecordKind.compaction => Icons.compress,
  TrajectoryRecordKind.command => Icons.terminal,
  TrajectoryRecordKind.error => Icons.error_outline,
};

/// Ledger-only label for a user prompt: the reference marks the record that
/// opens a model turn.
String? _promptLabel(AppLocalizations l10n, TrajectoryRecord record) =>
    record.kind == TrajectoryRecordKind.user ||
        record.kind == TrajectoryRecordKind.context
    ? (record.isRecall ? l10n.recallLabel : null)
    : null;

String _statusLabel(AppLocalizations l10n, String status) => switch (status) {
  'running' => l10n.runStatusRunning,
  'streaming' => l10n.trajectoryStatusStreaming,
  'completed' => l10n.runStatusDone,
  'failed' => l10n.runStatusFailed,
  'success' => l10n.runStatusDone,
  _ => status,
};

String _tokens(AppLocalizations l10n, int value) =>
    l10n.trajectoryTokenCount(value);

String _usageSummary(AppLocalizations l10n, TokenUsage usage) =>
    l10n.trajectoryTurnUsage(
      _compactTokens(usage.billedInputTokens),
      _compactTokens(usage.outputTokens),
    );

/// Compact token count for a structure line: the inspector carries the exact
/// figure, the rule carries the magnitude.
String _compactTokens(int value) {
  if (value < 1000) return value.toString();
  if (value < 1000000) {
    final scaled = value / 1000;
    return scaled >= 100
        ? '${scaled.round()}K'
        : '${(scaled * 10).round() / 10}K';
  }
  final scaled = value / 1000000;
  return scaled >= 100
      ? '${scaled.round()}M'
      : '${(scaled * 10).round() / 10}M';
}

/// Trailing per-row figure: the status while a record runs or fails, else
/// its step's output tokens.
String _recordTrailing(AppLocalizations l10n, TrajectoryRecord record) {
  final status = record.status;
  if (record.isError || status == 'running' || status == 'streaming') {
    return _statusLabel(l10n, status ?? 'failed');
  }
  final output = record.usage?.outputTokens;
  return output == null ? '' : _tokens(l10n, output);
}

String _formatTimestamp(BuildContext context, int epochMs) {
  final localizations = MaterialLocalizations.of(context);
  final time = DateTime.fromMillisecondsSinceEpoch(epochMs);
  return localizations.formatFullDate(time);
}
