import 'package:test/test.dart';

import 'package:domain/domain.dart';

void main() {
  group('ChatRepository contract vocabulary', () {
    test('QuestionEvidence equality and answers collection comparison', () {
      const ans1 = QuestionAnswer(questionId: 'q1', selectedOptions: ['yes']);
      const a = QuestionEvidence(sessionId: 'sess-1', answers: [ans1]);
      const b = QuestionEvidence(
        sessionId: 'sess-1',
        answers: [
          QuestionAnswer(questionId: 'q1', selectedOptions: ['yes']),
        ],
      );
      const diff = QuestionEvidence(sessionId: 'sess-1', answers: []);

      expect(a, equals(a));
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    test('CreateSessionRequest equality and hashCode', () {
      const a = CreateSessionRequest(
        sessionId: 's1',
        workspaceId: 'w1',
        cwd: '/path',
        agentPreset: 'preset',
      );
      const b = CreateSessionRequest(
        sessionId: 's1',
        workspaceId: 'w1',
        cwd: '/path',
        agentPreset: 'preset',
      );
      const diff = CreateSessionRequest(sessionId: 's2');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    test('QueueUpdateRequest equality and hashCode', () {
      const a = QueueUpdateRequest(
        sessionId: 's1',
        itemId: 'item-1',
        kind: QueueUpdateKind.remove,
      );
      const b = QueueUpdateRequest(
        sessionId: 's1',
        itemId: 'item-1',
        kind: QueueUpdateKind.remove,
      );
      const diff = QueueUpdateRequest(
        sessionId: 's1',
        itemId: 'item-1',
        kind: QueueUpdateKind.steer,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    test('ConnectionState and HostDescription equality', () {
      const host = HostDescription(home: '/home/tester');
      const hostCopy = HostDescription(home: '/home/tester');
      const hostDiff = HostDescription(home: '/home/other');

      expect(host, equals(hostCopy));
      expect(host.hashCode, equals(hostCopy.hashCode));
      expect(host, isNot(equals(hostDiff)));

      const connConnected = ConnectionState(
        phase: ConnectionPhase.connected,
        hostDescription: host,
        generation: 1,
      );
      const connCopy = ConnectionState(
        phase: ConnectionPhase.connected,
        hostDescription: host,
        generation: 1,
      );
      const connDisconnected = ConnectionState(
        phase: ConnectionPhase.disconnected,
      );

      expect(connConnected, equals(connCopy));
      expect(connConnected.hashCode, equals(connCopy.hashCode));
      expect(connConnected.isConnected, isTrue);
      expect(connDisconnected.isConnected, isFalse);
      expect(connConnected, isNot(equals(connDisconnected)));
    });

    test('a host fact with no source is absent, never defaulted', () {
      // The 0.1.1 `host/describe` facts are gone at 0.1.5: cwd/provider/model
      // are per-session, and attachedSessions/canOpenPath are published
      // nowhere. The type carries only the ready frame's home plus a version
      // no pinned route supplies — which stays null rather than fabricating a
      // default.
      const host = HostDescription(home: '/home/tester');

      expect(host.version, isNull);
      expect(host, equals(const HostDescription(home: '/home/tester')));
      expect(
        host,
        isNot(equals(const HostDescription(home: '/home/tester', version: ''))),
      );
    });

    test('BackendConfig equality and copyWith', () {
      final uri = Uri.parse('http://localhost:3080');
      final a = BackendConfig(id: 'b1', label: 'Local', baseUri: uri);
      final b = BackendConfig(id: 'b1', label: 'Local', baseUri: uri);
      final diff = a.copyWith(label: 'Remote');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
      expect(diff.label, equals('Remote'));
      expect(diff.id, equals('b1'));
      expect(diff.baseUri, equals(uri));
    });
  });
}
