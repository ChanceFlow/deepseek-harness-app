/// Tests for the `agent/inbox/spliced` steering classification.
///
/// The reference replays durable inbox splices to tell a human message
/// admitted into a live turn from an ordinary user turn
/// (`reference/deepseek-harness/packages/client/ui-chat/src/client/model/
/// steering-history.ts`), over the host-owned event
/// `SessionEventMap['agent/inbox/spliced']`
/// (`packages/core/agent/src/types.ts:96-102`).
library;

import 'package:domain/model/timeline_item.dart';
import 'package:network/rpc_envelope.dart';
import 'package:test/test.dart';

import 'package:harness_adapter/src/timeline_reducer.dart';

JsonMap _event(int seq, String type, JsonMap data) => <String, Object?>{
  'type': type,
  'seq': seq,
  'time': 1000 + seq,
  'data': data,
};

JsonMap _textBlock(String text) => <String, Object?>{
  'type': 'text',
  'text': text,
};

/// One `UserMessage` identity as `agent/inbox/spliced` carries it.
JsonMap _pending(String id) => <String, Object?>{
  'id': id,
  'source': <String, Object?>{'kind': 'user'},
  'content': <Object?>[_textBlock(id)],
};

JsonMap _userMessage(int seq, String id) =>
    _event(seq, 'user/message', <String, Object?>{
      'id': id,
      'source': <String, Object?>{'kind': 'user'},
      'content': <Object?>[_textBlock('hello from $id')],
    });

JsonMap _splice(
  int seq, {
  required String target,
  required int start,
  int? removedCount,
  List<String> inserted = const <String>[],
  String? outcome,
}) => _event(seq, 'agent/inbox/spliced', <String, Object?>{
  'target': target,
  'start': start,
  if (removedCount != null) 'removedCount': removedCount,
  'inserted': inserted.map(_pending).toList(),
  if (outcome != null) 'outcome': outcome,
});

List<TimelineMessage> _messages(TimelineReducer reducer) =>
    reducer.snapshot().whereType<TimelineMessage>().toList();

/// Feeds one durable event through the live frame carrier.
void _ingest(TimelineReducer reducer, JsonMap event) {
  reducer.ingestFrame(
    ServerRequest(
      rpcId: 'rpc-${event['seq']}',
      method: 'session/event',
      payload: <String, Object?>{'type': 'session/event', 'event': event},
    ),
  );
}

void main() {
  group('agent/inbox/spliced steering classification', () {
    test('a message removed from next-step is steering when it arrives', () {
      // Enqueue two next-step entries, then claim the first by replacing it
      // with nothing; the later user/message that names it is steering.
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          _splice(
            1,
            target: 'next-step',
            start: 0,
            inserted: <String>['m1', 'm2'],
          ),
          _splice(2, target: 'next-step', start: 0, removedCount: 1),
          _userMessage(3, 'm1'),
          _userMessage(4, 'm2'),
        ]);

      final messages = _messages(reducer);
      expect(messages, hasLength(2));
      expect(messages[0].value.id, 'm1');
      expect(messages[0].steering, isTrue);
      expect(messages[1].value.id, 'm2');
      expect(messages[1].steering, isFalse);
    });

    test('a next-turn claim is not steering', () {
      // Only the next-step list feeds a running turn; a next-turn claim wakes
      // a new one.
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          _splice(1, target: 'next-turn', start: 0, inserted: <String>['m1']),
          _splice(2, target: 'next-turn', start: 0, removedCount: 1),
          _userMessage(3, 'm1'),
        ]);

      expect(_messages(reducer).single.steering, isFalse);
    });

    test('a canceled removal does not claim', () {
      // `outcome: 'canceled'` is the host discarding the entries rather than
      // admitting them.
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          _splice(1, target: 'next-step', start: 0, inserted: <String>['m1']),
          _splice(
            2,
            target: 'next-step',
            start: 0,
            removedCount: 1,
            outcome: 'canceled',
          ),
          _userMessage(3, 'm1'),
        ]);

      expect(_messages(reducer).single.steering, isFalse);
    });

    test('a re-inserted identity is no longer claimed', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          _splice(1, target: 'next-step', start: 0, inserted: <String>['m1']),
          _splice(2, target: 'next-step', start: 0, removedCount: 1),
          _splice(3, target: 'next-step', start: 0, inserted: <String>['m1']),
          _userMessage(4, 'm1'),
        ]);

      expect(_messages(reducer).single.steering, isFalse);
    });

    test('an ordinary user turn is never steering', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[_userMessage(1, 'm1')]);

      expect(_messages(reducer).single.steering, isFalse);
    });

    test('a claim is consumed by the message that names it', () {
      // The same id cannot classify a second row.
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          _splice(1, target: 'next-step', start: 0, inserted: <String>['m1']),
          _splice(2, target: 'next-step', start: 0, removedCount: 1),
          _userMessage(3, 'm1'),
          _userMessage(4, 'm1'),
        ]);

      final messages = _messages(reducer);
      expect(messages.map((message) => message.steering), <bool>[true, false]);
    });

    test('ingesting one event at a time matches a replay', () {
      final events = <JsonMap>[
        _splice(1, target: 'next-step', start: 0, inserted: <String>['m1']),
        _splice(2, target: 'next-step', start: 0, removedCount: 1),
        _userMessage(3, 'm1'),
      ];
      final replayed = TimelineReducer('s1')..reset(events);
      final streamed = TimelineReducer('s1');
      for (final event in events) {
        _ingest(streamed, event);
      }

      expect(
        _messages(streamed).single.steering,
        _messages(replayed).single.steering,
      );
      expect(_messages(streamed).single.steering, isTrue);
    });

    test('a splice with no target fails loud', () {
      final reducer = TimelineReducer('s1');
      expect(
        () => _ingest(
          reducer,
          _event(1, 'agent/inbox/spliced', <String, Object?>{
            'start': 0,
            'inserted': <Object?>[],
          }),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('a splice whose inserted entry has no id fails loud', () {
      final reducer = TimelineReducer('s1');
      expect(
        () => _ingest(
          reducer,
          _event(1, 'agent/inbox/spliced', <String, Object?>{
            'target': 'next-step',
            'start': 0,
            'inserted': <Object?>[
              <String, Object?>{
                'source': <String, Object?>{'kind': 'user'},
              },
            ],
          }),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
