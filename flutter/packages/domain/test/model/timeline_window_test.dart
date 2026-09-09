import 'package:test/test.dart';

import 'package:domain/model/chat_message.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/timeline_window.dart';

void main() {
  group('TimelineWindow', () {
    const msg = ChatMessage(
      id: 'm1',
      sessionId: 's1',
      role: MessageRole.user,
      text: 'hello',
    );

    test('defaults are equal and have consistent hashCode', () {
      const a = TimelineWindow();
      const b = TimelineWindow();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.items, isEmpty);
      expect(a.hasMoreOlder, isFalse);
      expect(a.isLoadingOlder, isFalse);
      expect(a.isLoading, isFalse);
    });

    test('equal when all properties match including collection items', () {
      const a = TimelineWindow(
        items: [TimelineMessage(msg), TimelineTurnBoundary(1)],
        hasMoreOlder: true,
        isLoadingOlder: false,
        isLoading: false,
      );
      const b = TimelineWindow(
        items: [TimelineMessage(msg), TimelineTurnBoundary(1)],
        hasMoreOlder: true,
        isLoadingOlder: false,
        isLoading: false,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('identical instance is equal', () {
      const a = TimelineWindow(
        items: [TimelineMessage(msg)],
        hasMoreOlder: true,
      );

      expect(a, equals(a));
    });

    test('unequal when items differ', () {
      const a = TimelineWindow(items: [TimelineMessage(msg)]);
      const b = TimelineWindow(items: [TimelineTurnBoundary(1)]);
      const c = TimelineWindow(items: []);

      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(c)));
    });

    test('unequal when flags differ', () {
      const base = TimelineWindow();

      expect(base, isNot(equals(const TimelineWindow(hasMoreOlder: true))));
      expect(base, isNot(equals(const TimelineWindow(isLoadingOlder: true))));
      expect(base, isNot(equals(const TimelineWindow(isLoading: true))));
    });
  });
}
