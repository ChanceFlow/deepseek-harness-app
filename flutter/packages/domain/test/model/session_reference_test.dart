/// Value equality and the row-title rule of `SessionReferenceCandidate`.
library;

import 'package:test/test.dart';

import 'package:domain/model/session_reference.dart';

void main() {
  group('SessionReferenceCandidate', () {
    const base = SessionReferenceCandidate(
      sessionId: 'session-2',
      label: 'Release notes',
      displayTitle: 'Release notes',
      cwd: '/home/tester/project',
      sameWorkspace: true,
      createdAtEpochMs: 1700000000000,
      mention: '@[Release notes](dsh-session:eyJzZXNzaW9uLTIifQ)',
    );

    test('equality and hashCode cover every host-reported field', () {
      const same = SessionReferenceCandidate(
        sessionId: 'session-2',
        label: 'Release notes',
        displayTitle: 'Release notes',
        cwd: '/home/tester/project',
        sameWorkspace: true,
        createdAtEpochMs: 1700000000000,
        mention: '@[Release notes](dsh-session:eyJzZXNzaW9uLTIifQ)',
      );

      expect(base, equals(same));
      expect(base.hashCode, equals(same.hashCode));
      expect(
        base,
        isNot(
          equals(
            const SessionReferenceCandidate(
              sessionId: 'session-3',
              label: 'Release notes',
              displayTitle: 'Release notes',
              cwd: '/home/tester/project',
              sameWorkspace: true,
              createdAtEpochMs: 1700000000000,
              mention: '@[Release notes](dsh-session:eyJzZXNzaW9uLTIifQ)',
            ),
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            const SessionReferenceCandidate(
              sessionId: 'session-2',
              label: 'Release notes',
              displayTitle: 'Release notes',
              cwd: '/tmp/other',
              sameWorkspace: true,
              createdAtEpochMs: 1700000000000,
              mention: '@[Release notes](dsh-session:eyJzZXNzaW9uLTIifQ)',
            ),
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            const SessionReferenceCandidate(
              sessionId: 'session-2',
              label: 'Release notes',
              displayTitle: 'Release notes',
              cwd: '/home/tester/project',
              sameWorkspace: false,
              createdAtEpochMs: 1700000000000,
              mention: '@[Release notes](dsh-session:eyJzZXNzaW9uLTIifQ)',
            ),
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            const SessionReferenceCandidate(
              sessionId: 'session-2',
              label: 'Release notes',
              displayTitle: 'Release notes',
              cwd: '/home/tester/project',
              sameWorkspace: true,
              createdAtEpochMs: 1700000000001,
              mention: '@[Release notes](dsh-session:eyJzZXNzaW9uLTIifQ)',
            ),
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            const SessionReferenceCandidate(
              sessionId: 'session-2',
              label: 'Release notes',
              displayTitle: 'Release notes',
              cwd: '/home/tester/project',
              sameWorkspace: true,
              createdAtEpochMs: 1700000000000,
              mention: '@[Release notes](dsh-session:eyJzZXNzaW9uLTMifQ)',
            ),
          ),
        ),
      );
    });

    test('a projected display title wins over the id-backed label', () {
      const child = SessionReferenceCandidate(
        sessionId: 'session-3',
        label: 'session-3',
        displayTitle: 'parser child',
        sameWorkspace: false,
        createdAtEpochMs: 1700000000001,
        mention: '@[parser child](dsh-session:eyJzZXNzaW9uLTMifQ)',
      );

      expect(child.rowTitle, 'parser child');
    });

    test('an absent display title falls back to the label', () {
      const untitled = SessionReferenceCandidate(
        sessionId: 'session-3',
        label: 'session-3',
        sameWorkspace: true,
        createdAtEpochMs: 1700000000001,
        mention: '@[session-3](dsh-session:eyJzZXNzaW9uLTMifQ)',
      );

      expect(untitled.rowTitle, 'session-3');
      expect(untitled.cwd, isNull);
    });
  });
}
