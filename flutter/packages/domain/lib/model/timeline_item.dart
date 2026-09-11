/// Neutral timeline vocabulary rendered by the UI.
///
/// Only the harness adapter is allowed to create these from dsh events.
library;

import 'chat_message.dart';
import 'hook.dart';
import 'jobs.dart';
import 'session.dart';
import 'token_usage.dart';
import 'tool_presentation.dart';

enum ToolRunStatus { running, completed, failed }

/// Lifecycle of one durable workflow run or member. `interrupted` is the
/// projected state of a run whose turn closed before its terminal event
/// arrived.
enum WorkflowRunStatus { running, completed, failed, cancelled, interrupted }

/// Lifecycle of a host command folded from its `command/run` +
/// `command/done` pair (web's persistent flow node).
enum CommandRunStatus { running, success, failed }

/// Sealed timeline item union. Subclasses keep the `Timeline*` prefix so
/// library consumers never see bare `Message`/`Error` names.
sealed class TimelineItem {
  const TimelineItem();
}

/// One chat message row.
///
/// [step] is the logged `step/start` step that owns the row (assistant
/// messages carry their step on the wire; user and context rows are step 0
/// — outside any step). [usage] is the provider token accounting the
/// `assistant/message` event carried; null when the adapter reported none.
/// [firstTokenAtEpochMs] is the timestamp of the first model output delta
/// the recorded stream holds, and [stepStartedAtEpochMs] the owning
/// `step/start` event's logged time; together they are the reference's
/// time-to-first-token boundary (`firstTokenTime − stepStartTime`,
/// `client/ui-chat/src/client/contract/turn-metrics.ts`). Either is null
/// when the folded window did not carry it — never a fabricated value.
final class TimelineMessage extends TimelineItem {
  const TimelineMessage(
    this.value, {
    this.step = 0,
    this.usage,
    this.firstTokenAtEpochMs,
    this.stepStartedAtEpochMs,
  });

  final ChatMessage value;
  final int step;
  final TokenUsage? usage;
  final int? firstTokenAtEpochMs;

  /// The owning `step/start` event's logged time; null when that event fell
  /// outside the folded window.
  final int? stepStartedAtEpochMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TimelineMessage &&
          other.value == value &&
          other.step == step &&
          other.usage == usage &&
          other.firstTokenAtEpochMs == firstTokenAtEpochMs &&
          other.stepStartedAtEpochMs == stepStartedAtEpochMs);

  @override
  int get hashCode => Object.hash(
    'message',
    value,
    step,
    usage,
    firstTokenAtEpochMs,
    stepStartedAtEpochMs,
  );
}

/// Turn boundary from a logged `turn/start`; groups the transcript
/// ledger-style.
///
/// [usage] is the sum of the turn's per-step token accounting, folded when
/// the matching `turn/end` closes the turn. It is a convenience total over
/// figures the host did send — never an estimate.
///
/// [startedAtEpochMs] and [endedAtEpochMs] are the `turn/start` and
/// `turn/end` events' own logged times, so a surface can show the turn's
/// wall time. The end stays null until the matching `turn/end` folds, and
/// either stays null when a window cut removed its event.
final class TimelineTurnBoundary extends TimelineItem {
  const TimelineTurnBoundary(
    this.turn, {
    this.usage,
    this.startedAtEpochMs,
    this.endedAtEpochMs,
  });

  final int turn;
  final TokenUsage? usage;
  final int? startedAtEpochMs;
  final int? endedAtEpochMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TimelineTurnBoundary &&
          other.turn == turn &&
          other.usage == usage &&
          other.startedAtEpochMs == startedAtEpochMs &&
          other.endedAtEpochMs == endedAtEpochMs);

  @override
  int get hashCode =>
      Object.hash('turn', turn, usage, startedAtEpochMs, endedAtEpochMs);
}

/// Context compaction from a logged `compaction/summary` event.
final class TimelineCompaction extends TimelineItem {
  const TimelineCompaction({
    required this.id,
    this.shadowedCount,
    this.shadowedTokens,
    this.summary,
  });

  final String id;

  /// Number of history items shadowed by this compaction; null if unavailable.
  final int? shadowedCount;

  /// Estimated tokens shadowed by this compaction; null if unavailable.
  final int? shadowedTokens;

  /// Markdown summary of compacted context; null if unavailable.
  /// Expandability is derived from `summary != null`.
  final String? summary;

  /// Whether this compaction summary can be expanded in the UI.
  bool get isExpandable => summary != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TimelineCompaction &&
          other.id == id &&
          other.shadowedCount == shadowedCount &&
          other.shadowedTokens == shadowedTokens &&
          other.summary == summary);

  @override
  int get hashCode =>
      Object.hash('compaction', id, shadowedCount, shadowedTokens, summary);
}

/// One host slash command from its logged `command/run` + `command/done`
/// pair. The run append opens the card; the done event resolves it in
/// place by [commandId] — success surfaces the host's result text, an
/// error the command's text (e.g. "This operation was aborted" when the
/// initiating connection dropped). Cards are direct log appends: no turn
/// wraps them, so they land in the group current at their run.
final class TimelineCommand extends TimelineItem {
  const TimelineCommand({
    required this.commandId,
    required this.name,
    this.args,
    this.status = CommandRunStatus.running,
    this.text,
  });

  final String commandId;
  final String name;
  final String? args;
  final CommandRunStatus status;
  final String? text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TimelineCommand &&
          other.commandId == commandId &&
          other.name == name &&
          other.args == args &&
          other.status == status &&
          other.text == text);

  @override
  int get hashCode =>
      Object.hash('command', commandId, name, args, status, text);
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
      identical(this, other) ||
      (other is TimelineContextInjection &&
          other.id == id &&
          other.text == text &&
          other.producerLabel == producerLabel &&
          other.isRecall == isRecall &&
          other.summary == summary);

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

/// One tool invocation, root or nested.
///
/// [step] is the logged step that owns the call, [parentCallId] the
/// enclosing root call when this call ran nested inside a code-dispatch
/// program (`tool/ptc-dispatch-start`), and [children] the nested calls it
/// dispatched in start order. [startedAtEpochMs] is the `tool/call` (or
/// dispatch-start) timestamp; the contract carries no settle timestamp on
/// the result event, so no duration is derived.
final class TimelineToolCall extends TimelineItem {
  const TimelineToolCall({
    required this.id,
    required this.name,
    this.arguments,
    this.result,
    this.isError = false,
    this.status = ToolRunStatus.running,
    this.step = 0,
    this.parentCallId,
    this.children = const <TimelineToolCall>[],
    this.startedAtEpochMs,
    this.presentation,
  });

  final String id;
  final String name;
  final String? arguments;
  final String? result;
  final bool isError;
  final ToolRunStatus status;
  final int step;

  /// Enclosing root call id for a nested dispatch; null on a root call.
  final String? parentCallId;

  /// Nested dispatches this call owns, in dispatch order.
  final List<TimelineToolCall> children;

  /// Unix epoch milliseconds the call was logged; null when unknown.
  final int? startedAtEpochMs;

  /// The tool's persisted result presentation (the `tool/result` event's
  /// `meta`), or null when the tool persisted none or the payload carries
  /// no known card. Null is the reference's own generic fallback.
  final ToolResultPresentation? presentation;

  /// Whether this call ran nested inside another call's code dispatch.
  bool get isNested => parentCallId != null;

  /// This call and every descendant, depth-first in dispatch order. Used by
  /// the ledger to render the subtool tree as a flat, selectable list.
  List<TimelineToolCall> get flattened {
    final out = <TimelineToolCall>[this];
    for (final child in children) {
      out.addAll(child.flattened);
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TimelineToolCall &&
          other.id == id &&
          other.name == name &&
          other.arguments == arguments &&
          other.result == result &&
          other.isError == isError &&
          other.status == status &&
          other.step == step &&
          other.parentCallId == parentCallId &&
          other.startedAtEpochMs == startedAtEpochMs &&
          other.presentation == presentation &&
          _listEquals(other.children, children));

  @override
  int get hashCode => Object.hash(
    'tool',
    id,
    name,
    arguments,
    result,
    isError,
    status,
    step,
    parentCallId,
    Object.hashAll(children),
    startedAtEpochMs,
    presentation,
  );
}

/// One hook audit row folded from a `hook/invoked` + `hook/result` pair
/// (log-only session events; paired by `handlerId`).
///
/// A blocking `PreToolUse` deny settles as `decision: 'deny'` here, so the
/// refusal has an audit trail in transcript order instead of reading as an
/// ordinary tool failure.
final class TimelineHookAudit extends TimelineItem {
  const TimelineHookAudit(this.audit);

  final HookAudit audit;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TimelineHookAudit && other.audit == audit);

  @override
  int get hashCode => Object.hash('hook', audit);
}

/// One member of a durable workflow run.
final class WorkflowMember {
  const WorkflowMember({
    required this.seq,
    required this.label,
    required this.childId,
    required this.status,
  });

  /// Member sequence inside the run.
  final int seq;

  final String label;

  /// The member's child session id, the jump target for its transcript.
  final String childId;

  final WorkflowRunStatus status;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkflowMember &&
          other.seq == seq &&
          other.label == label &&
          other.childId == childId &&
          other.status == status);

  @override
  int get hashCode => Object.hash(seq, label, childId, status);
}

/// One phase group inside a workflow run.
final class WorkflowPhase {
  const WorkflowPhase({
    required this.key,
    required this.phase,
    required this.members,
  });

  /// Collision-free identity key of the phase (the reference's
  /// `workflowPhaseKey`): `missing` for an omitted phase, else
  /// `value:<length>:<phase>`.
  final String key;

  /// The exact phase string; null is the absent field (distinct from an
  /// empty string).
  final String? phase;

  final List<WorkflowMember> members;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkflowPhase &&
          other.key == key &&
          other.phase == phase &&
          _listEquals(other.members, members));

  @override
  int get hashCode => Object.hash(key, phase, Object.hashAll(members));
}

/// One durable workflow run folded from the `tool-workflow/*` event family,
/// keyed by `runId`.
///
/// A history tail that carries only member/terminal updates stays pending —
/// no item is published — until the unique `tool-workflow/run-start`
/// arrives, matching the reference's conversation-node replay: `start`
/// anchors the node and `update` folds into it. A run whose turn closed
/// with no terminal event presents as `interrupted`, and the workflow tool's
/// own `tool/result` row is left untouched.
final class TimelineWorkflowRun extends TimelineItem {
  const TimelineWorkflowRun({
    required this.runId,
    required this.name,
    required this.status,
    required this.phases,
    this.stopReason,
  });

  final String runId;
  final String name;
  final WorkflowRunStatus status;

  /// The wire stop reason (`completed` / `cancelled` / `error`), or null
  /// while the run has no terminal event.
  final String? stopReason;

  /// Phase groups in first-seen phase order.
  final List<WorkflowPhase> phases;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TimelineWorkflowRun &&
          other.runId == runId &&
          other.name == name &&
          other.status == status &&
          other.stopReason == stopReason &&
          _listEquals(other.phases, phases));

  @override
  int get hashCode =>
      Object.hash(runId, name, status, stopReason, Object.hashAll(phases));
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
      identical(this, other) ||
      (other is TimelineApprovalRequest &&
          other.requestId == requestId &&
          other.sessionId == sessionId &&
          other.approvalId == approvalId &&
          other.toolName == toolName &&
          other.callId == callId &&
          other.reason == reason);

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
      identical(this, other) ||
      (other is TimelineQuestionRequest &&
          other.requestId == requestId &&
          _listEquals(other.questions, questions));

  @override
  int get hashCode =>
      Object.hash('question', requestId, Object.hashAll(questions));
}

final class TimelineQueue extends TimelineItem {
  const TimelineQueue({this.items = const <SessionQueueItem>[]});

  final List<SessionQueueItem> items;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TimelineQueue && _listEquals(other.items, items));

  @override
  int get hashCode => Object.hash('queue', Object.hashAll(items));
}

final class TimelineJobs extends TimelineItem {
  const TimelineJobs({this.jobs = const <JobView>[]});

  final List<JobView> jobs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TimelineJobs && _listEquals(other.jobs, jobs));

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
      identical(this, other) ||
      (other is TimelineError &&
          other.id == id &&
          other.message == message &&
          other.code == code);

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
      identical(this, other) ||
      (other is QuestionItem &&
          other.id == id &&
          other.question == question &&
          _listEquals(other.options, options) &&
          other.multiSelect == multiSelect &&
          other.detail == detail &&
          other.header == header &&
          _mapEquals(other.optionDescriptions, optionDescriptions) &&
          other.intent == intent);

  @override
  int get hashCode => Object.hash(
    id,
    question,
    Object.hashAll(options),
    multiSelect,
    detail,
    header,
    optionDescriptions.entries.fold<int>(
      0,
      (acc, entry) => acc ^ Object.hash(entry.key, entry.value),
    ),
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
      identical(this, other) ||
      (other is QuestionIntent &&
          other.kind == kind &&
          other.approve == approve);

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
      identical(this, other) ||
      (other is ApprovalAnswer &&
          other.requestId == requestId &&
          other.sessionId == sessionId &&
          other.approvalId == approvalId &&
          other.allowed == allowed);

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
      identical(this, other) ||
      (other is QuestionAnswer &&
          other.questionId == questionId &&
          _listEquals(other.selectedOptions, selectedOptions) &&
          other.customText == customText);

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
      identical(this, other) ||
      (other is SessionQueueItem &&
          other.itemId == itemId &&
          other.placement == placement &&
          other.text == text);

  @override
  int get hashCode => Object.hash(itemId, placement, text);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}
