/// RPC client seam shared by the adapter and its test doubles.
library;

import 'rpc_envelope.dart';

abstract class DshRpcClient {
  /// Posts one JSON-RPC call to `api/<endpoint>` and returns the result.
  Future<RpcResult> call(String endpoint, String method, JsonMap payload);

  /// Posts one client response to `api/respond` for an interactive frame.
  Future<void> respond(String rpcId, RpcResult result);
}
