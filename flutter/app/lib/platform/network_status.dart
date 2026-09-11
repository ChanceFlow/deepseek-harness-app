/// Platform bridge for Android default-network availability changes.
///
/// Android reports the device's default network through
/// `ConnectivityManager.registerDefaultNetworkCallback` in
/// `NetworkStatusBridge.kt`, which publishes to the `dsh/network_status`
/// event channel. This seam turns those reports into "the network is back"
/// hints: a listener moves its reconnect the moment the hint arrives instead
/// of waiting out the exponential backoff the network loss started.
///
/// The seam owns its subscription. `available` is broadcast — one platform
/// registration serves every listener, it is requested on the first listener
/// and cancelled when the last one cancels. Where no host implements the
/// channel (widget tests, desktop), `listen` is unanswered and the stream
/// stays inert and error-free.
///
/// [EventChannel.receiveBroadcastStream] is not used here: a missing host
/// makes it route `MissingPluginException` through `FlutterError.reportError`,
/// which a widget test that only builds the dependency graph never drains.
/// [OptionalMethodChannel] answers null for the same state instead, and the
/// controller below receives the host's events through the standard envelope.
library;

import 'dart:async';

import 'package:flutter/services.dart';

/// Event channel name; must match `NetworkStatusBridge.kt`.
const String kNetworkStatusChannel = 'dsh/network_status';

const MethodCodec _codec = StandardMethodCodec();

/// The control leg of the host event channel. [OptionalMethodChannel] answers
/// null instead of throwing where no host implements it.
const OptionalMethodChannel _control = OptionalMethodChannel(
  kNetworkStatusChannel,
);

/// Broadcast "the device's default network is available" hints.
final class NetworkStatus {
  NetworkStatus() {
    _available = StreamController<void>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
  }

  late final StreamController<void> _available;

  bool _listening = false;
  bool _disposed = false;

  /// One event per default-network availability report. The first listener
  /// registers the host callback; the last cancellation unregisters it.
  Stream<void> get available => _available.stream;

  /// Stops listening and releases the host callback; the future completes
  /// when the broadcast stream is done. Safe to call twice.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stop();
    await _available.close();
  }

  void _start() {
    if (_disposed || _listening) return;
    _listening = true;
    ServicesBinding.instance.defaultBinaryMessenger.setMessageHandler(
      kNetworkStatusChannel,
      _onPlatformEvent,
    );
    unawaited(_send('listen'));
  }

  void _stop() {
    if (!_listening) return;
    _listening = false;
    ServicesBinding.instance.defaultBinaryMessenger.setMessageHandler(
      kNetworkStatusChannel,
      null,
    );
    // Never awaited: a channel whose host does not answer must not hang the
    // cancelling subscription, which is what a widget test or a desktop host
    // with no channel would otherwise do.
    unawaited(_send('cancel'));
  }

  Future<void> _send(String method) async {
    try {
      await _control.invokeMethod<void>(method);
    } on PlatformException {
      // The host refused the request. The hint is optional: losing it costs a
      // reconnect on the next generation loss, never a crash.
    }
  }

  /// Decodes one host event envelope. A `null` reply and an error envelope
  /// both leave the stream untouched — a host that cannot report network
  /// state is the widget-test/desktop case, not a failure to surface.
  Future<ByteData?> _onPlatformEvent(ByteData? reply) async {
    if (reply == null || _disposed || _available.isClosed) return null;
    try {
      _codec.decodeEnvelope(reply);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
    _available.add(null);
    return null;
  }
}
