/// Deterministic notification identity tests: the pinned FNV-1a id values
/// and the tag formats. Pins guard the restart-orphan contract — a fresh
/// process must address the previous process's rows by exactly these ids.
library;

import 'package:app/notifications/notification_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('workingNotificationTag', () {
    test('is the backend/session key verbatim', () {
      expect(workingNotificationTag('b1', 's1'), 'b1/s1');
      expect(workingNotificationTag('', ''), '/');
    });
  });

  group('pendingNotificationTag', () {
    test('is the working tag plus the pending suffix', () {
      expect(pendingNotificationTag('b1', 's1'), 'b1/s1/pending');
      expect(pendingNotificationTag('', ''), '//pending');
    });

    test('shares no identity with the working row', () {
      expect(
        pendingNotificationTag('b1', 's1'),
        isNot(workingNotificationTag('b1', 's1')),
      );
    });
  });

  group('workingNotificationId', () {
    // FNV-1a (32-bit) over the UTF-8 tag bytes, masked to int32-positive.
    // Values computed with an independent implementation; do not "fix"
    // them against the Dart code.
    test('pins the FNV-1a values', () {
      expect(workingNotificationId('b1', 's1'), 449815053);
      expect(workingNotificationId('b1', 's2'), 399482196);
      expect(workingNotificationId('b2', 's1'), 791308770);
      expect(workingNotificationId('', ''), 705468254);
      expect(workingNotificationId('a', 'b'), 982414785);
    });

    test('hashes the UTF-8 bytes, not the code units', () {
      expect(workingNotificationId('backend-a', 'session-π'), 1815931314);
      expect(workingNotificationId('b', 'π'), 1410755481);
    });

    test('is deterministic and stays in the positive int32 range', () {
      final id = workingNotificationId('dsh-host', 'sess-1234567890abcdef');
      expect(id, workingNotificationId('dsh-host', 'sess-1234567890abcdef'));
      expect(id, inInclusiveRange(0, 0x7FFFFFFF));
    });

    test('the slash join separates backend from session', () {
      expect(
        workingNotificationId('b1', 's1'),
        isNot(workingNotificationId('b1/s', '1')),
      );
    });
  });

  group('pendingNotificationId', () {
    // Same pinned FNV-1a contract over the `/pending` tag.
    test('pins the FNV-1a values', () {
      expect(pendingNotificationId('b1', 's1'), 1157486345);
      expect(pendingNotificationId('b1', 's2'), 2003052184);
      expect(pendingNotificationId('b2', 's1'), 312027414);
      expect(pendingNotificationId('', ''), 1544178146);
      expect(pendingNotificationId('a', 'b'), 410454637);
    });

    test('hashes the UTF-8 bytes, not the code units', () {
      expect(pendingNotificationId('backend-a', 'session-π'), 907597958);
      expect(pendingNotificationId('b', 'π'), 1394289381);
    });

    test(
      'is deterministic, distinct from the working id, and int32-positive',
      () {
        for (final (backendId, sessionId) in <(String, String)>[
          ('dsh-host', 'sess-1234567890abcdef'),
          ('b1', 's1'),
          ('', ''),
        ]) {
          final id = pendingNotificationId(backendId, sessionId);
          expect(
            id,
            pendingNotificationId(backendId, sessionId),
            reason: 'deterministic for $backendId/$sessionId',
          );
          expect(
            id,
            isNot(workingNotificationId(backendId, sessionId)),
            reason: 'separate row from the work row',
          );
          expect(id, inInclusiveRange(0, 0x7FFFFFFF));
        }
      },
    );
  });
}
