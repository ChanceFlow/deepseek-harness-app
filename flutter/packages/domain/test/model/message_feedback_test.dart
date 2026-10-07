import 'package:test/test.dart';

import 'package:domain/model/message_feedback.dart';

void main() {
  group('Message feedback wire parsing', () {
    test('parses both ratings and both known ends of the category table', () {
      expect(
        messageFeedbackRatingFromWire('positive'),
        MessageFeedbackRating.positive,
      );
      expect(
        messageFeedbackRatingFromWire('negative'),
        MessageFeedbackRating.negative,
      );
      expect(
        messageFeedbackCategoryFromWire('task-result'),
        MessageFeedbackCategory.taskResult,
      );
      expect(
        messageFeedbackCategoryFromWire('security-privacy-permission'),
        MessageFeedbackCategory.securityPrivacyPermission,
      );
    });

    test('an unknown rating or category fails loud naming the value', () {
      expect(
        () => messageFeedbackRatingFromWire('maybe'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('maybe'),
          ),
        ),
      );
      expect(
        () => messageFeedbackCategoryFromWire('vibes'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('vibes'),
          ),
        ),
      );
    });
  });

  group('MessageFeedbackItem', () {
    const item = MessageFeedbackItem(
      messageId: 'm-1',
      rating: MessageFeedbackRating.positive,
      version: 'v-1',
      createdAtEpochMs: 100,
      updatedAtEpochMs: 200,
      note: 'clear answer',
      category: MessageFeedbackCategory.taskResult,
    );

    test('equality covers every field', () {
      const copy = MessageFeedbackItem(
        messageId: 'm-1',
        rating: MessageFeedbackRating.positive,
        version: 'v-1',
        createdAtEpochMs: 100,
        updatedAtEpochMs: 200,
        note: 'clear answer',
        category: MessageFeedbackCategory.taskResult,
      );
      expect(item, equals(copy));
      expect(item.hashCode, equals(copy.hashCode));

      const otherVersion = MessageFeedbackItem(
        messageId: 'm-1',
        rating: MessageFeedbackRating.positive,
        version: 'v-2',
        createdAtEpochMs: 100,
        updatedAtEpochMs: 200,
        note: 'clear answer',
        category: MessageFeedbackCategory.taskResult,
      );
      expect(item, isNot(equals(otherVersion)));
    });

    test('an uncategorized item with no note is distinct from a noted one', () {
      const bare = MessageFeedbackItem(
        messageId: 'm-1',
        rating: MessageFeedbackRating.negative,
        version: 'v-1',
        createdAtEpochMs: 100,
        updatedAtEpochMs: 100,
      );
      expect(bare.note, isNull);
      expect(bare.category, isNull);
      expect(bare, isNot(equals(item)));
    });
  });

  group('MessageFeedbackWrite', () {
    const item = MessageFeedbackItem(
      messageId: 'm-1',
      rating: MessageFeedbackRating.negative,
      version: 'v-2',
      createdAtEpochMs: 100,
      updatedAtEpochMs: 300,
    );

    test('a committed delete carries no item', () {
      const committed = MessageFeedbackCommitted(null);
      expect(committed.item, isNull);
      expect(committed, equals(const MessageFeedbackCommitted(null)));
      expect(committed, isNot(equals(const MessageFeedbackCommitted(item))));
    });

    test('a refusal carries its code and the authoritative item', () {
      const conflict = MessageFeedbackRefused(
        'version-conflict',
        current: item,
      );
      expect(conflict.code, 'version-conflict');
      expect(conflict.current, item);
      expect(
        conflict,
        equals(const MessageFeedbackRefused('version-conflict', current: item)),
      );
      expect(
        conflict,
        isNot(equals(const MessageFeedbackRefused('target-not-found'))),
      );
    });
  });
}
