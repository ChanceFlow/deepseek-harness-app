/// Remote RPC invoker with transparent version fallback and payload wrapping.
library;

import 'package:network/dsh_exceptions.dart';
import 'package:network/dsh_rpc_client.dart';
import 'package:network/rpc_envelope.dart';

import 'rpc_map.dart';

/// Invokes Typert Remote endpoints through [DshRpcClient] with automatic
/// `{ args: ... }` envelope packaging and transparent 0.1.2 -> 0.1.1 fallback.
final class DshRemoteInvoker {
  const DshRemoteInvoker(this._rpcClient);

  final DshRpcClient _rpcClient;

  /// Executes one Remote unary call against [endpoint], attempting legacy
  /// fallback aliases if the primary endpoint returns HTTP 404.
  Future<RpcResult> call(String endpoint, JsonMap payload) async {
    final wrapped = payload.containsKey('args') && payload.length == 1
        ? payload
        : <String, Object?>{'args': payload};

    try {
      return await _rpcClient.call(endpoint, endpoint, wrapped);
    } on DshTransportException catch (e) {
      if (e.message.contains('404')) {
        final fallbacks = kDshEndpointFallbacks[endpoint];
        if (fallbacks != null) {
          for (final fallback in fallbacks) {
            try {
              return await _rpcClient.call(fallback, fallback, wrapped);
            } on DshTransportException catch (fe) {
              if (fe.message.contains('404')) continue;
              rethrow;
            }
          }
        }
      }
      rethrow;
    }
  }

  /// Calls [endpoint] and returns its non-null [RpcResult.value], throwing a
  /// [DshBusinessException] on error outcomes or missing response value.
  Future<JsonMap> invoke(String endpoint, JsonMap payload) async {
    final result = await call(endpoint, payload);
    if (!result.ok) {
      final failure = result.error;
      throw DshBusinessException(
        code: failure?.code ?? 'internal',
        message: failure?.message ?? '$endpoint failed',
      );
    }
    final value = result.value;
    if (value == null) {
      throw DshBusinessException(
        code: 'bad-response',
        message: '$endpoint missing value',
      );
    }
    return value;
  }

  /// Calls [endpoint] and returns its value, or returns null if the endpoint
  /// is not mounted (HTTP 404) on the backend.
  Future<JsonMap?> invokeOrNullOnNotFound(
    String endpoint,
    JsonMap payload,
  ) async {
    try {
      final result = await call(endpoint, payload);
      if (!result.ok) return null;
      return result.value;
    } on DshTransportException catch (e) {
      if (e.message.contains('404')) return null;
      rethrow;
    }
  }

  /// Calls [endpoint] for void mutations, ensuring success.
  Future<void> execute(String endpoint, JsonMap payload) async {
    final result = await call(endpoint, payload);
    if (!result.ok) {
      final failure = result.error;
      throw DshBusinessException(
        code: failure?.code ?? 'internal',
        message: failure?.message ?? '$endpoint failed',
      );
    }
  }
}
