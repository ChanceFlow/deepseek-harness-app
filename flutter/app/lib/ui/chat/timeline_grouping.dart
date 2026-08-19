/// Trajectory-outline helpers over the folded timeline.
library;

import 'dart:convert';

import 'package:domain/model/chat_message.dart';
import 'package:domain/model/timeline_item.dart';

/// One trajectory-outline segment: everything after a turn boundary until
/// the next one. A null turn holds the rows before the first `turn/start`.
final class TimelineTurnGroup {
  const TimelineTurnGroup({required this.turn, required this.items});

  final int? turn;
  final List<TimelineItem> items;

  @override
  bool operator ==(Object other) =>
      other is TimelineTurnGroup &&
      other.turn == turn &&
      _listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(turn, Object.hashAll(items));
}

/// Partition a timeline into ledger-style turn groups. Boundary markers
/// land in their own group's heading (not its rows); boundaries with no
/// rows still produce a group so the outline keeps the turn number.
List<TimelineTurnGroup> groupTimelineByTurn(List<TimelineItem> items) {
  final groups = <TimelineTurnGroup>[];
  int? currentTurn;
  var current = <TimelineItem>[];

  void flush() {
    groups.add(TimelineTurnGroup(turn: currentTurn, items: current));
    current = <TimelineItem>[];
  }

  for (final item in items) {
    if (item is TimelineTurnBoundary) {
      flush();
      currentTurn = item.turn;
    } else {
      current.add(item);
    }
  }
  flush();
  return groups;
}

/// Request-header preview: the first user message of a group, folded to
/// one line and truncated — the trajectory outline's prompt echo.
String? promptPreview(List<TimelineItem> items, {int maxChars = 60}) {
  final userMessage = items
      .whereType<TimelineMessage>()
      .where((message) => message.value.role == MessageRole.user)
      .firstOrNull;
  final text = userMessage?.value.text;
  if (text == null) return null;
  final firstLine = const LineSplitter()
      .convert(text)
      .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '')
      .trim();
  if (firstLine.isEmpty) return null;
  if (firstLine.length <= maxChars) return firstLine;
  final clipped = firstLine.substring(0, maxChars - 1).trimRight();
  return '$clipped…';
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
