/// RPC client seam shared by the adapter and its test doubles.
library;

import 'rpc_envelope.dart';

abstract class DshRpcClient {
  /// Posts one JSON-RPC call to `api/<endpoint>` and returns the result.
  ///
  /// [timeout] is the caller's request deadline: when non-null and it
  /// elapses before the exchange settles, the implementation throws a
  /// `DshTransportException` naming the deadline. `null` (the default) means
  /// no deadline — a deliberately unbounded call.
  ///
  /// This package passes the value through without interpreting it; which
  /// calls need a deadline, and how long it is, is the caller's policy.
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  });

  /// Posts one client response to `api/respond` for an interactive frame.
  Future<void> respond(String rpcId, RpcResult result);
}
