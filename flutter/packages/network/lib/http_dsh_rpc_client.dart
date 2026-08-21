/// HTTP JSON-RPC client over `package:http`.
library;

import 'dart:convert';
import 'dart:io' show HttpClient;
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;

import 'dsh_exceptions.dart';
import 'dsh_rpc_client.dart';
import 'rpc_envelope.dart';

/// Bound on TCP/TLS connection establishment only — never a request deadline
/// (long-running RPCs like compaction stay unconstrained).
const Duration kDshRpcConnectTimeout = Duration(seconds: 10);

final class HttpDshRpcClient implements DshRpcClient {
  HttpDshRpcClient(
    this._baseUrl, {
    http.Client? httpClient,
    this.connectTimeout = kDshRpcConnectTimeout,
  }) : _httpClient = httpClient ??
           IOClient(
             HttpClient()
               ..connectionTimeout = connectTimeout,
           );

  final Uri _baseUrl;
  final http.Client _httpClient;

  /// See [kDshRpcConnectTimeout].
  final Duration connectTimeout;

  static const _headers = <String, String>{
    'Content-Type': 'application/json; charset=utf-8',
  };

  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload,
  ) async {
    final rpcId = _uuidV4();
    final request = ClientRequest(
      rpcId: rpcId,
      method: method,
      payload: payload,
    );
    return (await _execute('api/$endpoint', request.toJson(), rpcId)).result;
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
    String expectedRpcId,
  ) async {
    final responseText = await _executeRaw(path, requestJson);
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

  Future<String> _executeRaw(String path, JsonMap requestJson) async {
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
      response = await _httpClient.post(
        url,
        headers: _headers,
        body: jsonEncode(requestJson),
      );
    } catch (error) {
      throw DshTransportException('transport failure for $path', error);
    }
    final responseText = utf8.decode(response.bodyBytes);
    if (response.statusCode ~/ 100 != 2) {
      final clipped = responseText.length <= 300
          ? responseText
          : responseText.substring(0, 300);
      throw DshTransportException(
        'HTTP ${response.statusCode} for $path: $clipped',
      );
    }
    return responseText;
  }
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
