import 'package:domain/model/chat_message.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/chat/timeline_grouping.dart';

TimelineMessage message(String id) => TimelineMessage(
      ChatMessage(id: id, sessionId: 's1', role: MessageRole.user, text: id),
    );

TimelineMessage messageWith({
  required String id,
  required MessageRole role,
  required String text,
}) =>
    TimelineMessage(
      ChatMessage(id: id, sessionId: 's1', role: role, text: text),
    );

void main() {
  test('items before the first boundary form the null group', () {
    final groups = groupTimelineByTurn(<TimelineItem>[message('a'), message('b')]);

    expect(groups, hasLength(1));
    expect(groups.single.turn, isNull);
    expect(
      groups.single.items
          .whereType<TimelineMessage>()
          .map((item) => item.value.id)
          .toList(),
      <String>['a', 'b'],
    );
  });

  test('boundaries split groups and land only in the heading', () {
    final groups = groupTimelineByTurn(<TimelineItem>[
      const TimelineTurnBoundary(1),
      message('a'),
      const TimelineTurnBoundary(2),
      message('b'),
      message('c'),
    ]);

    expect(groups, hasLength(3));
    expect(groups[0].turn, isNull);
    expect(groups[0].items, isEmpty);
    expect(groups[1].turn, 1);
    expect(
      groups[1].items
          .whereType<TimelineMessage>()
          .map((item) => item.value.id)
          .toList(),
      <String>['a'],
    );
    expect(groups[2].turn, 2);
    expect(
      groups[2].items
          .whereType<TimelineMessage>()
          .map((item) => item.value.id)
          .toList(),
      <String>['b', 'c'],
    );
  });

  test('a boundary without rows keeps its group for the outline number', () {
    final groups = groupTimelineByTurn(<TimelineItem>[
      const TimelineTurnBoundary(1),
      message('a'),
      const TimelineTurnBoundary(2),
    ]);

    expect(groups, hasLength(3));
    expect(groups[2].turn, 2);
    expect(groups[2].items, isEmpty);
  });

  test('prompt preview echoes the first user message folded to one line', () {
    final preview = promptPreview(<TimelineItem>[
      messageWith(id: 'u1', role: MessageRole.assistant, text: 'prior answer'),
      messageWith(id: 'u2', role: MessageRole.user, text: 'first line\nsecond line'),
      messageWith(id: 'u3', role: MessageRole.user, text: 'later prompt'),
    ]);

    expect(preview, 'first line');
  });

  test('prompt preview truncates long prompts and returns null without user rows',
      () {
    final long = promptPreview(<TimelineItem>[
      messageWith(id: 'u1', role: MessageRole.user, text: 'x' * 100),
    ]);
    final none = promptPreview(<TimelineItem>[
      messageWith(id: 'a1', role: MessageRole.assistant, text: 'answer'),
    ]);

    expect(long?.length, 60);
    final longValue = long;
    if (longValue != null) {
      expect(longValue.substring(longValue.length - 1), '…');
    }
    expect(none, isNull);
  });
}
