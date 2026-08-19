/// Neutral timeline vocabulary rendered by the UI.
///
/// Only the harness adapter is allowed to create these from dsh events.
library;

import 'chat_message.dart';
import 'jobs.dart';
import 'session.dart';

enum ToolRunStatus { running, completed, failed }

/// Sealed timeline item union. Subclasses keep the `Timeline*` prefix so
/// library consumers never see bare `Message`/`Error` names.
sealed class TimelineItem {
  const TimelineItem();
}

/// One chat message row.
final class TimelineMessage extends TimelineItem {
  const TimelineMessage(this.value);

  final ChatMessage value;

  @override
  bool operator ==(Object other) =>
      other is TimelineMessage && other.value == value;

  @override
  int get hashCode => Object.hash('message', value);
}

/// Turn boundary from a logged `turn/start`; groups the transcript
/// ledger-style.
final class TimelineTurnBoundary extends TimelineItem {
  const TimelineTurnBoundary(this.turn);

  final int turn;

  @override
  bool operator ==(Object other) =>
      other is TimelineTurnBoundary && other.turn == turn;

  @override
  int get hashCode => Object.hash('turn', turn);
}

/// Context compaction from a logged `compaction/summary` event.
final class TimelineCompaction extends TimelineItem {
  const TimelineCompaction({required this.id, required this.shadowedCount});

  final String id;
  final int shadowedCount;

  @override
  bool operator ==(Object other) =>
      other is TimelineCompaction &&
      other.id == id &&
      other.shadowedCount == shadowedCount;

  @override
  int get hashCode => Object.hash('compaction', id, shadowedCount);
}

/// Non-user context injected into model history (web ContextMessageNode):
/// a `user/message` whose durable source kind is not `user` — goal
/// snapshots, skill invocations, workspace instructions, plugin catalogs,
/// cross-session recalls.
final class TimelineContextInjection extends TimelineItem {
  const TimelineContextInjection({
    required this.id,
    required this.text,
    this.producerLabel,
    this.isRecall = false,
    this.summary,
  });

  final String id;

  /// Collected text of the injected content blocks.
  final String text;

  /// Producer name projected from the durable source (instruction paths,
  /// plugin id, skill name, or the bare source kind); null when the
  /// source carries no readable kind.
  final String? producerLabel;

  /// Cross-session recall (source kind `session-reference`).
  final bool isRecall;

  /// One-line account for `notice`-form context; null otherwise.
  final String? summary;

  @override
  bool operator ==(Object other) =>
      other is TimelineContextInjection &&
      other.id == id &&
      other.text == text &&
      other.producerLabel == producerLabel &&
      other.isRecall == isRecall &&
      other.summary == summary;

  @override
  int get hashCode => Object.hash(
    'context-injection',
    id,
    text,
    producerLabel,
    isRecall,
    summary,
  );
}

final class TimelineToolCall extends TimelineItem {
  const TimelineToolCall({
    required this.id,
    required this.name,
    this.arguments,
    this.result,
    this.isError = false,
    this.status = ToolRunStatus.running,
  });

  final String id;
  final String name;
  final String? arguments;
  final String? result;
  final bool isError;
  final ToolRunStatus status;

  @override
  bool operator ==(Object other) =>
      other is TimelineToolCall &&
      other.id == id &&
      other.name == name &&
      other.arguments == arguments &&
      other.result == result &&
      other.isError == isError &&
      other.status == status;

  @override
  int get hashCode =>
      Object.hash('tool', id, name, arguments, result, isError, status);
}

final class TimelineApprovalRequest extends TimelineItem {
  const TimelineApprovalRequest({
    required this.requestId,
    required this.sessionId,
    required this.approvalId,
    required this.toolName,
    this.callId,
    this.reason,
  });

  final String requestId;
  final String sessionId;
  final String approvalId;
  final String toolName;
  final String? callId;
  final String? reason;

  @override
  bool operator ==(Object other) =>
      other is TimelineApprovalRequest &&
      other.requestId == requestId &&
      other.sessionId == sessionId &&
      other.approvalId == approvalId &&
      other.toolName == toolName &&
      other.callId == callId &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(
    'approval',
    requestId,
    sessionId,
    approvalId,
    toolName,
    callId,
    reason,
  );
}

final class TimelineQuestionRequest extends TimelineItem {
  const TimelineQuestionRequest({
    required this.requestId,
    required this.questions,
  });

  final String requestId;
  final List<QuestionItem> questions;

  @override
  bool operator ==(Object other) =>
      other is TimelineQuestionRequest &&
      other.requestId == requestId &&
      _listEquals(other.questions, questions);

  @override
  int get hashCode =>
      Object.hash('question', requestId, Object.hashAll(questions));
}

final class TimelineQueue extends TimelineItem {
  const TimelineQueue({this.items = const <SessionQueueItem>[]});

  final List<SessionQueueItem> items;

  @override
  bool operator ==(Object other) =>
      other is TimelineQueue && _listEquals(other.items, items);

  @override
  int get hashCode => Object.hash('queue', Object.hashAll(items));
}

final class TimelineJobs extends TimelineItem {
  const TimelineJobs({this.jobs = const <JobView>[]});

  final List<JobView> jobs;

  @override
  bool operator ==(Object other) =>
      other is TimelineJobs && _listEquals(other.jobs, jobs);

  @override
  int get hashCode => Object.hash('jobs', Object.hashAll(jobs));
}

final class TimelineError extends TimelineItem {
  const TimelineError({required this.id, required this.message, this.code});

  final String id;
  final String message;
  final String? code;

  @override
  bool operator ==(Object other) =>
      other is TimelineError &&
      other.id == id &&
      other.message == message &&
      other.code == code;

  @override
  int get hashCode => Object.hash('error', id, message, code);
}

final class QuestionItem {
  const QuestionItem({
    required this.id,
    required this.question,
    this.options = const <String>[],
    this.multiSelect = false,
    this.detail,
    this.header,
    this.optionDescriptions = const <String, String>{},
    this.intent,
  });

  final String id;
  final String question;
  final List<String> options;
  final bool multiSelect;
  final String? detail;
  final String? header;
  final Map<String, String> optionDescriptions;

  /// Presentation-only hint; `plan-review` renders a review decision card.
  final QuestionIntent? intent;

  @override
  bool operator ==(Object other) =>
      other is QuestionItem &&
      other.id == id &&
      other.question == question &&
      _listEquals(other.options, options) &&
      other.multiSelect == multiSelect &&
      other.detail == detail &&
      other.header == header &&
      _mapEquals(other.optionDescriptions, optionDescriptions) &&
      other.intent == intent;

  @override
  int get hashCode => Object.hash(
    id,
    question,
    Object.hashAll(options),
    multiSelect,
    detail,
    header,
    Object.hashAll(optionDescriptions.keys),
    Object.hashAll(optionDescriptions.values),
    intent,
  );
}

/// Wire presentation intent carried on one question.
final class QuestionIntent {
  const QuestionIntent({required this.kind, this.approve});

  final String kind;
  final String? approve;

  @override
  bool operator ==(Object other) =>
      other is QuestionIntent && other.kind == kind && other.approve == approve;

  @override
  int get hashCode => Object.hash(kind, approve);
}

final class ApprovalAnswer {
  const ApprovalAnswer({
    required this.requestId,
    required this.sessionId,
    required this.approvalId,
    required this.allowed,
  });

  final String requestId;
  final String sessionId;
  final String approvalId;
  final bool allowed;

  @override
  bool operator ==(Object other) =>
      other is ApprovalAnswer &&
      other.requestId == requestId &&
      other.sessionId == sessionId &&
      other.approvalId == approvalId &&
      other.allowed == allowed;

  @override
  int get hashCode => Object.hash(requestId, sessionId, approvalId, allowed);
}

final class QuestionAnswer {
  const QuestionAnswer({
    required this.questionId,
    this.selectedOptions = const <String>[],
    this.customText,
  });

  final String questionId;
  final List<String> selectedOptions;
  final String? customText;

  @override
  bool operator ==(Object other) =>
      other is QuestionAnswer &&
      other.questionId == questionId &&
      _listEquals(other.selectedOptions, selectedOptions) &&
      other.customText == customText;

  @override
  int get hashCode =>
      Object.hash(questionId, Object.hashAll(selectedOptions), customText);
}

final class SessionQueueItem {
  const SessionQueueItem({
    required this.itemId,
    required this.placement,
    required this.text,
  });

  final String itemId;
  final QueuePlacement placement;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is SessionQueueItem &&
      other.itemId == itemId &&
      other.placement == placement &&
      other.text == text;

  @override
  int get hashCode => Object.hash(itemId, placement, text);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
