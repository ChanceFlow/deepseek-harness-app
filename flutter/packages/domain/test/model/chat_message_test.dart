import 'package:test/test.dart';

import 'package:domain/model/attachment.dart';
import 'package:domain/model/chat_message.dart';

void main() {
  group('ChatMessage', () {
    const img1 = AttachmentRef(
      attachmentId: 'att-1',
      mediaType: 'image/png',
      bytes: 1024,
      width: 100,
      height: 100,
    );

    const base = ChatMessage(
      id: 'msg-1',
      sessionId: 'sess-1',
      role: MessageRole.user,
      text: 'hello world',
      reasoning: 'thinking',
      reasoningDuration: Duration(milliseconds: 500),
      streaming: false,
      createdAtEpochMs: 123456789,
      images: [img1],
      seq: 42,
    );

    test('identical instance is equal', () {
      expect(base, equals(base));
    });

    test('equal when all properties match including collection items', () {
      const copy = ChatMessage(
        id: 'msg-1',
        sessionId: 'sess-1',
        role: MessageRole.user,
        text: 'hello world',
        reasoning: 'thinking',
        reasoningDuration: Duration(milliseconds: 500),
        streaming: false,
        createdAtEpochMs: 123456789,
        images: [
          AttachmentRef(
            attachmentId: 'att-1',
            mediaType: 'image/png',
            bytes: 1024,
            width: 100,
            height: 100,
          ),
        ],
        seq: 42,
      );

      expect(base, equals(copy));
      expect(base.hashCode, equals(copy.hashCode));
    });

    test('unequal when any scalar field moves', () {
      expect(
        base,
        isNot(
          equals(
            const ChatMessage(
              id: 'msg-2',
              sessionId: 'sess-1',
              role: MessageRole.user,
              text: 'hello world',
            ),
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            const ChatMessage(
              id: 'msg-1',
              sessionId: 'sess-2',
              role: MessageRole.user,
              text: 'hello world',
            ),
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            const ChatMessage(
              id: 'msg-1',
              sessionId: 'sess-1',
              role: MessageRole.assistant,
              text: 'hello world',
            ),
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            const ChatMessage(
              id: 'msg-1',
              sessionId: 'sess-1',
              role: MessageRole.user,
              text: 'other text',
            ),
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            const ChatMessage(
              id: 'msg-1',
              sessionId: 'sess-1',
              role: MessageRole.user,
              text: 'hello world',
              reasoning: 'different reasoning',
            ),
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            const ChatMessage(
              id: 'msg-1',
              sessionId: 'sess-1',
              role: MessageRole.user,
              text: 'hello world',
              reasoningDuration: Duration(seconds: 2),
            ),
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            const ChatMessage(
              id: 'msg-1',
              sessionId: 'sess-1',
              role: MessageRole.user,
              text: 'hello world',
              streaming: true,
            ),
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            const ChatMessage(
              id: 'msg-1',
              sessionId: 'sess-1',
              role: MessageRole.user,
              text: 'hello world',
              createdAtEpochMs: 99999,
            ),
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            const ChatMessage(
              id: 'msg-1',
              sessionId: 'sess-1',
              role: MessageRole.user,
              text: 'hello world',
              seq: 99,
            ),
          ),
        ),
      );
    });

    test('unequal when images collection differs', () {
      const withDifferentImages = ChatMessage(
        id: 'msg-1',
        sessionId: 'sess-1',
        role: MessageRole.user,
        text: 'hello world',
        images: [],
      );

      expect(base, isNot(equals(withDifferentImages)));
    });
  });
}
