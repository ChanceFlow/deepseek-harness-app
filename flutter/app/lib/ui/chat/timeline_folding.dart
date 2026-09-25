/// Timeline activity folding: one disclosure per execution phase, holding that
/// phase's thoughts, injected context and tool calls in transcript order.
///
/// The phase's label and live detail come from the reference chat grouping's
/// own model ([deriveProcessActivity] in `process_activity.dart`); this module
/// owns only which rows a phase holds.
library;

import 'package:domain/model/chat_message.dart';
import 'package:domain/model/timeline_item.dart';

/// One folded execution phase — the thoughts, injected context rows and tool
/// calls that ran between two transcript anchors, in transcript order.
///
/// The card owns the phase's only disclosure: its members render inline when
/// the card opens, never as a fold of their own.
final class TimelineActivityGroup {
  const TimelineActivityGroup({
    required this.id,
    required this.entries,
    this.closed = true,
  });

  /// Stable identity of the phase: the first member's own id.
  final String id;

  /// Phase members in transcript order: reasoning-only assistant messages,
  /// [TimelineContextInjection] rows and [TimelineToolCall] rows.
  final List<TimelineItem> entries;

  /// Whether the phase's Turn has ended. A closed phase keeps its settled
  /// label and stops shimmering; an open one names what is running.
  final bool closed;

  /// The phase's tool calls in order.
  List<TimelineToolCall> get calls =>
      entries.whereType<TimelineToolCall>().toList(growable: false);

  /// The phase's merged thought, when it reasoned.
  TimelineMessage? get thought {
    for (final entry in entries) {
      if (entry is TimelineMessage) return entry;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is TimelineActivityGroup &&
      other.id == id &&
      other.closed == closed &&
      _listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hash(id, closed, Object.hashAll(entries));

  @override
  String toString() =>
      'TimelineActivityGroup(id: $id, closed: $closed, entries: $entries)';

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Folds each execution phase into one [TimelineActivityGroup]: consecutive
/// reasoning-only assistant messages merge into a single thought, and the
/// injected-context rows that used to delimit a phase join it instead — an
/// injection is a step in the run, so it gets a tool call's treatment rather
/// than a row of its own.
///
/// A reply-bearing step whose own reasoning is non-empty contributes that
/// reasoning to the phase **and** renders its reply as a row: the reference
/// emits both from the one step (`process-groups.ts`: the node is pushed as a
/// `reasoning` member, then the group flushes and the same node is emitted as
/// the `response`), so a reader who opens the phase sees the thinking that
/// produced the answer they just read.
///
/// A phase of one member is emitted as that member, so a lone tool call, a
/// lone thought and a lone injection keep their own row.
List<Object> foldTimelineActivities(List<TimelineItem> items) {
  final result = <Object>[];
  // The phase's steps in transcript order, and the phase's thoughts collected
  // across them: a phase is one reasoning run spread over its steps, so its
  // thoughts merge into a single block at the position of the first one
  // (the "Thought 12s" total the timeline has always shown), while injections
  // and tool calls keep their own order.
  final steps = <TimelineItem>[];
  final thoughts = <TimelineMessage>[];
  var thoughtInsertAt = 0;
  // Identity of the phase's first member. The merged thought borrows the
  // newest chunk's id while it streams, so keying the card on it would remount
  // — and collapse — the card on every chunk; the first member's id is stable.
  String? firstMemberId;
  // Whether the Turn the phase belongs to has ended, read off the boundary that
  // opened it. A timeline whose window cut the boundary is read as settled.
  var turnEnded = true;

  /// Emit the phase being collected.
  ///
  /// [tail] marks the phase the Turn's own log ends on. The reference closes
  /// every group as soon as any node follows it and leaves only the trailing
  /// one live (`process-groups.ts` `flush`), so a phase with an answer or a
  /// marker after it wears its settled label however open its Turn still is.
  void flushPhase({bool tail = false}) {
    if (steps.isEmpty && thoughts.isEmpty) return;
    final entries = <TimelineItem>[];
    if (thoughts.isNotEmpty) {
      entries
        ..addAll(steps.take(thoughtInsertAt))
        ..add(thoughts.length == 1 ? thoughts.first : _mergeThoughts(thoughts))
        ..addAll(steps.skip(thoughtInsertAt));
    } else {
      entries.addAll(steps);
    }
    result.add(
      entries.length == 1
          ? entries.first
          : TimelineActivityGroup(
              id: firstMemberId!,
              entries: List<TimelineItem>.unmodifiable(entries),
              closed: !tail || turnEnded,
            ),
    );
    steps.clear();
    thoughts.clear();
    thoughtInsertAt = 0;
    firstMemberId = null;
  }

  for (final item in items) {
    switch (item) {
      case TimelineTurnBoundary(:final endSeq):
        flushPhase();
        // The phase that follows belongs to this Turn, so its settled state
        // comes from the boundary the reducer filled when `turn/end` folded.
        turnEnded = endSeq != null;
        result.add(item);
      case TimelineToolCall():
      case TimelineContextInjection():
        firstMemberId ??= _entryId(item);
        steps.add(item);
      case TimelineMessage(:final value):
        if (value.role == MessageRole.assistant) {
          final hasReply = value.text.trim().isNotEmpty;
          final reasoning = value.reasoning;
          final hasReasoning = reasoning != null && reasoning.trim().isNotEmpty;
          if (hasReasoning) {
            firstMemberId ??= _entryId(item);
            if (thoughts.isEmpty) thoughtInsertAt = steps.length;
            thoughts.add(hasReply ? _reasoningOnly(item, value) : item);
          }
          if (hasReply) {
            // The reply is its own row, and it ends the phase — the reasoning
            // above stays with the work that produced it. The row carries only
            // the reply: the reference emits this step as the phase's
            // `response` part, which suppresses its reasoning blocks
            // (`AssistantMarkdown.tsx`), so one thought never renders twice.
            flushPhase();
            result.add(hasReasoning ? _replyOnly(item, value) : item);
          } else if (!hasReasoning) {
            // An assistant message with neither reply text nor reasoning is a
            // protocol artifact: it publishes no row and does not split the
            // phase.
          }
        } else {
          flushPhase();
          result.add(item);
        }
      case TimelineCommand():
      case TimelineCompaction():
      case TimelineQuestionRequest():
      case TimelineApprovalRequest():
      case TimelineError():
      case TimelineQueue():
      case TimelineJobs():
      case TimelineHookAudit():
      case TimelineWorkflowRun():
        flushPhase();
        result.add(item);
    }
  }

  // The phase the log ends on: the Turn's trailing one, which is the only phase
  // that may still be live.
  flushPhase(tail: true);
  return result;
}

/// The reasoning half of one step, for the phase it reasons inside: the same
/// identity, seq and timing, with the reply text removed so the member renders
/// as the thought it is.
TimelineMessage _reasoningOnly(TimelineItem item, ChatMessage value) =>
    TimelineMessage(
      ChatMessage(
        id: value.id,
        sessionId: value.sessionId,
        role: value.role,
        text: '',
        reasoning: value.reasoning,
        reasoningDuration: value.reasoningDuration,
        streaming: value.streaming,
        createdAtEpochMs: value.createdAtEpochMs,
        images: value.images,
        seq: value.seq,
      ),
    );

/// The reply half of one step whose reasoning joined its phase: the same
/// identity, seq and timing, with the reasoning removed so the reader does not
/// read the same thought twice — once behind the phase's fold and once over the
/// answer.
TimelineMessage _replyOnly(TimelineItem item, ChatMessage value) =>
    TimelineMessage(
      ChatMessage(
        id: value.id,
        sessionId: value.sessionId,
        role: value.role,
        text: value.text,
        streaming: value.streaming,
        createdAtEpochMs: value.createdAtEpochMs,
        images: value.images,
        seq: value.seq,
      ),
    );

/// One thought block from a phase's reasoning-only messages: the last
/// message's identity and seq, every reasoning text joined, the durations
/// summed, and streaming when any constituent still streamed.
TimelineMessage _mergeThoughts(List<TimelineMessage> thoughts) {
  final last = thoughts.last.value;
  Duration? totalDuration;
  for (final thought in thoughts) {
    final duration = thought.value.reasoningDuration;
    if (duration != null) {
      totalDuration = (totalDuration ?? Duration.zero) + duration;
    }
  }
  final mergedReasoning = thoughts
      .map((m) => m.value.reasoning)
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .join('\n\n');

  return TimelineMessage(
    ChatMessage(
      id: last.id,
      sessionId: last.sessionId,
      role: MessageRole.assistant,
      text: '',
      reasoning: mergedReasoning,
      reasoningDuration: totalDuration,
      streaming: thoughts.any((m) => m.value.streaming),
      createdAtEpochMs: last.createdAtEpochMs,
      images: last.images,
      seq: last.seq,
    ),
  );
}

/// The phase's identity: its first member's own id.
String _entryId(TimelineItem item) => switch (item) {
  TimelineMessage(:final value) => value.id,
  TimelineContextInjection(:final id) => id,
  TimelineToolCall(:final id) => id,
  TimelineTurnBoundary(:final turn) => 'turn:$turn',
  TimelineCompaction(:final id) => id,
  TimelineCommand(:final commandId) => commandId,
  TimelineQuestionRequest(:final requestId) => requestId,
  TimelineApprovalRequest(:final requestId) => requestId,
  TimelineError(:final id) => id,
  TimelineQueue() => 'queue',
  TimelineJobs() => 'jobs',
  TimelineHookAudit(:final audit) => audit.handlerId,
  TimelineWorkflowRun(:final runId) => runId,
};
