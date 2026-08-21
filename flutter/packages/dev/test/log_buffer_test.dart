import 'package:dev/src/log_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogBuffer', () {
    test('keeps lines within capacity, oldest dropped', () {
      final buffer = LogBuffer(capacity: 3);
      buffer.append('a', at: DateTime(2026, 1, 1, 0, 0, 0, 1));
      buffer.append('b', at: DateTime(2026, 1, 1, 0, 0, 0, 2));
      buffer.append('c', at: DateTime(2026, 1, 1, 0, 0, 0, 3));
      buffer.append('d', at: DateTime(2026, 1, 1, 0, 0, 0, 4));
      expect(buffer.length, 3);
      final snap = buffer.snapshot();
      expect(snap, hasLength(3));
      expect(snap.first, contains('b'));
      expect(snap.last, contains('d'));
    });

    test('snapshot is unmodifiable and detached', () {
      final buffer = LogBuffer();
      buffer.append('x');
      final snap = buffer.snapshot();
      expect(() => snap.add('y'), throwsUnsupportedError);
      buffer.clear();
      expect(buffer.isEmpty, isTrue);
      // Snapshot still holds pre-clear content.
      expect(snap, hasLength(1));
    });

    test('lines carry ISO timestamp prefix', () {
      final buffer = LogBuffer();
      buffer.append('I/flutter hello', at: DateTime(2026, 8, 21, 3, 4, 5, 678));
      final line = buffer.snapshot().single;
      expect(line, startsWith('2026-08-21T03:04:05.678'));
      expect(line, contains('hello'));
    });
  });

  group('formatLogLine', () {
    test('clock prefix + level + message', () {
      final line = formatLogLine('E/flutter', 'boom', at: DateTime(2026, 8, 21, 9, 8, 7, 6));
      expect(line, '09:08:07.006 E/flutter boom');
    });
  });
}