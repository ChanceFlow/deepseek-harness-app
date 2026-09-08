/// UI state and actions for the Error Logs screen.
library;

import '../../../logging/error_log_entry.dart';

/// Immutable UI state for the Error Logs screen.
class ErrorLogsUiState {
  const ErrorLogsUiState({
    this.entries = const <ErrorLogEntry>[],
    this.filterLevel,
    this.searchQuery = '',
    this.expandedIds = const <String>{},
    this.isLoading = false,
    this.activeBackendUrl,
  });

  final List<ErrorLogEntry> entries;
  final ErrorLogLevel? filterLevel;
  final String searchQuery;
  final Set<String> expandedIds;
  final bool isLoading;
  final String? activeBackendUrl;

  int get totalCount => entries.length;

  int get fatalCount =>
      entries.where((ErrorLogEntry e) => e.level == ErrorLogLevel.fatal).length;

  int get errorCount =>
      entries.where((ErrorLogEntry e) => e.level == ErrorLogLevel.error).length;

  int get warnCount => entries
      .where((ErrorLogEntry e) => e.level == ErrorLogLevel.warning)
      .length;

  /// Entries filtered by [filterLevel] and [searchQuery].
  List<ErrorLogEntry> get filteredEntries {
    final String query = searchQuery.trim().toLowerCase();
    return entries.where((ErrorLogEntry entry) {
      if (filterLevel != null && entry.level != filterLevel) {
        return false;
      }
      if (query.isNotEmpty) {
        final bool inMessage = entry.message.toLowerCase().contains(query);
        final bool inType = entry.type.toLowerCase().contains(query);
        final bool inStack =
            entry.stackTrace?.toLowerCase().contains(query) ?? false;
        if (!inMessage && !inType && !inStack) return false;
      }
      return true;
    }).toList();
  }

  bool isExpanded(String id) => expandedIds.contains(id);

  ErrorLogsUiState copyWith({
    List<ErrorLogEntry>? entries,
    ErrorLogLevel? filterLevel,
    bool clearFilterLevel = false,
    String? searchQuery,
    Set<String>? expandedIds,
    bool? isLoading,
    String? activeBackendUrl,
  }) {
    return ErrorLogsUiState(
      entries: entries ?? this.entries,
      filterLevel: clearFilterLevel ? null : (filterLevel ?? this.filterLevel),
      searchQuery: searchQuery ?? this.searchQuery,
      expandedIds: expandedIds ?? this.expandedIds,
      isLoading: isLoading ?? this.isLoading,
      activeBackendUrl: activeBackendUrl ?? this.activeBackendUrl,
    );
  }
}

/// Actions dispatched from the Error Logs UI.
sealed class ErrorLogsAction {
  const ErrorLogsAction();
}

/// Change active severity filter. Pass null for all.
class SetFilterLevelAction extends ErrorLogsAction {
  const SetFilterLevelAction(this.level);
  final ErrorLogLevel? level;
}

/// Set search filter query.
class SetSearchQueryAction extends ErrorLogsAction {
  const SetSearchQueryAction(this.query);
  final String query;
}

/// Toggle expanded state for a single card.
class ToggleExpandAction extends ErrorLogsAction {
  const ToggleExpandAction(this.id);
  final String id;
}

/// Expand all cards.
class ExpandAllAction extends ErrorLogsAction {
  const ExpandAllAction();
}

/// Collapse all cards.
class CollapseAllAction extends ErrorLogsAction {
  const CollapseAllAction();
}

/// Clear all collected logs.
class ClearLogsAction extends ErrorLogsAction {
  const ClearLogsAction();
}

/// Refresh logs from collector.
class RefreshLogsAction extends ErrorLogsAction {
  const RefreshLogsAction();
}
