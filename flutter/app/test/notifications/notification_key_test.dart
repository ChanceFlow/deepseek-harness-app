/// Deterministic notification identity tests: the pinned FNV-1a id values
/// and the tag format. Pins guard the restart-orphan contract — a fresh
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
}
