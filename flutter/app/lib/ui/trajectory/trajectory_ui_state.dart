/// Trajectory screen UI state and user intents (UDF).
///
/// The ledger is a projection over the same `domain` timeline the chat
/// surface renders: turn boundaries become rules, the adapter's per-row
/// step fact becomes inline step markers, and tool rows carry their nested
/// code-dispatch calls. Every figure the inspector shows is a fact the host
/// logged; [TrajectoryUnavailable] states a boundary the session log does
/// not carry rather than estimating one.
library;

import 'package:domain/model/token_usage.dart';

/// The record kinds the ledger distinguishes, in the reference trajectory's
/// own vocabulary (`TrajectoryCellKind`).
enum TrajectoryRecordKind {
  user,
  context,
  assistant,
  tool,
  compaction,
  command,
  error,
}

/// One selectable ledger record.
///
/// [id] is the stable identity that survives prepending an older history
/// page (the owning item's own key), and [sourceSeq] its log position when
/// the item carries one.
final class TrajectoryRecord {
  const TrajectoryRecord({
    required this.id,
    required this.kind,
    required this.turn,
    required this.step,
    required this.label,
    this.text = '',
    this.detail,
    this.result,
    this.status,
    this.isError = false,
    this.usage,
    this.startedAtEpochMs,
    this.firstTokenAtEpochMs,
    this.parentId,
    this.depth = 0,
    this.hasChildren = false,
    this.expanded = false,
    this.isRecall = false,
  });

  final String id;
  final TrajectoryRecordKind kind;

  /// Owning turn from the preceding `turn/start`; null before the first one.
  final int? turn;

  /// Owning step from the logged `step/start`; 0 when the row sits outside
  /// any step (user prompts, context injections, commands).
  final int step;

  /// Short non-markdown summary shown on the ledger row.
  final String label;

  /// Body the row shows inline, and the first half of what search matches.
  final String text;

  /// Full input for the inspector — tool arguments or a prompt's full text.
  final String? detail;

  /// Full tool result for the inspector.
  final String? result;

  /// Localized run status for a tool/command/compaction row; null when the
  /// kind carries no lifecycle.
  final String? status;

  final bool isError;

  /// Provider accounting the host sent for this record's step; null when the
  /// adapter reported none.
  final TokenUsage? usage;

  /// Unix epoch milliseconds the record started, when the event carried one.
  final int? startedAtEpochMs;

  /// First model output token of a recorded assistant stream, when present.
  final int? firstTokenAtEpochMs;

  /// Enclosing root call id for a nested dispatch; null on a root row.
  final String? parentId;

  /// Nesting depth: 0 for a ledger row, 1+ for a code-dispatch sub-call.
  final int depth;

  final bool hasChildren;

  /// Whether this row's nested calls are currently shown.
  final bool expanded;

  /// Cross-session recall (a context injection whose source is a session
  /// reference) — the ledger labels it, search still indexes the text.
  final bool isRecall;

  TrajectoryRecord copyWith({bool? expanded}) => TrajectoryRecord(
    id: id,
    kind: kind,
    turn: turn,
    step: step,
    label: label,
    text: text,
    detail: detail,
    result: result,
    status: status,
    isError: isError,
    usage: usage,
    startedAtEpochMs: startedAtEpochMs,
    firstTokenAtEpochMs: firstTokenAtEpochMs,
    parentId: parentId,
    depth: depth,
    hasChildren: hasChildren,
    expanded: expanded ?? this.expanded,
    isRecall: isRecall,
  );
}

/// One turn section of the ledger: the turn rule, its step markers, and its
/// records in log order (nested calls inline, indented under their parent).
final class TrajectoryTurnSection {
  const TrajectoryTurnSection({
    required this.turn,
    required this.rows,
    this.usage,
  });

  /// Turn number, or null for the rows before the first `turn/start`.
  final int? turn;

  final List<TrajectoryLedgerRow> rows;

  /// Turn total the adapter folded from its steps; null when no step
  /// reported accounting.
  final TokenUsage? usage;
}

/// A turn rule, a step marker, or a record — the ledger's flat display
/// vocabulary, so one `ListView` renders the whole structure.
sealed class TrajectoryLedgerRow {
  const TrajectoryLedgerRow();
}

/// Thick rule at a turn boundary (`Turn {n}`).
final class TrajectoryTurnRow extends TrajectoryLedgerRow {
  const TrajectoryTurnRow({
    required this.turn,
    required this.usage,
    required this.recordCount,
    required this.toolCount,
  });

  final int? turn;
  final TokenUsage? usage;
  final int recordCount;
  final int toolCount;
}

/// Inline marker opening a step inside a turn (`Step {n}`).
final class TrajectoryStepRow extends TrajectoryLedgerRow {
  const TrajectoryStepRow({
    required this.turn,
    required this.step,
    required this.recordCount,
  });

  final int? turn;
  final int step;
  final int recordCount;
}

/// One selectable ledger record.
final class TrajectoryRecordRow extends TrajectoryLedgerRow {
  const TrajectoryRecordRow(this.record);

  final TrajectoryRecord record;
}

/// Ledger loading state for the empty body: the first page is in flight,
/// there is genuinely nothing logged, or a search matched nothing.
enum TrajectoryEmptyState { loading, noRecords, noSearchMatches }

final class TrajectoryUiState {
  const TrajectoryUiState({
    this.sections = const <TrajectoryTurnSection>[],
    this.rows = const <TrajectoryLedgerRow>[],
    this.searchQuery = '',
    this.selectedId,
    this.expandedIds = const <String>{},
    this.isLoading = false,
    this.isLoadingOlder = false,
    this.hasMoreOlder = false,
    this.errorMessage,
    this.sessionTitle,
    this.totalRecords = 0,
    this.matchCount = 0,
  });

  /// Every loaded turn section, unfiltered — the inspector and the search
  /// index read this window.
  final List<TrajectoryTurnSection> sections;

  /// The flattened, search-filtered ledger in display order.
  final List<TrajectoryLedgerRow> rows;

  final String searchQuery;

  /// Stable id of the record whose inspector is open; null = none.
  final String? selectedId;

  /// Record ids whose nested code-dispatch calls are expanded.
  final Set<String> expandedIds;

  final bool isLoading;
  final bool isLoadingOlder;
  final bool hasMoreOlder;

  /// Host failure text from the last paging attempt; null when clear.
  final String? errorMessage;

  /// Session title for the app bar; null while the summaries have not
  /// loaded it.
  final String? sessionTitle;

  /// Records in the loaded window (unfiltered).
  final int totalRecords;

  /// Records matching the live query; equals [totalRecords] without one.
  final int matchCount;

  bool get hasSearch => searchQuery.trim().isNotEmpty;

  TrajectoryEmptyState get emptyState {
    if (isLoading && totalRecords == 0) return TrajectoryEmptyState.loading;
    if (hasSearch && matchCount == 0) {
      return TrajectoryEmptyState.noSearchMatches;
    }
    return TrajectoryEmptyState.noRecords;
  }

  /// The selected record, or null when nothing is selected.
  TrajectoryRecord? get selectedRecord {
    final id = selectedId;
    if (id == null) return null;
    for (final section in sections) {
      for (final row in section.rows) {
        if (row is TrajectoryRecordRow && row.record.id == id) {
          return row.record;
        }
      }
    }
    return null;
  }
}

/// User intents the trajectory screen dispatches.
sealed class TrajectoryAction {
  const TrajectoryAction();
}

/// Replace the live ledger query ('' clears it).
final class SetTrajectorySearch extends TrajectoryAction {
  const SetTrajectorySearch(this.query);

  final String query;
}

/// Open the inspector for one record, or close it with null.
final class SelectTrajectoryRecord extends TrajectoryAction {
  const SelectTrajectoryRecord(this.recordId);

  final String? recordId;
}

/// Show/hide one record's nested code-dispatch calls.
final class ToggleTrajectoryExpansion extends TrajectoryAction {
  const ToggleTrajectoryExpansion(this.recordId);

  final String recordId;
}

/// Load one older history page.
final class LoadOlderTrajectory extends TrajectoryAction {
  const LoadOlderTrajectory();
}
