/// Trajectory screen controller.
///
/// The reference web client's `ui-trajectory` ledger is assembled from the
/// same session facts the chat surface already receives: the conversation
/// node stream plus `session/history` paging. This controller folds the
/// adapter's `domain` timeline window into turn sections with inline step
/// markers, keeps a local search over the loaded window, and owns the
/// selection the inspector reads. It issues no RPC of its own — older
/// history rides the repository's existing `loadOlderHistory`, which the
/// shared session state serves to both views.
library;

import 'dart:async';

import 'package:domain/model/chat_message.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/timeline_window.dart';
import 'package:domain/model/token_usage.dart';
import 'package:domain/repository/chat_repository.dart';

import '../state_stream.dart';
import '../../logging/error_log_collector.dart';
import 'trajectory_ui_state.dart';

/// One reference-record index over the loaded window.
///
/// The reference ledger indexes each record's text once per version and
/// matches space-separated terms with AND semantics
/// (`trajectory-search-index.ts`); this folds the same fields into one
/// lower-cased haystack per record.
String trajectoryRecordHaystack(TrajectoryRecord record) => <String>[
  record.turn == null ? 'between turns' : 'turn ${record.turn}',
  record.step == 0 ? '' : 'step ${record.step}',
  record.kind.name,
  record.label,
  record.text,
  record.detail ?? '',
  record.result ?? '',
  record.status ?? '',
].where((part) => part.isNotEmpty).join('\n').toLowerCase();

/// Whether [haystack] satisfies every whitespace-separated term in [query].
bool trajectoryMatches(String haystack, List<String> terms) =>
    terms.every(haystack.contains);

class TrajectoryController {
  TrajectoryController(
    this._repository, {
    required this.sessionId,
    String? title,
  }) : _sessionTitle = title {
    _subs.add(
      _repository.observeSessions().listen((sessions) {
        for (final session in sessions) {
          if (session.id != sessionId) continue;
          _sessionTitle = session.title;
          break;
        }
        _publish();
      }),
    );
    _subs.add(
      _repository.observeTimelineWindow(sessionId).listen((window) {
        _window = window;
        _rebuild();
        _publish();
      }),
    );
  }

  final ChatRepository _repository;
  final String sessionId;

  final AppStateStream<TrajectoryUiState> _state =
      AppStateStream<TrajectoryUiState>(const TrajectoryUiState());
  final List<StreamSubscription<void>> _subs = <StreamSubscription<void>>[];

  TimelineWindow _window = const TimelineWindow();
  String? _sessionTitle;
  String _searchQuery = '';
  String? _selectedId;
  final Set<String> _expandedIds = <String>{};
  bool _loadingOlder = false;
  String? _errorMessage;

  /// The window version the current [TrajectoryUiState.sections] was folded
  /// from. Rebuilding is skipped while the window object is unchanged, so a
  /// streaming publish that only re-sent the same items does not reindex.
  TimelineWindow? _builtFrom;
  List<TrajectoryTurnSection> _sections = const <TrajectoryTurnSection>[];

  /// Lower-cased search haystack per record id, rebuilt with the sections.
  Map<String, String> _haystacks = const <String, String>{};

  TrajectoryUiState get state => _state.value;
  Stream<TrajectoryUiState> get uiState => _state.stream;

  void dispose() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    unawaited(_state.close());
  }

  void onAction(TrajectoryAction action) {
    switch (action) {
      case SetTrajectorySearch(:final query):
        _searchQuery = query;
        _publish();
      case SelectTrajectoryRecord(:final recordId):
        _selectedId = recordId;
        _publish();
      case ToggleTrajectoryExpansion(:final recordId):
        if (!_expandedIds.remove(recordId)) _expandedIds.add(recordId);
        _rebuild();
        _publish();
      case LoadOlderTrajectory():
        unawaited(_loadOlder());
    }
  }

  Future<void> _loadOlder() async {
    // A transport failure can clear the window's own flag; the retry must
    // stay available until a page actually lands.
    if (_loadingOlder || (!_window.hasMoreOlder && _errorMessage == null)) {
      return;
    }
    _loadingOlder = true;
    _errorMessage = null;
    _publish();
    try {
      await _repository.loadOlderHistory(sessionId);
    } catch (error, stackTrace) {
      _errorMessage = error.toString();
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: const <String, Object?>{'controller': 'TrajectoryController'},
      );
    } finally {
      _loadingOlder = false;
      _publish();
    }
  }

  /// Folds the window into turn sections. The window's own `isLoadingOlder`
  /// is not mirrored into the ledger: the repository already flags a page in
  /// flight, and this controller's own request marker keeps the button
  /// disabled from the tap until the stream settles.
  void _rebuild() {
    if (identical(_window, _builtFrom)) return;
    _builtFrom = _window;

    // The ledger walks the window itself rather than the chat outline's
    // `groupTimelineByTurn`: that helper files a boundary as its group's
    // heading and drops the item, while the turn's folded token total rides
    // the boundary item. Rows before the first boundary form a null-turn
    // section, matching the reference's "between turns" section.
    final sections = <TrajectoryTurnSection>[];
    int? turn;
    TokenUsage? usage;
    var pending = <TimelineItem>[];

    void flush() {
      final rows = _turnRows(pending, turn: turn);
      if (rows.isNotEmpty) {
        sections.add(
          TrajectoryTurnSection(turn: turn, rows: rows, usage: usage),
        );
      }
      pending = <TimelineItem>[];
    }

    for (final item in _window.items) {
      if (item is TimelineTurnBoundary) {
        flush();
        turn = item.turn;
        usage = item.usage;
        continue;
      }
      pending.add(item);
    }
    flush();

    _sections = sections;
    final haystacks = <String, String>{};
    for (final section in sections) {
      for (final row in section.rows) {
        if (row is TrajectoryRecordRow) {
          haystacks[row.record.id] = trajectoryRecordHaystack(row.record);
        }
      }
    }
    _haystacks = haystacks;
  }

  /// One turn's display rows: the records in log order with an inline step
  /// marker whenever the owning step changes, and nested dispatch calls
  /// inline under their root (indented) when expanded. The turn rule itself
  /// is the section's own row.
  List<TrajectoryLedgerRow> _turnRows(
    List<TimelineItem> items, {
    required int? turn,
  }) {
    final rows = <TrajectoryLedgerRow>[];
    final stepCounts = <int, int>{};
    final records = <TrajectoryRecord>[];

    void addRecord(TrajectoryRecord record) {
      records.add(record);
      if (record.depth == 0) {
        stepCounts[record.step] = (stepCounts[record.step] ?? 0) + 1;
      }
    }

    for (final item in items) {
      final record = _toRecord(item, turn: turn);
      if (record == null) continue;
      addRecord(record);
      if (item is TimelineToolCall && item.children.isNotEmpty) {
        for (final child in item.flattened.skip(1)) {
          addRecord(_toolRecord(child, turn: turn, depth: 1));
        }
      }
    }
    if (records.isEmpty) return const <TrajectoryLedgerRow>[];

    var lastStep = -1;
    for (final record in records) {
      // A nested dispatch belongs to its parent's row group: a step marker
      // must not split it from its root.
      if (record.depth == 0 && record.step != lastStep) {
        lastStep = record.step;
        rows.add(
          TrajectoryStepRow(
            turn: turn,
            step: record.step,
            recordCount: stepCounts[record.step] ?? 0,
          ),
        );
      }
      rows.add(TrajectoryRecordRow(record));
    }
    return rows;
  }

  void _publish() {
    final terms = _searchQuery
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList();

    final rows = <TrajectoryLedgerRow>[];
    var matchCount = 0;
    for (final section in _sections) {
      var visibleRecords = 0;
      var visibleTools = 0;
      var sectionHasVisible = false;
      for (final row in section.rows) {
        if (row is! TrajectoryRecordRow) continue;
        final record = row.record;
        if (terms.isNotEmpty) {
          if (!trajectoryMatches(_haystacks[record.id] ?? '', terms)) continue;
          matchCount++;
        }
        // A nested code-dispatch call is on screen only while its root's
        // group is expanded; the root row carries the toggle.
        if (record.depth > 0 &&
            record.parentId != null &&
            !_expandedIds.contains(record.parentId)) {
          continue;
        }
        sectionHasVisible = true;
        if (record.depth == 0) {
          visibleRecords++;
          if (record.kind == TrajectoryRecordKind.tool) visibleTools++;
        }
      }
      if (terms.isNotEmpty && !sectionHasVisible) continue;
      rows.add(
        TrajectoryTurnRow(
          turn: section.turn,
          usage: section.usage,
          recordCount: visibleRecords,
          toolCount: visibleTools,
        ),
      );
      if (terms.isEmpty) {
        // The structural rows (step markers) ride through unchanged; only a
        // nested record whose root is collapsed is held back.
        for (final row in section.rows) {
          if (row is! TrajectoryRecordRow) {
            rows.add(row);
            continue;
          }
          final record = row.record;
          if (record.depth > 0 &&
              record.parentId != null &&
              !_expandedIds.contains(record.parentId)) {
            continue;
          }
          rows.add(row);
        }
      } else {
        // A filtered section renders without its structure rows: the turn
        // rule and step markers describe a structure the search removed. A
        // matching sub-call keeps its indentation, so a hit inside a code
        // dispatch stays readable even when its root did not match.
        for (final row in section.rows) {
          if (row is! TrajectoryRecordRow) continue;
          final record = row.record;
          if (!trajectoryMatches(_haystacks[record.id] ?? '', terms)) continue;
          rows.add(row);
        }
      }
    }

    var totalRecords = 0;
    for (final section in _sections) {
      for (final row in section.rows) {
        if (row is TrajectoryRecordRow && row.record.depth == 0) {
          totalRecords++;
        }
      }
    }

    _state.value = TrajectoryUiState(
      sections: _sections,
      rows: rows,
      searchQuery: _searchQuery,
      selectedId: _selectedId,
      expandedIds: Set<String>.unmodifiable(_expandedIds),
      isLoading: _window.isLoading,
      isLoadingOlder: _window.isLoadingOlder || _loadingOlder,
      hasMoreOlder: _window.hasMoreOlder,
      errorMessage: _errorMessage,
      sessionTitle: _sessionTitle,
      totalRecords: totalRecords,
      matchCount: terms.isEmpty ? totalRecords : matchCount,
    );
  }

  TrajectoryRecord? _toRecord(TimelineItem item, {required int? turn}) {
    switch (item) {
      case TimelineMessage(:final value, :final step, :final usage):
        final isAssistant = value.role == MessageRole.assistant;
        return TrajectoryRecord(
          id: value.id,
          kind: isAssistant
              ? TrajectoryRecordKind.assistant
              : TrajectoryRecordKind.user,
          turn: turn,
          step: step,
          label: _messageLabel(value),
          text: _bodyText(value, isAssistant: isAssistant),
          detail: value.text.isEmpty ? null : value.text,
          usage: usage,
          startedAtEpochMs: value.createdAtEpochMs > 0
              ? value.createdAtEpochMs
              : null,
          firstTokenAtEpochMs: item.firstTokenAtEpochMs,
          status: value.streaming ? 'streaming' : null,
        );
      case TimelineContextInjection(
        :final id,
        :final text,
        :final producerLabel,
        :final summary,
        :final isRecall,
      ):
        // A context injection has no logged step: it enters the model
        // history before the step's first user message.
        return TrajectoryRecord(
          id: id,
          kind: TrajectoryRecordKind.context,
          turn: turn,
          step: 0,
          label: producerLabel ?? 'context',
          text: summary ?? text,
          detail: text.isEmpty ? null : text,
          isRecall: isRecall,
        );
      case TimelineToolCall():
        return _toolRecord(item, turn: turn, depth: 0);
      case TimelineCompaction(:final id, :final shadowedCount, :final summary):
        return TrajectoryRecord(
          id: id,
          kind: TrajectoryRecordKind.compaction,
          turn: turn,
          step: 0,
          label: 'compaction',
          text: '${shadowedCount ?? 0} items',
          detail: summary,
          status: shadowedCount == null ? null : 'completed',
        );
      case TimelineCommand(
        :final commandId,
        :final name,
        :final args,
        :final status,
        :final text,
      ):
        return TrajectoryRecord(
          id: commandId,
          kind: TrajectoryRecordKind.command,
          turn: turn,
          step: 0,
          label: name,
          text: text ?? args ?? '',
          detail: args,
          result: text,
          status: status.name,
          isError: status == CommandRunStatus.failed,
        );
      case TimelineError(:final id, :final message, :final code):
        return TrajectoryRecord(
          id: id,
          kind: TrajectoryRecordKind.error,
          turn: turn,
          step: 0,
          label: code ?? 'error',
          text: message,
          status: 'failed',
          isError: true,
        );
      case TimelineTurnBoundary():
      case TimelineApprovalRequest():
      case TimelineQuestionRequest():
      case TimelineQueue():
      case TimelineJobs():
      // Hook audits and workflow runs are decoded facts without a ledger
      // record yet; the fold keeps them addressable for a dedicated surface.
      case TimelineHookAudit():
      case TimelineWorkflowRun():
        return null;
    }
  }

  TrajectoryRecord _toolRecord(
    TimelineToolCall call, {
    required int? turn,
    required int depth,
  }) => TrajectoryRecord(
    id: call.id,
    kind: TrajectoryRecordKind.tool,
    turn: turn,
    step: call.step,
    label: call.name,
    text: call.arguments ?? '',
    detail: call.arguments,
    result: call.result,
    status: call.status.name,
    isError: call.isError,
    parentId: call.parentCallId,
    depth: depth,
    hasChildren: call.children.isNotEmpty,
    expanded: _expandedIds.contains(call.id),
  );

  /// Ledger labels stay host vocabulary: the row is scan-line material and
  /// its localization happens in the view, where the ARB seat lives.
  String _messageLabel(ChatMessage value) =>
      value.role == MessageRole.assistant ? 'assistant' : 'user';

  /// First non-blank line of a message body, the reference ledger's
  /// one-line preview (`trajectoryPreviewText`).
  String _bodyText(ChatMessage value, {required bool isAssistant}) {
    final source = isAssistant && value.text.trim().isEmpty
        ? (value.reasoning ?? '')
        : value.text;
    for (final line in source.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }
}
