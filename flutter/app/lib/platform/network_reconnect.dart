/// Bridges the platform's network-availability hints to the live connection
/// generations.
///
/// A network loss starts the connection manager's exponential backoff, but
/// the device coming back online (screen unlock, Wi-Fi/cellular switch, Doze
/// exit) invalidates whatever that backoff assumed about reachability. This
/// binder turns each hint into one immediate reconnect request across every
/// enabled backend, so recovery does not wait out a delay that was chosen for
/// a network that no longer exists.
///
/// Deliberately decoupled from the manager type: it takes a plain stream and
/// a callback, so the policy is unit-testable without a real socket and the
/// DI layer owns which managers the callback reaches.
library;

import 'dart:async';

/// Connects one availability stream to one reconnect action.
class NetworkReconnectBinder {
  NetworkReconnectBinder({
    required this._available,
    required this._reconnectAll,
  });

  final Stream<void> _available;
  final void Function() _reconnectAll;

  StreamSubscription<void>? _subscription;

  /// Whether the hint stream is currently subscribed.
  bool get isListening => _subscription != null;

  /// Starts listening; idempotent. A hint that arrives before [start] is
  /// dropped — the connect loop is still dialing its first generation then,
  /// and a reconnect request would be redundant.
  void start() {
    _subscription ??= _available.listen((_) => _reconnectAll());
  }

  /// Stops listening and releases the host callback through the stream's
  /// cancel path. Safe to call twice.
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }
}
