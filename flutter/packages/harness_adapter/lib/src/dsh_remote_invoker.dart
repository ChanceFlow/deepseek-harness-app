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
    DshRpcEndpoints.subagentsPrompt,
  };

  static JsonMap _prepareArgs(String endpoint, JsonMap payload) {
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

  static JsonMap _unwrapArgsForFallback(String endpoint, JsonMap payload) {
    if (endpoint.startsWith('goals/') || endpoint.startsWith('goal.')) {
      final req = asJsonObject(payload['request']) ?? payload;
      return <String, Object?>{
        'sessionId': payload['agentId'] ?? payload['sessionId'],
        if (payload['ref'] != null) 'ref': payload['ref'],
        if (req['objective'] != null) 'objective': req['objective'],
        if (req['maxGoalRounds'] != null) 'maxGoalRounds': req['maxGoalRounds'],
      };
    }
    if (endpoint == DshRpcEndpoints.agentPresetsSelect ||
        endpoint == 'agentPreset.select') {
      return <String, Object?>{
        'sessionId': payload['agentId'] ?? payload['sessionId'],
        'agentPreset': payload['agentPreset'],
      };
    }
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
          final fallbackArgs = _unwrapArgsForFallback(endpoint, rawArgs);
          for (final fallback in fallbacks) {
            try {
              if (fallback == DshRpcEndpoints.sessionPage) {
                if (endpoint == DshRpcEndpoints.sessionHistory) {
                  final initialThrough =
                      fallbackArgs['throughSeq'] ??
                      fallbackArgs['beforeSeq'] ??
                      999999999;
                  final payload = <String, Object?>{
                    'args': <String, Object?>{
                      'request': <String, Object?>{
                        'address': <String, Object?>{
                          'kind': 'session',
                          'sessionId': fallbackArgs['sessionId'],
                        },
                        'throughSeq': initialThrough,
                        if (fallbackArgs['beforeSeq'] != null)
                          'beforeSeq': fallbackArgs['beforeSeq'],
                        if (fallbackArgs['maxMessages'] != null)
                          'maxMessages': fallbackArgs['maxMessages'],
                      },
                    },
                  };
                  var res = await _rpcClient.call(fallback, fallback, payload);
                  if (!res.ok) {
                    final msg = res.error?.message ?? '';
                    final match = RegExp(r'past cursor (\d+)').firstMatch(msg);
                    if (match != null) {
                      final cursor = int.tryParse(match.group(1)!);
                      if (cursor != null) {
                        final retryPayload = <String, Object?>{
                          'args': <String, Object?>{
                            'request': <String, Object?>{
                              'address': <String, Object?>{
                                'kind': 'session',
                                'sessionId': fallbackArgs['sessionId'],
                              },
                              'throughSeq': cursor,
                              if (fallbackArgs['beforeSeq'] != null)
                                'beforeSeq': fallbackArgs['beforeSeq'],
                              if (fallbackArgs['maxMessages'] != null)
                                'maxMessages': fallbackArgs['maxMessages'],
                            },
                          },
                        };
                        res = await _rpcClient.call(
                          fallback,
                          fallback,
                          retryPayload,
                        );
                      }
                    }
                  }
                  return res;
                } else if (endpoint == DshRpcEndpoints.subagentsHistory) {
                  final initialThrough =
                      fallbackArgs['throughSeq'] ?? 999999999;
                  final payload = <String, Object?>{
                    'args': <String, Object?>{
                      'request': <String, Object?>{
                        'address': <String, Object?>{
                          'kind': 'subagent',
                          'parentSessionId': fallbackArgs['parentSessionId'],
                          'childSessionId': fallbackArgs['childSessionId'],
                          'mode': fallbackArgs['mode'] ?? 'continuable',
                        },
                        'throughSeq': initialThrough,
                        'maxMessages': 50,
                      },
                    },
                  };
                  var res = await _rpcClient.call(fallback, fallback, payload);
                  if (!res.ok) {
                    final msg = res.error?.message ?? '';
                    final match = RegExp(r'past cursor (\d+)').firstMatch(msg);
                    if (match != null) {
                      final cursor = int.tryParse(match.group(1)!);
                      if (cursor != null) {
                        final retryPayload = <String, Object?>{
                          'args': <String, Object?>{
                            'request': <String, Object?>{
                              'address': <String, Object?>{
                                'kind': 'subagent',
                                'parentSessionId':
                                    fallbackArgs['parentSessionId'],
                                'childSessionId':
                                    fallbackArgs['childSessionId'],
                                'mode': fallbackArgs['mode'] ?? 'continuable',
                              },
                              'throughSeq': cursor,
                              'maxMessages': 50,
                            },
                          },
                        };
                        res = await _rpcClient.call(
                          fallback,
                          fallback,
                          retryPayload,
                        );
                      }
                    }
                  }
                  return res;
                } else {
                  return await _rpcClient.call(
                    fallback,
                    fallback,
                    <String, Object?>{'args': fallbackArgs},
                  );
                }
              } else {
                return await _rpcClient.call(
                  fallback,
                  fallback,
                  <String, Object?>{'args': fallbackArgs},
                );
              }
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
      if (!result.ok) {
        final failure = result.error;
        throw DshBusinessException(
          code: failure?.code ?? 'internal',
          message: failure?.message ?? '$endpoint failed',
        );
      }
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
