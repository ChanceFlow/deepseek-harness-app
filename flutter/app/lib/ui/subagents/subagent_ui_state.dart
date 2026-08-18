/// Subagents screen UI state and intents — port of SubagentUiState.kt.
library;

import 'package:domain/model/session.dart';
import 'package:domain/model/subagent.dart';
import 'package:domain/model/timeline_item.dart';

final class SubagentUiState {
  const SubagentUiState({
    this.sessions = const <SessionSummary>[],
    this.selectedParentId,
    this.catalog = const SubagentCatalog(),
    this.selectedChildId,
    this.childTimeline = const <TimelineItem>[],
    this.isSendingChild = false,
    this.isLoading = false,
    this.errorMessage,
  });

  final List<SessionSummary> sessions;
  final String? selectedParentId;
  final SubagentCatalog catalog;
  final String? selectedChildId;
  final List<TimelineItem> childTimeline;
  final bool isSendingChild;
  final bool isLoading;
  final String? errorMessage;
}

sealed class SubagentAction {
  const SubagentAction();
}

final class SelectParent extends SubagentAction {
  const SelectParent(this.sessionId);

  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is SelectParent && other.sessionId == sessionId;

  @override
  int get hashCode => sessionId.hashCode;
}

final class OpenChild extends SubagentAction {
  const OpenChild(this.childSessionId);

  final String childSessionId;

  @override
  bool operator ==(Object other) =>
      other is OpenChild && other.childSessionId == childSessionId;

  @override
  int get hashCode => childSessionId.hashCode;
}

final class SendSubagentPrompt extends SubagentAction {
  const SendSubagentPrompt(this.text);

  final String text;

  @override
  bool operator ==(Object other) =>
      other is SendSubagentPrompt && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

final class InterruptSubagent extends SubagentAction {
  const InterruptSubagent(this.childSessionId);

  final String childSessionId;

  @override
  bool operator ==(Object other) =>
      other is InterruptSubagent && other.childSessionId == childSessionId;

  @override
  int get hashCode => childSessionId.hashCode;
}

final class RefreshSubagentsAction extends SubagentAction {
  const RefreshSubagentsAction();

  @override
  bool operator ==(Object other) => other is RefreshSubagentsAction;

  @override
  int get hashCode => 'refresh-subagents'.hashCode;
}

final class DismissSubagentError extends SubagentAction {
  const DismissSubagentError();

  @override
  bool operator ==(Object other) => other is DismissSubagentError;

  @override
  int get hashCode => 'dismiss-subagent-error'.hashCode;
}
