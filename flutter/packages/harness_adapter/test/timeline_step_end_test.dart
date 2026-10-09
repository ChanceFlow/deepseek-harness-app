/// Tests for the `step/end` timeline boundary.
///
/// The stats fold already counts a step at `step/end`
/// (`session_stats_fold.dart`); this is the timeline half, the reference's
/// `stepEnd` (`reference/deepseek-harness/packages/client/ui-trajectory/src/
/// client/trajectory-assistant-definition.ts:247`, located by
/// `ui-chat/src/client/conversation-nodes/turn-tail.ts:44`).
library;

import 'package:domain/model/timeline_item.dart';
import 'package:network/rpc_envelope.dart';
import 'package:test/test.dart';

import 'package:harness_adapter/src/adapter_diagnostics.dart';
import 'package:harness_adapter/src/timeline_reducer.dart';

JsonMap _event(int seq, String type, JsonMap data) => <String, Object?>{
  'type': type,
  'seq': seq,
  'time': 1000 + seq,
  'data': data,
};

JsonMap _turnStart(int seq, int turn) =>
    _event(seq, 'turn/start', <String, Object?>{'turn': turn});

JsonMap _stepEnd(int seq, int turn, int step) =>
    _event(seq, 'step/end', <String, Object?>{'turn': turn, 'step': step});

JsonMap _assistant(int seq, int turn, int step, String id) =>
    _event(seq, 'assistant/message', <String, Object?>{
      'turn': turn,
      'step': step,
      'message': <String, Object?>{
        'id': id,
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': 'answer $id'},
        ],
      },
    });

List<TimelineMessage> _messages(TimelineReducer reducer) =>
    reducer.snapshot().whereType<TimelineMessage>().toList();

void main() {
  group('step/end bounds its step', () {
    test('the owning message carries the step end time and seq', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          _turnStart(1, 1),
          _assistant(2, 1, 1, 'a1'),
          _stepEnd(3, 1, 1),
        ]);

      final message = _messages(reducer).single;
      expect(message.stepEndedAtEpochMs, 1003);
      expect(message.stepEndSeq, 3);
    });

    test('a later turn reusing the step number keeps its own end', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          _turnStart(1, 1),
          _assistant(2, 1, 1, 'a1'),
          _stepEnd(3, 1, 1),
          _turnStart(4, 2),
          _assistant(5, 2, 1, 'a2'),
          _stepEnd(6, 2, 1),
        ]);

      final messages = _messages(reducer);
      expect(messages, hasLength(2));
      expect(messages[0].value.id, 'a1');
      expect(messages[0].stepEndSeq, 3);
      expect(messages[1].value.id, 'a2');
      expect(messages[1].stepEndSeq, 6);
    });

    test('a step with no message never borrows the previous turn\'s row', () {
      // A cancelled step assembles no message, so the turn's own rows hold
      // nothing to bound; the previous turn's row must stay untouched.
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          _turnStart(1, 1),
          _assistant(2, 1, 1, 'a1'),
          _stepEnd(3, 1, 1),
          _turnStart(4, 2),
          _stepEnd(5, 2, 1),
        ]);

      final message = _messages(reducer).single;
      expect(message.value.id, 'a1');
      expect(message.stepEndSeq, 3);
    });

    test('a step end without its turn boundary folds nothing', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[_stepEnd(1, 1, 1)]);

      expect(reducer.snapshot(), isEmpty);
    });

    test('step/end no longer reports a coverage gap', () {
      final diagnostics = <AdapterDiagnostic>[];
      final reducer = TimelineReducer('s1', onDiagnostic: diagnostics.add);
      reducer.reset(<JsonMap>[
        _turnStart(1, 1),
        _assistant(2, 1, 1, 'a1'),
        _stepEnd(3, 1, 1),
      ]);

      expect(diagnostics, isEmpty);
    });
  });
}
