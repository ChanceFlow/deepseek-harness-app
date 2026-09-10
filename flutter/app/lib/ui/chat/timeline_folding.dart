/// Cursor/Windsurf-style timeline activity folding: one collapsed card per
/// execution phase, holding that phase's thoughts, injected context and tool
/// calls in transcript order.
library;

import 'package:domain/model/chat_message.dart';
import 'package:domain/model/timeline_item.dart';

/// One folded execution phase — the thoughts, injected context rows and tool
/// calls that ran between two transcript anchors, in transcript order.
///
/// The card owns the phase's only disclosure: its members render inline when
/// the card opens, never as a fold of their own.
final class TimelineActivityGroup {
  const TimelineActivityGroup({required this.id, required this.entries});

  /// Stable identity of the phase: the first member's own id.
  final String id;

  /// Phase members in transcript order: reasoning-only assistant messages,
  /// [TimelineContextInjection] rows and [TimelineToolCall] rows.
  final List<TimelineItem> entries;

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

  /// True when the phase holds any tool call (the card's summary source).
  bool get hasCalls => entries.any((entry) => entry is TimelineToolCall);

  @override
  bool operator ==(Object other) =>
      other is TimelineActivityGroup &&
      other.id == id &&
      _listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hash(id, Object.hashAll(entries));

  @override
  String toString() => 'TimelineActivityGroup(id: $id, entries: $entries)';

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

  void flushPhase() {
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
            ),
    );
    steps.clear();
    thoughts.clear();
    thoughtInsertAt = 0;
    firstMemberId = null;
  }

  for (final item in items) {
    switch (item) {
      case TimelineToolCall():
      case TimelineContextInjection():
        firstMemberId ??= _entryId(item);
        steps.add(item);
      case TimelineMessage(:final value):
        if (value.role == MessageRole.assistant && value.text.trim().isEmpty) {
          final reasoning = value.reasoning;
          if (reasoning != null && reasoning.trim().isNotEmpty) {
            firstMemberId ??= _entryId(item);
            if (thoughts.isEmpty) thoughtInsertAt = steps.length;
            thoughts.add(item);
          }
          // Dropped if reasoning is null or empty (protocol artifact).
        } else {
          flushPhase();
          result.add(item);
        }
      case TimelineTurnBoundary():
      case TimelineQuestionRequest():
      case TimelineApprovalRequest():
      case TimelineCommand():
      case TimelineCompaction():
      case TimelineError():
      case TimelineQueue():
      case TimelineJobs():
        flushPhase();
        result.add(item);
    }
  }

  flushPhase();
  return result;
}

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
};
