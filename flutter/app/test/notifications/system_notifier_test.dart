/// System-notifier payload tests: the notification-tap target codec.
library;

import 'package:app/notifications/system_notifier.dart' show NotificationTarget;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationTarget codec', () {
    test('round-trips backend + session ids', () {
      const target = NotificationTarget(backendId: 'b-1', sessionId: 's-2');
      expect(NotificationTarget.decode(target.encode()), target);
    });

    test('decodes a malformed payload to null', () {
      expect(NotificationTarget.decode('not json'), isNull);
      expect(NotificationTarget.decode('{"backendId":1}'), isNull);
      expect(NotificationTarget.decode('{"backendId":"b","sessionId":2}'), isNull);
      expect(NotificationTarget.decode('[]'), isNull);
    });

    test('ignores unknown extra fields', () {
      const target = NotificationTarget(backendId: 'b', sessionId: 's');
      expect(
        NotificationTarget.decode(
          '{"backendId":"b","sessionId":"s","extra":true}',
        ),
        target,
      );
    });
  });
}
