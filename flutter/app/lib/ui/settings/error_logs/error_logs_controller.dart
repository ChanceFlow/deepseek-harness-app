/// Controller managing state and interactions for the Error Logs screen.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import '../../../logging/error_log_collector.dart';
import '../../../logging/error_log_entry.dart';
import '../../state_stream.dart';
import 'error_logs_ui_state.dart';

class ErrorLogsController {
  ErrorLogsController({ErrorLogCollector? collector, this.activeBackendUrl})
    : _collector = collector ?? ErrorLogCollector.instance {
    _stateStream = AppStateStream<ErrorLogsUiState>(
      ErrorLogsUiState(
        entries: _collector.entries,
        activeBackendUrl: activeBackendUrl,
      ),
    );
    _collectorSub = _collector.stream.listen((List<ErrorLogEntry> entries) {
      _stateStream.value = _stateStream.value.copyWith(entries: entries);
    });
  }

  final ErrorLogCollector _collector;
  final String? activeBackendUrl;
  late final AppStateStream<ErrorLogsUiState> _stateStream;
  StreamSubscription<List<ErrorLogEntry>>? _collectorSub;

  ErrorLogsUiState get state => _stateStream.value;
  Stream<ErrorLogsUiState> get uiState => _stateStream.stream;

  void onAction(ErrorLogsAction action) {
    switch (action) {
      case SetFilterLevelAction(:final ErrorLogLevel? level):
        _stateStream.value = _stateStream.value.copyWith(
          filterLevel: level,
          clearFilterLevel: level == null,
        );

      case SetSearchQueryAction(:final String query):
        _stateStream.value = _stateStream.value.copyWith(searchQuery: query);

      case ToggleExpandAction(:final String id):
        final Set<String> updated = Set<String>.from(
          _stateStream.value.expandedIds,
        );
        if (updated.contains(id)) {
          updated.remove(id);
        } else {
          updated.add(id);
        }
        _stateStream.value = _stateStream.value.copyWith(expandedIds: updated);

      case ExpandAllAction():
        final Set<String> allIds = _stateStream.value.filteredEntries
            .map((ErrorLogEntry e) => e.id)
            .toSet();
        _stateStream.value = _stateStream.value.copyWith(expandedIds: allIds);

      case CollapseAllAction():
        _stateStream.value = _stateStream.value.copyWith(
          expandedIds: const <String>{},
        );

      case ClearLogsAction():
        _collector.clear();
        _stateStream.value = _stateStream.value.copyWith(
          entries: const <ErrorLogEntry>[],
          expandedIds: const <String>{},
        );

      case RefreshLogsAction():
        _stateStream.value = _stateStream.value.copyWith(
          entries: _collector.entries,
        );
    }
  }

  /// Copy all current filtered logs (or all logs) formatted as a Markdown report.
  Future<String> copyAllToClipboard({bool filteredOnly = false}) async {
    final List<ErrorLogEntry> targetEntries = filteredOnly
        ? _stateStream.value.filteredEntries
        : _stateStream.value.entries;
    final String report = _collector.formatExportReport(
      entries: targetEntries,
      activeBackendUrl: activeBackendUrl,
    );
    await Clipboard.setData(ClipboardData(text: report));
    return report;
  }

  /// Copy a single error log entry formatted as Markdown.
  Future<String> copyEntryToClipboard(ErrorLogEntry entry) async {
    final String text = entry.toMarkdown();
    await Clipboard.setData(ClipboardData(text: text));
    return text;
  }

  /// Copy system environment information alone.
  Future<String> copySystemInfoToClipboard() async {
    final String report = _collector.formatExportReport(
      entries: const <ErrorLogEntry>[],
      activeBackendUrl: activeBackendUrl,
    );
    await Clipboard.setData(ClipboardData(text: report));
    return report;
  }

  void dispose() {
    unawaited(_collectorSub?.cancel());
    _collectorSub = null;
    unawaited(_stateStream.close());
  }
}
