/// Downlink-only server event stream seam.
library;

import 'rpc_envelope.dart';

abstract class DshEventSocket {
  /// Opens one downlink-only server stream.
  ///
  /// [onOpen] is invoked once the physical transport is ready, before the
  /// first frame; connection readiness uses this callback as a strict
  /// handshake signal.
  Stream<ServerRequest> connect(String path, {void Function()? onOpen});
}
