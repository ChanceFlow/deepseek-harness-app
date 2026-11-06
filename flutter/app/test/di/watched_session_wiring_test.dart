/// The watched-session provider seam's wiring: the WebView shell reports no
/// selection fact, so the default answer is null (nothing is ever "watched"
/// and every turn completion surfaces); a test or a future bridge overrides
/// the per-backend family to supply the fact.
library;

import 'package:app/di/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the shell watches nothing: the default is null on every backend', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(watchedSessionIdProvider('b')), isNull);
    expect(container.read(watchedSessionIdProvider('other')), isNull);
  });

  test('the override seam supplies one backend without leaking to another', () {
    final container = ProviderContainer(
      overrides: [
        watchedSessionIdProvider('b').overrideWith((ref) => 'session-a'),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(watchedSessionIdProvider('b')), 'session-a');
    expect(container.read(watchedSessionIdProvider('other')), isNull);
  });
}
