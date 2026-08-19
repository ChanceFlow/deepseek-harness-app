/// JSON-RPC envelope vocabulary shared by the client and server wire.
library;

/// A JSON object value as decoded from the wire.
typedef JsonMap = Map<String, Object?>;

JsonMap _asMap(Object? value, String what) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw FormatException('$what must be a JSON object, got: $value');
}

final class ClientRequest {
  ClientRequest({
    this.type = 'client-request',
    required this.rpcId,
    required this.method,
    required this.payload,
  });

  final String type;
  final String rpcId;
  final String method;
  final JsonMap payload;

  static ClientRequest fromJson(Object? json) {
    final map = _asMap(json, 'ClientRequest');
    return ClientRequest(
      type: map['type'] as String? ?? 'client-request',
      rpcId: map['rpcId'] as String,
      method: map['method'] as String,
      payload: _asMap(map['payload'], 'ClientRequest.payload'),
    );
  }

  JsonMap toJson() => <String, Object?>{
    'type': type,
    'rpcId': rpcId,
    'method': method,
    'payload': payload,
  };
}

final class ClientResponse {
  ClientResponse({
    this.type = 'client-response',
    required this.rpcId,
    required this.result,
  });

  final String type;
  final String rpcId;
  final RpcResult result;

  static ClientResponse fromJson(Object? json) {
    final map = _asMap(json, 'ClientResponse');
    return ClientResponse(
      type: map['type'] as String? ?? 'client-response',
      rpcId: map['rpcId'] as String,
      result: RpcResult.fromJson(map['result']),
    );
  }

  JsonMap toJson() => <String, Object?>{
    'type': type,
    'rpcId': rpcId,
    'result': result.toJson(),
  };
}

final class ServerResponse {
  ServerResponse({
    this.type = 'server-response',
    required this.rpcId,
    required this.result,
  });

  final String type;
  final String rpcId;
  final RpcResult result;

  static ServerResponse fromJson(Object? json) {
    final map = _asMap(json, 'ServerResponse');
    return ServerResponse(
      type: map['type'] as String? ?? 'server-response',
      rpcId: map['rpcId'] as String,
      result: RpcResult.fromJson(map['result']),
    );
  }

  JsonMap toJson() => <String, Object?>{
    'type': type,
    'rpcId': rpcId,
    'result': result.toJson(),
  };
}

final class ServerRequest {
  ServerRequest({
    this.type = 'server-request',
    required this.rpcId,
    required this.method,
    required this.payload,
  });

  final String type;
  final String rpcId;
  final String method;
  final JsonMap payload;

  static ServerRequest fromJson(Object? json) {
    final map = _asMap(json, 'ServerRequest');
    return ServerRequest(
      type: map['type'] as String? ?? 'server-request',
      rpcId: map['rpcId'] as String,
      method: map['method'] as String,
      payload: _asMap(map['payload'], 'ServerRequest.payload'),
    );
  }

  JsonMap toJson() => <String, Object?>{
    'type': type,
    'rpcId': rpcId,
    'method': method,
    'payload': payload,
  };
}

final class RpcResult {
  RpcResult({required this.ok, this.value, this.error});

  final bool ok;
  final JsonMap? value;
  final RpcError? error;

  static RpcResult fromJson(Object? json) {
    final map = _asMap(json, 'RpcResult');
    final error = map['error'];
    final value = map['value'];
    return RpcResult(
      ok: map['ok'] as bool,
      value: value == null ? null : _asMap(value, 'RpcResult.value'),
      error: error == null ? null : RpcError.fromJson(error),
    );
  }

  JsonMap toJson() => <String, Object?>{
    'ok': ok,
    if (value != null) 'value': value,
    if (error != null) 'error': error!.toJson(),
  };
}

final class RpcError {
  RpcError({required this.code, required this.message, this.details});

  final String code;
  final String message;
  final JsonMap? details;

  static RpcError fromJson(Object? json) {
    final map = _asMap(json, 'RpcError');
    final details = map['details'];
    return RpcError(
      code: map['code'] as String,
      message: map['message'] as String,
      details: details == null ? null : _asMap(details, 'RpcError.details'),
    );
  }

  JsonMap toJson() => <String, Object?>{
    'code': code,
    'message': message,
    if (details != null) 'details': details,
  };
}

final class RpcReceipt {
  RpcReceipt({required this.accepted, this.reason});

  final bool accepted;
  final String? reason;

  static RpcReceipt fromJson(Object? json) {
    final map = _asMap(json, 'RpcReceipt');
    return RpcReceipt(
      accepted: map['accepted'] as bool,
      reason: map['reason'] as String?,
    );
  }

  JsonMap toJson() => <String, Object?>{
    'accepted': accepted,
    if (reason != null) 'reason': reason,
  };
}
