/// HTTP JSON-RPC client over `package:http`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;

import 'dsh_exceptions.dart';
import 'dsh_rpc_client.dart';
import 'rpc_envelope.dart';

/// Bound on TCP/TLS connection establishment only — never a request deadline
/// (long-running RPCs like compaction stay unconstrained unless their caller
/// passes a per-call `timeout`).
const Duration kDshRpcConnectTimeout = Duration(seconds: 10);

/// The content type this client always sends unless a caller overrides it;
/// see [HttpDshRpcClient.effectiveHeaders] for the precedence rule.
const String _jsonContentType = 'application/json; charset=utf-8';

final class HttpDshRpcClient implements DshRpcClient {
  HttpDshRpcClient(
    this._baseUrl, {
    http.Client? httpClient,
    this.connectTimeout = kDshRpcConnectTimeout,
    Map<String, String> headers = const <String, String>{},
  }) : _callerHeaders = Map<String, String>.unmodifiable(headers),
       _headers = Map<String, String>.unmodifiable(_mergeHeaders(headers)),
       _httpClient =
           httpClient ??
           IOClient(HttpClient()..connectionTimeout = connectTimeout);

  final Uri _baseUrl;
  final http.Client _httpClient;
  final Map<String, String> _callerHeaders;
  final Map<String, String> _headers;

  /// See [kDshRpcConnectTimeout].
  final Duration connectTimeout;

  /// Headers the caller supplied at construction. This package never reads,
  /// names, or validates their meaning — whatever is handed in is copied
  /// onto every outgoing request.
  Map<String, String> get headers => _callerHeaders;

  /// The exact header map sent on every outgoing HTTP request: the caller's
  /// [headers] plus this client's JSON content type.
  ///
  /// Precedence: a caller entry wins over the built-in default, matched
  /// case-insensitively, so a caller may replace `Content-Type` but never
  /// silently drop it.
  Map<String, String> get effectiveHeaders => _headers;

  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async {
    final rpcId = _uuidV4();
    final wrappedPayload = payload.containsKey('args') && payload.length == 1
        ? payload
        : <String, Object?>{'args': payload};
    final request = ClientRequest(
      rpcId: rpcId,
      method: method,
      payload: wrappedPayload,
    );
    return (await _execute(
      'api/$endpoint',
      request.toJson(),
      rpcId,
      timeout: timeout,
    )).result;
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {
    final request = ClientResponse(rpcId: rpcId, result: result);
    final responseText = await _executeRaw('api/respond', request.toJson());
    final RpcReceipt receipt;
    try {
      receipt = RpcReceipt.fromJson(jsonDecode(responseText));
    } catch (error) {
      throw DshTransportException(
        'invalid server receipt for api/respond',
        error,
      );
    }
    if (!receipt.accepted) {
      throw DshBusinessException(
        code: receipt.reason ?? 'bad-response',
        message: 'server did not accept client response',
      );
    }
  }

  Future<ServerResponse> _execute(
    String path,
    JsonMap requestJson,
    String expectedRpcId, {
    Duration? timeout,
  }) async {
    final responseText = await _executeRaw(path, requestJson, timeout: timeout);
    final ServerResponse decoded;
    try {
      decoded = ServerResponse.fromJson(jsonDecode(responseText));
    } catch (error) {
      throw DshTransportException('invalid server-response for $path', error);
    }
    if (decoded.rpcId != expectedRpcId) {
      throw DshTransportException(
        'rpcId mismatch for $path: expected $expectedRpcId, '
        'got ${decoded.rpcId}',
      );
    }
    return decoded;
  }

  Future<String> _executeRaw(
    String path,
    JsonMap requestJson, {
    Duration? timeout,
  }) async {
    final Uri url;
    try {
      url = _baseUrl.resolve(path);
    } catch (error) {
      throw DshTransportException(
        'cannot resolve $path against $_baseUrl',
        error,
      );
    }
    final http.Response response;
    try {
      // The deadline owns the whole exchange: the timeout wraps the request
      // future, so a response body that never finishes also times out.
      // `null` leaves the request unbounded, as before.
      final request = _httpClient.post(
        url,
        headers: _headers,
        body: jsonEncode(requestJson),
      );
      response = await (timeout == null ? request : request.timeout(timeout));
    } on TimeoutException catch (error) {
      throw DshTransportException(
        'request deadline ${timeout!.inMilliseconds}ms exceeded for $path',
        error,
      );
    } catch (error) {
      throw DshTransportException('transport failure for $path', error);
    }
    final responseText = utf8.decode(response.bodyBytes);
    if (response.statusCode ~/ 100 != 2) {
      final clipped = responseText.length <= 300
          ? responseText
          : responseText.substring(0, 300);
      throw DshTransportException.http(
        'HTTP ${response.statusCode} for $path: $clipped',
        response.statusCode,
      );
    }
    return responseText;
  }
}

/// Builds the outgoing header map from the caller's [headers].
///
/// The JSON content type is always present unless the caller overrides it
/// with a differently-cased key, in which case the caller's entry replaces
/// the default rather than being appended beside it (two `Content-Type`
/// values on one request is not a valid HTTP message).
Map<String, String> _mergeHeaders(Map<String, String> headers) {
  final merged = <String, String>{'Content-Type': _jsonContentType};
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == 'content-type') {
      merged.remove('Content-Type');
    }
    merged[entry.key] = entry.value;
  }
  return merged;
}

String _uuidV4() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
