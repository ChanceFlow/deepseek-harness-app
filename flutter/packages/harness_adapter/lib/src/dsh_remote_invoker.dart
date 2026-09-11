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
    DshRpcEndpoints.sessionCreate,
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
    DshRpcEndpoints.sessionPage,
    DshRpcEndpoints.subagentsPrompt,
  };

  static JsonMap _prepareArgs(String endpoint, JsonMap payload) {
    if (endpoint == DshRpcEndpoints.sessionModelCatalog ||
        endpoint == DshRpcEndpoints.agentPresetsList ||
        endpoint == DshRpcEndpoints.settingsDescribe) {
      return const <String, Object?>{};
    }
    if (endpoint == DshRpcEndpoints.sessionList) {
      if (payload.containsKey('_request')) return payload;
      return <String, Object?>{'_request': payload};
    }
    if (endpoint == DshRpcEndpoints.agentPresetsSelect) {
      return <String, Object?>{
        'agentId': payload['agentId'] ?? payload['sessionId'],
        'agentPreset': payload['agentPreset'],
      };
    }
    if (endpoint == DshRpcEndpoints.workspaceFilesRead) {
      return <String, Object?>{
        'sessionId': payload['sessionId'],
        'path': payload['path'],
        'range': payload['range'] ?? const <String, Object?>{},
      };
    }
    if (endpoint == DshRpcEndpoints.workspaceFilesReadBytes) {
      return <String, Object?>{
        'sessionId': payload['sessionId'],
        'path': payload['path'],
        'range': payload['range'] ?? const <String, Object?>{},
      };
    }
    if (endpoint == DshRpcEndpoints.workspaceFilesReadAll ||
        endpoint == DshRpcEndpoints.workspaceFilesStat ||
        endpoint == DshRpcEndpoints.workspaceFilesList) {
      return <String, Object?>{
        'sessionId': payload['sessionId'],
        'path': payload['path'],
      };
    }
    if (endpoint == DshRpcEndpoints.goalsCreate) {
      final req = asJsonObject(payload['request']) ?? payload;
      return <String, Object?>{
        'agentId': payload['agentId'] ?? payload['sessionId'],
        'request': <String, Object?>{
          'objective': req['objective'],
          if (req['maxGoalRounds'] != null)
            'maxGoalRounds': req['maxGoalRounds'],
        },
      };
    }
    if (endpoint == DshRpcEndpoints.goalsEdit) {
      final req = asJsonObject(payload['request']) ?? payload;
      return <String, Object?>{
        'agentId': payload['agentId'] ?? payload['sessionId'],
        'ref': payload['ref'],
        'request': <String, Object?>{
          if (req['objective'] != null) 'objective': req['objective'],
          if (req['maxGoalRounds'] != null)
            'maxGoalRounds': req['maxGoalRounds'],
        },
      };
    }
    if (endpoint == DshRpcEndpoints.goalsPause ||
        endpoint == DshRpcEndpoints.goalsResume ||
        endpoint == DshRpcEndpoints.goalsComplete ||
        endpoint == DshRpcEndpoints.goalsClear) {
      return <String, Object?>{
        'agentId': payload['agentId'] ?? payload['sessionId'],
        'ref': payload['ref'],
      };
    }
    if (endpoint == DshRpcEndpoints.sessionPage) {
      if (payload.containsKey('request')) return payload;
      if (payload.containsKey('address')) {
        return <String, Object?>{'request': payload};
      }
      return <String, Object?>{
        'request': <String, Object?>{
          'address': <String, Object?>{
            'kind': 'session',
            'sessionId': payload['sessionId'],
          },
          'throughSeq': payload['throughSeq'] ?? payload['beforeSeq'] ?? 0,
          if (payload['beforeSeq'] != null) 'beforeSeq': payload['beforeSeq'],
          if (payload['maxMessages'] != null)
            'maxMessages': payload['maxMessages'],
        },
      };
    }
    if (_requestWrappedEndpoints.contains(endpoint)) {
      if (payload.containsKey('request')) return payload;
      return <String, Object?>{'request': payload};
    }
    return payload;
  }

  /// Executes one Remote unary call against [endpoint] in DSH 0.1.2.
  ///
  /// [timeout] is the caller's request deadline and is forwarded verbatim to
  /// the transport; `null` means the call is deliberately unbounded. It is a
  /// required argument so every call site states which it is — see
  /// `_callUnbounded` in `harness_repository_impl.dart` for the long-running
  /// exemption list.
  Future<RpcResult> call(
    String endpoint,
    JsonMap payload, {
    required Duration? timeout,
  }) async {
    final rawArgs = payload.containsKey('args') && payload.length == 1
        ? (asJsonObject(payload['args']) ?? payload)
        : payload;
    final primaryArgs = _prepareArgs(endpoint, rawArgs);
    final primaryWrapped = <String, Object?>{'args': primaryArgs};

    var result = await _rpcClient.call(
      endpoint,
      endpoint,
      primaryWrapped,
      timeout: timeout,
    );
    if (!result.ok && endpoint == DshRpcEndpoints.sessionPage) {
      final msg = result.error?.message ?? '';
      final match = RegExp(r'past cursor (-?\d+)').firstMatch(msg);
      if (match != null) {
        final cursor = int.tryParse(match.group(1)!);
        if (cursor != null) {
          final req = asJsonObject(primaryArgs['request']) ?? primaryArgs;
          final retryReq = Map<String, Object?>.from(req);
          retryReq['throughSeq'] = cursor;
          final retryPayload = <String, Object?>{
            'args': <String, Object?>{'request': retryReq},
          };
          result = await _rpcClient.call(
            endpoint,
            endpoint,
            retryPayload,
            timeout: timeout,
          );
        }
      }
    }
    return result;
  }

  /// Calls [endpoint] and returns its non-null [RpcResult.value], throwing a
  /// [DshBusinessException] on error outcomes or missing response value.
  Future<JsonMap> invoke(
    String endpoint,
    JsonMap payload, {
    required Duration? timeout,
  }) async {
    final result = await call(endpoint, payload, timeout: timeout);
    if (!result.ok) {
      final failure = result.error;
      throw DshBusinessException(
        code: failure?.code ?? 'internal',
        message: failure?.message ?? '$endpoint failed',
        details: failure?.details,
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

  /// Calls [endpoint] for void mutations, ensuring success.
  Future<void> execute(
    String endpoint,
    JsonMap payload, {
    required Duration? timeout,
  }) async {
    final result = await call(endpoint, payload, timeout: timeout);
    if (!result.ok) {
      final failure = result.error;
      throw DshBusinessException(
        code: failure?.code ?? 'internal',
        message: failure?.message ?? '$endpoint failed',
        details: failure?.details,
      );
    }
  }
}
