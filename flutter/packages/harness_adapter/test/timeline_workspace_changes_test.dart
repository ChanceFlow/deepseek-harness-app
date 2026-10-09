/// Tests for the `workspace/changes` turn announcement.
///
/// The reference's `deliverables` node keeps the turn's latest event seq and
/// replaces an earlier one (`reference/deepseek-harness/packages/client/
/// ui-deliverables/src/client/turn-deliverables.ts:171,182`); the summary
/// itself stays on the host, served for that sequence while the Session
/// lives (`packages/deliverables/workspace-changes/src/types.ts:100-106`).
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

JsonMap _changes(int seq, int turn) =>
    _event(seq, 'workspace/changes', <String, Object?>{'turn': turn});

TimelineTurnBoundary _boundary(TimelineReducer reducer, int turn) => reducer
    .snapshot()
    .whereType<TimelineTurnBoundary>()
    .singleWhere((boundary) => boundary.turn == turn);

void main() {
  group('workspace/changes announces a turn\'s changed files', () {
    test('the turn boundary carries the announcement seq', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[_turnStart(1, 1), _changes(2, 1)]);

      expect(_boundary(reducer, 1).changesSeq, 2);
    });

    test('the latest announcement replaces an earlier one', () {
      // The host keeps only the latest summary per turn.
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[_turnStart(1, 1), _changes(2, 1), _changes(5, 1)]);

      expect(_boundary(reducer, 1).changesSeq, 5);
    });

    test('a turn that announced nothing carries no seq', () {
      final reducer = TimelineReducer('s1')..reset(<JsonMap>[_turnStart(1, 1)]);

      expect(_boundary(reducer, 1).changesSeq, isNull);
    });

    test('an announcement for another turn leaves this one alone', () {
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[_turnStart(1, 1), _turnStart(2, 2), _changes(3, 2)]);

      expect(_boundary(reducer, 1).changesSeq, isNull);
      expect(_boundary(reducer, 2).changesSeq, 3);
    });

    test('closing the turn keeps the announcement', () {
      // `turn/end` rebuilds the boundary; the change seq must survive it.
      final reducer = TimelineReducer('s1')
        ..reset(<JsonMap>[
          _turnStart(1, 1),
          _changes(2, 1),
          _event(3, 'turn/end', <String, Object?>{
            'turn': 1,
            'reason': <String, Object?>{'kind': 'completed'},
          }),
        ]);

      final boundary = _boundary(reducer, 1);
      expect(boundary.changesSeq, 2);
      expect(boundary.endSeq, 3);
    });

    test('an announcement with no turn boundary folds nothing', () {
      final reducer = TimelineReducer('s1')..reset(<JsonMap>[_changes(1, 1)]);

      expect(reducer.snapshot(), isEmpty);
    });

    test('workspace/changes no longer reports a coverage gap', () {
      final diagnostics = <AdapterDiagnostic>[];
      final reducer = TimelineReducer('s1', onDiagnostic: diagnostics.add);
      reducer.reset(<JsonMap>[_turnStart(1, 1), _changes(2, 1)]);

      expect(diagnostics, isEmpty);
    });
  });
}
