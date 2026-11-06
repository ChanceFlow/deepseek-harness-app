/// Which configured backends hold a live WebView, and which are released to
/// reload on their next visit.
///
/// A WebView is the expensive resource in the shell: each configured dsh
/// host keeps one so switching is instant, but several warm hosts cost more
/// memory than a phone tolerates. This pool is the policy that decides the
/// live set — the most recently used hosts win, the active host is protected
/// by default, and everything beyond [HostPoolPolicy.maxLive] is released. A
/// released host is not broken: it has no WebView, so its next
/// [HostPool.touch] rebuilds it from the configured URL.
///
/// The pool is deliberately platform-free: no `webview_flutter`, no platform
/// channels, no widget imports (only `foundation` for `@immutable`). It is a
/// state machine a unit test can drive, and the shell reconciles real WebView
/// controllers against [HostPool.liveIds] and [HostPool.activeId] afterwards.
/// Keeping the decision out of the controller is what makes eviction order
/// and the active-host invariant testable at all.
library;

import 'package:flutter/foundation.dart';

/// A fresh host has never had its URL edited.
const int _initialRevision = 0;

/// A host that has never been touched. Touches stamp strictly increasing
/// values, so the LRU order is total and deterministic.
const int _neverUsed = 0;

/// How many WebViews the shell keeps alive, and whether the active one is
/// exempt from release.
///
/// The default live budget is three: the host on screen plus two warm
/// neighbors, so an A/B switch is instant and a third host pays a reload
/// instead of a fourth WebView staying resident. The budget is a count of
/// live hosts, active included — protection never lets the pool exceed it.
final class HostPoolPolicy {
  /// Creates a policy. [maxLive] must keep at least one host live, because a
  /// pool that may hold none would release the host the user is looking at.
  const HostPoolPolicy({
    this.maxLive = defaultMaxLive,
    this.protectActive = defaultProtectActive,
  }) : assert(maxLive >= 1, 'maxLive must be at least 1');

  /// The default live-WebView budget: the active host plus two warm hosts.
  static const int defaultMaxLive = 3;

  /// By default the host on screen is exempt from eviction and release.
  static const bool defaultProtectActive = true;

  /// The most hosts that may hold a live WebView at once.
  final int maxLive;

  /// Whether the active host is exempt from eviction and from
  /// [HostPool.release].
  ///
  /// The active host is the one the user is looking at, so dropping its
  /// WebView would show an empty pane; protection keeps it live. A shell that
  /// deliberately reclaims every WebView — for example while backgrounded —
  /// clears this so [HostPool.release] may take the active host too.
  final bool protectActive;
}

/// Whether a host's WebView is retained or must be rebuilt from its URL.
enum HostPoolState {
  /// A WebView exists and switching to this host shows it immediately.
  live,

  /// No WebView exists; the host reloads when [HostPool.touch] returns to it.
  released,
}

/// One configured host's state in the pool.
///
/// Immutable snapshots: [HostPool] replaces the entry on every mutation, so a
/// caller holding one (for example to stamp the revision a WebView loaded)
/// never observes a half-applied change.
@immutable
final class HostPoolEntry {
  const HostPoolEntry({
    required this.id,
    this.revision = _initialRevision,
    this.state = HostPoolState.released,
    this.lastUsed = _neverUsed,
  });

  /// Stable backend id. [HostPool.hostIds] keeps configuration order.
  final String id;

  /// Increments on every [HostPool.bumpRevision]. A WebView that loaded an
  /// older revision must reload, so the revision is the shell's reload fence.
  final int revision;

  /// Whether a WebView currently exists for this host.
  final HostPoolState state;

  /// Monotonic use stamp; larger is more recent. The LRU victim is the live
  /// entry with the smallest stamp.
  final int lastUsed;

  /// Whether [state] is [HostPoolState.live].
  bool get isLive => switch (state) {
    HostPoolState.live => true,
    HostPoolState.released => false,
  };

  /// A copy with the given fields replaced; [id] never changes.
  HostPoolEntry copyWith({
    int? revision,
    HostPoolState? state,
    int? lastUsed,
  }) => HostPoolEntry(
    id: id,
    revision: revision ?? this.revision,
    state: state ?? this.state,
    lastUsed: lastUsed ?? this.lastUsed,
  );

  @override
  bool operator ==(Object other) =>
      other is HostPoolEntry &&
      other.id == id &&
      other.revision == revision &&
      other.state == state &&
      other.lastUsed == lastUsed;

  @override
  int get hashCode => Object.hash(id, revision, state, lastUsed);
}

/// The live-WebView policy over an ordered list of configured host ids.
///
/// Every mutation re-applies [HostPoolPolicy.maxLive], so the invariant holds
/// after each call rather than only at the next maintenance sweep. `touch`
/// switches hosts, `setHosts` follows configuration changes, `release` drops a
/// single WebView, and `bumpRevision` marks a URL edit that requires a reload.
final class HostPool {
  /// Starts every host [HostPoolState.released] and no host active: the shell
  /// builds a WebView on the first [touch], not at configuration time.
  ///
  /// Duplicate ids in [hostIds] are rejected because one id keys exactly one
  /// WebView; the call fails before mutating anything.
  HostPool({
    this.policy = const HostPoolPolicy(),
    List<String> hostIds = const <String>[],
  }) {
    setHosts(hostIds);
  }

  /// The budget this pool enforces on every mutation.
  final HostPoolPolicy policy;

  /// Insertion-ordered so [hostIds] and [liveIds] are deterministic.
  final Map<String, HostPoolEntry> _entries = <String, HostPoolEntry>{};
  String? _activeId;
  int _clock = _neverUsed;

  /// The host whose WebView is on screen, or null before the first [touch].
  ///
  /// Active and live are independent facts: under
  /// [HostPoolPolicy.protectActive] the active host is always live, but with
  /// protection off [release] may leave it active and released.
  String? get activeId => _activeId;

  /// Every configured host id, in configuration order.
  List<String> get hostIds => List<String>.unmodifiable(_entries.keys);

  /// Live host ids in configuration order. The shell keeps exactly these
  /// WebViews and disposes every other.
  List<String> get liveIds => List<String>.unmodifiable([
    for (final entry in _entries.values)
      if (entry.isLive) entry.id,
  ]);

  /// The current entry for [id], or null when [id] is not configured.
  HostPoolEntry? entryOf(String id) => _entries[id];

  /// The state of [id]. An unknown or removed host is
  /// [HostPoolState.released]: it has no WebView to keep.
  HostPoolState stateOf(String id) =>
      entryOf(id)?.state ?? HostPoolState.released;

  /// The URL revision of [id]; the fresh-host revision for an unknown id.
  int revisionOf(String id) => entryOf(id)?.revision ?? _initialRevision;

  /// Makes [id] the active host, marks it live and stamps it as most recently
  /// used, then evicts the least-recently-used hosts beyond the live budget.
  ///
  /// An unknown [id] is appended to [hostIds] — a host discovered outside the
  /// configured list still gets its WebView — so the order stays deterministic.
  void touch(String id) {
    final existing = _entries[id];
    _entries[id] = (existing ?? HostPoolEntry(id: id)).copyWith(
      state: HostPoolState.live,
      lastUsed: _nextUse(),
    );
    _activeId = id;
    evict();
  }

  /// Replaces the configured host list, keeping [ids]'s order.
  ///
  /// Retained hosts keep their state, revision and use stamp; a removed host
  /// is released (its WebView is dropped) and loses its revision. Removing the
  /// active host clears [activeId]: protection cannot keep a WebView for a
  /// host the configuration no longer contains.
  void setHosts(List<String> ids) {
    _requireUnique(ids);
    final next = <String, HostPoolEntry>{};
    for (final id in ids) {
      next[id] = _entries[id] ?? HostPoolEntry(id: id);
    }
    _entries
      ..clear()
      ..addAll(next);
    if (_activeId != null && !_entries.containsKey(_activeId)) {
      _activeId = null;
    }
    evict();
  }

  /// Releases [id]'s WebView without evicting anything else.
  ///
  /// No-op for an unknown or already released host, and for the active host
  /// while [HostPoolPolicy.protectActive] is on. With protection off the
  /// active host may be released and stays [activeId] — the pool reports it
  /// released and the shell rebuilds it on the next [touch].
  void release(String id) {
    final entry = _entries[id];
    if (entry == null || !entry.isLive || _isProtected(id)) return;
    _releaseEntry(id);
  }

  /// Bumps [id]'s URL revision so a WebView that loaded an older revision
  /// reloads.
  ///
  /// State, active host and use stamp are untouched: the active host reloads
  /// in place to the edited URL instead of disappearing. An unknown [id] is
  /// ignored so a late URL edit cannot resurrect a host that was just removed.
  void bumpRevision(String id) {
    final entry = _entries[id];
    if (entry == null) return;
    _entries[id] = entry.copyWith(revision: entry.revision + 1);
  }

  /// Releases the least-recently-used live hosts until at most
  /// [HostPoolPolicy.maxLive] remain.
  ///
  /// Every mutator already calls this, so the budget holds after each call;
  /// the method is public for a shell-level memory trim or a policy change
  /// that needs the same sweep without another mutation. Under
  /// [HostPoolPolicy.protectActive] the active host is never a candidate.
  void evict() {
    while (_liveCount > policy.maxLive) {
      final victim = _leastRecentlyUsed();
      if (victim == null) return;
      _releaseEntry(victim.id);
    }
  }

  int get _liveCount {
    var count = 0;
    for (final entry in _entries.values) {
      if (entry.isLive) count++;
    }
    return count;
  }

  HostPoolEntry? _leastRecentlyUsed() {
    HostPoolEntry? victim;
    for (final entry in _entries.values) {
      if (!entry.isLive || _isProtected(entry.id)) continue;
      if (victim == null || entry.lastUsed < victim.lastUsed) {
        victim = entry;
      }
    }
    return victim;
  }

  bool _isProtected(String id) => policy.protectActive && id == _activeId;

  void _releaseEntry(String id) {
    final entry = _entries[id];
    if (entry == null) return;
    _entries[id] = entry.copyWith(state: HostPoolState.released);
  }

  int _nextUse() => ++_clock;

  static void _requireUnique(List<String> ids) {
    final seen = <String>{};
    for (final id in ids) {
      if (!seen.add(id)) {
        throw ArgumentError.value(ids, 'hostIds', 'duplicate host id "$id"');
      }
    }
  }
}
