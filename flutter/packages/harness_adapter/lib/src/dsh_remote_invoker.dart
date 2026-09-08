/// Remote RPC invoker with transparent version fallback and payload wrapping.
library;

import 'package:network/dsh_exceptions.dart';
import 'package:network/dsh_rpc_client.dart';
import 'package:network/rpc_envelope.dart';

import 'rpc_map.dart';

/// Invokes Typert Remote endpoints through [DshRpcClient] with automatic
/// `{ args: ... }` and `{ request: ... }` envelope packaging and transparent
/// 0.1.2 -> 0.1.1 fallback.
final class DshRemoteInvoker {
  const DshRemoteInvoker(this._rpcClient);

  final DshRpcClient _rpcClient;

  static const Set<String> _requestWrappedEndpoints = <String>{
    DshRpcEndpoints.sessionPrompt,
    DshRpcEndpoints.sessionAttachment,
    DshRpcEndpoints.sessionCancel,
    DshRpcEndpoints.sessionSearch,
    DshRpcEndpoints.sessionRename,
    DshRpcEndpoints.sessionFork,
    DshRpcEndpoints.sessionSelectModel,
    DshRpcEndpoints.sessionUpdateQueue,
    DshRpcEndpoints.skillsList,
    DshRpcEndpoints.workspaceCreate,
    DshRpcEndpoints.workspaceRename,
    DshRpcEndpoints.workspaceDelete,
    DshRpcEndpoints.workspaceInsertBefore,
    DshRpcEndpoints.workspaceInsertSessionBefore,
    DshRpcEndpoints.workspaceArchiveSession,
    DshRpcEndpoints.subagentsPrompt,
  };

  static JsonMap _prepareArgs(String endpoint, JsonMap payload) {
    if (endpoint == DshRpcEndpoints.sessionList) {
      if (payload.containsKey('_request')) return payload;
      return <String, Object?>{'_request': payload};
    }
    if (_requestWrappedEndpoints.contains(endpoint)) {
      if (payload.containsKey('request')) return payload;
      return <String, Object?>{'request': payload};
    }
    return payload;
  }

  static JsonMap _unwrapArgsForFallback(JsonMap payload) {
    if (payload.containsKey('request') && payload.length == 1) {
      final inner = asJsonObject(payload['request']);
      if (inner != null) return inner;
    }
    if (payload.containsKey('_request') && payload.length == 1) {
      final inner = asJsonObject(payload['_request']);
      if (inner != null) return inner;
    }
    return payload;
  }

  /// Executes one Remote unary call against [endpoint], attempting legacy
  /// fallback aliases if the primary endpoint returns HTTP 404.
  Future<RpcResult> call(String endpoint, JsonMap payload) async {
    final rawArgs = payload.containsKey('args') && payload.length == 1
        ? (asJsonObject(payload['args']) ?? payload)
        : payload;
    final primaryArgs = _prepareArgs(endpoint, rawArgs);
    final primaryWrapped = <String, Object?>{'args': primaryArgs};

    try {
      return await _rpcClient.call(endpoint, endpoint, primaryWrapped);
    } on DshTransportException catch (e) {
      if (e.message.contains('404')) {
        final explicitFallbacks = kDshEndpointFallbacks[endpoint];
        final dotFallback = endpoint.contains('/')
            ? endpoint.replaceAll('/', '.')
            : null;
        final fallbacks = <String>[
          ...?explicitFallbacks,
          if (dotFallback != null &&
              !(explicitFallbacks?.contains(dotFallback) ?? false))
            dotFallback,
        ];
        if (fallbacks.isNotEmpty) {
          final fallbackArgs = _unwrapArgsForFallback(rawArgs);
          final fallbackWrapped = <String, Object?>{'args': fallbackArgs};
          for (final fallback in fallbacks) {
            try {
              return await _rpcClient.call(fallback, fallback, fallbackWrapped);
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
