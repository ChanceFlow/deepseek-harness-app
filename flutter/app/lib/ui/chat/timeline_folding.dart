/// Cursor/Windsurf-style timeline activity folding: aggregates execution phases
/// (thoughts + tool calls) within a turn into compact activity chips.
library;

import 'package:domain/model/chat_message.dart';
import 'package:domain/model/timeline_item.dart';

/// A group of tool calls in an execution phase, rendered as a compact,
/// cursor-style collapsible section that is collapsed by default.
final class TimelineToolGroup {
  const TimelineToolGroup({required this.id, required this.calls});

  final String id;
  final List<TimelineToolCall> calls;

  @override
  bool operator ==(Object other) =>
      other is TimelineToolGroup &&
      other.id == id &&
      _listEquals(other.calls, calls);

  @override
  int get hashCode => Object.hash(id, Object.hashAll(calls));

  @override
  String toString() => 'TimelineToolGroup(id: $id, calls: $calls)';

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Folds execution phase activities (assistant reasoning thoughts and tool calls)
/// into merged thought blocks and [TimelineToolGroup]s.
List<Object> foldTimelineActivities(List<TimelineItem> items) {
  final result = <Object>[];
  final currentThoughts = <TimelineMessage>[];
  final currentTools = <TimelineToolCall>[];

  void flushPhase() {
    if (currentThoughts.isNotEmpty) {
      if (currentThoughts.length == 1) {
        result.add(currentThoughts.first);
      } else {
        final lastMessage = currentThoughts.last.value;
        Duration? totalDuration;
        for (final thought in currentThoughts) {
          final duration = thought.value.reasoningDuration;
          if (duration != null) {
            totalDuration = (totalDuration ?? Duration.zero) + duration;
          }
        }
        final mergedReasoning = currentThoughts
            .map((m) => m.value.reasoning)
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .join('\n\n');
        final streaming = currentThoughts.any((m) => m.value.streaming);

        result.add(
          TimelineMessage(
            ChatMessage(
              id: lastMessage.id,
              sessionId: lastMessage.sessionId,
              role: MessageRole.assistant,
              text: '',
              reasoning: mergedReasoning,
              reasoningDuration: totalDuration,
              streaming: streaming,
              createdAtEpochMs: lastMessage.createdAtEpochMs,
              images: lastMessage.images,
              seq: lastMessage.seq,
            ),
          ),
        );
      }
      currentThoughts.clear();
    }

    if (currentTools.isNotEmpty) {
      if (currentTools.length == 1) {
        result.add(currentTools.single);
      } else {
        result.add(
          TimelineToolGroup(
            id: currentTools.first.id,
            calls: List<TimelineToolCall>.unmodifiable(currentTools),
          ),
        );
      }
      currentTools.clear();
    }
  }

  for (final item in items) {
    switch (item) {
      case TimelineToolCall():
        currentTools.add(item);
      case TimelineMessage(:final value):
        if (value.role == MessageRole.assistant && value.text.trim().isEmpty) {
          final reasoning = value.reasoning;
          if (reasoning != null && reasoning.trim().isNotEmpty) {
            currentThoughts.add(item);
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
      case TimelineContextInjection():
        flushPhase();
        result.add(item);
    }
  }

  flushPhase();
  return result;
}
