/// HostPool behavior: the live-WebView policy the shell reconciles against.
///
/// Every test drives the real pool through its public mutations and asserts
/// the observable decisions — active id, live set, per-host state and
/// revision. No controller, no WebView: the point of the module is that the
/// eviction order and the active-host invariant are plain state changes.
library;

import 'package:app/shell/host_pool.dart';
import 'package:flutter_test/flutter_test.dart';

HostPool _pool(
  List<String> hosts, {
  HostPoolPolicy policy = const HostPoolPolicy(),
}) => HostPool(policy: policy, hostIds: hosts);

HostPoolPolicy _maxLive(int value, {bool protectActive = true}) =>
    HostPoolPolicy(maxLive: value, protectActive: protectActive);

void main() {
  group('HostPoolPolicy', () {
    test('defaults to three live hosts with the active one protected', () {
      const policy = HostPoolPolicy();
      expect(policy.maxLive, 3);
      expect(policy.protectActive, isTrue);
    });

    test('rejects a budget that could hold no host', () {
      expect(() => HostPoolPolicy(maxLive: 0), throwsAssertionError);
    });
  });

  group('HostPool', () {
    test('configures every host released, with no active host', () {
      final pool = _pool(['a', 'b', 'c']);

      expect(pool.hostIds, ['a', 'b', 'c']);
      expect(pool.liveIds, isEmpty);
      expect(pool.activeId, isNull);
      for (final id in ['a', 'b', 'c']) {
        expect(pool.stateOf(id), HostPoolState.released);
        expect(pool.revisionOf(id), 0);
        expect(pool.entryOf(id)?.lastUsed, 0);
      }

      // Removed/unknown hosts answer as released: there is no WebView.
      expect(pool.stateOf('missing'), HostPoolState.released);
      expect(pool.revisionOf('missing'), 0);
    });

    test('touch makes a host active, live and most recently used', () {
      final pool = _pool(['a', 'b']);

      pool.touch('a');
      expect(pool.activeId, 'a');
      expect(pool.stateOf('a'), HostPoolState.live);
      expect(pool.liveIds, ['a']);
      final firstUse = pool.entryOf('a')!.lastUsed;

      // A repeat touch is state-idempotent but bumps recency, so the host
      // stays the freshest LRU candidate.
      pool.touch('a');
      expect(pool.activeId, 'a');
      expect(pool.stateOf('a'), HostPoolState.live);
      expect(pool.liveIds, ['a']);
      expect(pool.entryOf('a')!.lastUsed, greaterThan(firstUse));
    });

    test('appends an unknown touched host at the end', () {
      final pool = _pool(['a', 'b']);

      pool.touch('c');
      expect(pool.hostIds, ['a', 'b', 'c']);
      expect(pool.activeId, 'c');
      expect(pool.stateOf('c'), HostPoolState.live);
    });

    test('adding past maxLive releases the LRU, never the active host', () {
      final pool = _pool(['a', 'b', 'c'], policy: _maxLive(2));

      pool.touch('a');
      pool.touch('b');
      expect(pool.liveIds, ['a', 'b']);

      pool.touch('c');
      expect(pool.liveIds, ['b', 'c']);
      expect(pool.activeId, 'c');
      expect(pool.stateOf('a'), HostPoolState.released);
      expect(pool.stateOf('c'), HostPoolState.live);
    });

    test('switching touches LRU order so the stale host is released', () {
      final pool = _pool(['a', 'b', 'c'], policy: _maxLive(2));

      pool.touch('a');
      pool.touch('b');
      // Re-touch a: b is now the least recently used live host.
      pool.touch('a');
      expect(pool.liveIds, ['a', 'b']);

      pool.touch('c');
      expect(pool.liveIds, ['a', 'c']);
      expect(pool.activeId, 'c');
      expect(pool.stateOf('b'), HostPoolState.released);
    });

    test('touch is idempotent in the live set and active host', () {
      final pool = _pool(['a', 'b'], policy: _maxLive(1));
      pool.touch('b');

      pool.touch('b');
      expect(pool.liveIds, ['b']);
      expect(pool.activeId, 'b');
      expect(pool.stateOf('b'), HostPoolState.live);
    });

    test('maxLive of one keeps exactly the active host', () {
      final pool = _pool(['a', 'b'], policy: _maxLive(1));

      pool.touch('a');
      expect(pool.liveIds, ['a']);

      pool.touch('b');
      expect(pool.liveIds, ['b']);
      expect(pool.stateOf('a'), HostPoolState.released);

      pool.touch('a');
      expect(pool.liveIds, ['a']);
      expect(pool.stateOf('b'), HostPoolState.released);
    });

    test('a single host is never evicted by repeated touches', () {
      final pool = _pool(['only'], policy: _maxLive(1));

      for (var i = 0; i < 5; i++) {
        pool.touch('only');
      }
      expect(pool.liveIds, ['only']);
      expect(pool.activeId, 'only');
      expect(pool.stateOf('only'), HostPoolState.live);
    });

    test('setHosts keeps the given order and releases removed hosts', () {
      final pool = _pool(['a', 'b', 'c']);
      pool.touch('a');
      pool.touch('b');
      pool.touch('c');

      pool.setHosts(['c', 'a']);
      expect(pool.hostIds, ['c', 'a']);
      expect(pool.liveIds, ['c', 'a']);
      expect(pool.activeId, 'c');
      // b left the configuration, so its WebView is gone.
      expect(pool.stateOf('b'), HostPoolState.released);
    });

    test('setHosts adds new hosts released and clears a removed active', () {
      final pool = _pool(['a', 'b']);
      pool.touch('b');

      pool.setHosts(['a', 'b', 'c']);
      expect(pool.hostIds, ['a', 'b', 'c']);
      expect(pool.liveIds, ['b']);
      expect(pool.activeId, 'b');
      expect(pool.stateOf('c'), HostPoolState.released);

      pool.setHosts(['a', 'c']);
      expect(pool.hostIds, ['a', 'c']);
      expect(pool.activeId, isNull);
      expect(pool.stateOf('b'), HostPoolState.released);
    });

    test(
      'setHosts preserves a retained host state, revision and use stamp',
      () {
        final pool = _pool(['a', 'b']);
        pool.touch('a');
        pool.bumpRevision('a');
        final before = pool.entryOf('a')!;

        pool.setHosts(['a', 'b']);
        expect(pool.entryOf('a'), before);
        expect(pool.liveIds, ['a']);
      },
    );

    test('setHosts rejects duplicates before mutating', () {
      final pool = _pool(['a', 'b']);

      expect(() => pool.setHosts(['b', 'a', 'b']), throwsArgumentError);
      expect(pool.hostIds, ['a', 'b']);
      expect(() => _pool(['a', 'a']), throwsArgumentError);
    });

    test('bumpRevision marks reload-needed without releasing the WebView', () {
      final pool = _pool(['a', 'b']);
      pool.touch('a');
      final loadedRevision = pool.revisionOf('a');
      final lastUsed = pool.entryOf('a')!.lastUsed;

      pool.bumpRevision('a');
      expect(pool.revisionOf('a'), loadedRevision + 1);
      expect(pool.stateOf('a'), HostPoolState.live);
      expect(pool.activeId, 'a');
      expect(pool.entryOf('a')!.lastUsed, lastUsed);
      // A different host's revision is untouched.
      expect(pool.revisionOf('b'), 0);
    });

    test('revision survives a release and the next touch', () {
      final pool = _pool(['a', 'b'], policy: _maxLive(1));
      pool.touch('a');
      pool.bumpRevision('a');

      pool.touch('b');
      expect(pool.stateOf('a'), HostPoolState.released);
      expect(pool.revisionOf('a'), 1);

      pool.touch('a');
      expect(pool.stateOf('a'), HostPoolState.live);
      expect(pool.revisionOf('a'), 1);
    });

    test('bumpRevision ignores an unknown id', () {
      final pool = _pool(['a']);

      pool.bumpRevision('missing');
      expect(pool.hostIds, ['a']);
      expect(pool.revisionOf('missing'), 0);
    });

    test('release drops an idle host and is idempotent', () {
      final pool = _pool(['a', 'b'], policy: _maxLive(2));
      pool.touch('a');
      pool.touch('b');

      pool.release('a');
      expect(pool.stateOf('a'), HostPoolState.released);
      pool.release('a');
      expect(pool.stateOf('a'), HostPoolState.released);
      pool.release('missing');
      expect(pool.liveIds, ['b']);
    });

    test('protection keeps the active host live through release and evict', () {
      final pool = _pool(['a', 'b'], policy: _maxLive(1));
      pool.touch('a');

      pool.release('a');
      expect(pool.stateOf('a'), HostPoolState.live);

      pool.evict();
      expect(pool.stateOf('a'), HostPoolState.live);
      expect(pool.activeId, 'a');
    });

    test('protectActive off lets the active host be released', () {
      final pool = _pool(['a'], policy: _maxLive(1, protectActive: false));
      pool.touch('a');

      pool.release('a');
      expect(pool.stateOf('a'), HostPoolState.released);
      expect(pool.activeId, 'a');

      pool.touch('a');
      expect(pool.stateOf('a'), HostPoolState.live);
    });

    test('the live budget holds after every mutation', () {
      final pool = _pool(['a', 'b', 'c', 'd'], policy: _maxLive(2));
      pool.touch('a');
      pool.touch('b');
      pool.touch('c');
      pool.touch('d');
      expect(pool.liveIds.length, lessThanOrEqualTo(2));

      pool.setHosts(['d', 'a', 'b', 'c']);
      expect(pool.liveIds.length, lessThanOrEqualTo(2));
      expect(pool.liveIds, ['d', 'c']);
    });
  });
}
