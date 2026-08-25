/// Tests for the HTTP JSON-RPC client against an in-memory `MockClient`.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:network/dsh_exceptions.dart';
import 'package:network/http_dsh_rpc_client.dart';
import 'package:network/rpc_envelope.dart';

void main() {
  test('call decodes the server response and echoes rpcId', () async {
    final client = HttpDshRpcClient(
      Uri.parse('http://127.0.0.1:3080'),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/session.list');
        final sent = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode(
            ServerResponse(
              rpcId: sent['rpcId'] as String,
              result: RpcResult(
                ok: true,
                value: <String, Object?>{'sessions': <Object?>[]},
              ),
            ).toJson(),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final result = await client.call('session.list', 'session.list', {});
    expect(result.ok, isTrue);
    expect(result.value, <String, Object?>{'sessions': <Object?>[]});
  });

  test('non-2xx response surfaces a DshTransportException', () async {
    final client = HttpDshRpcClient(
      Uri.parse('http://127.0.0.1:3080'),
      httpClient: MockClient((request) async => http.Response('boom', 500)),
    );

    await expectLater(
      client.call('session.list', 'session.list', {}),
      throwsA(isA<DshTransportException>()),
    );
  });

  test('invalid JSON response surfaces a DshTransportException', () async {
    final client = HttpDshRpcClient(
      Uri.parse('http://127.0.0.1:3080'),
      httpClient: MockClient((request) async => http.Response('not json', 200)),
    );

    await expectLater(
      client.call('session.list', 'session.list', {}),
      throwsA(isA<DshTransportException>()),
    );
  });

  test('rpcId mismatch surfaces a DshTransportException', () async {
    final client = HttpDshRpcClient(
      Uri.parse('http://127.0.0.1:3080'),
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode(
            ServerResponse(
              rpcId: 'some-other-id',
              result: RpcResult(ok: true),
            ).toJson(),
          ),
          200,
        ),
      ),
    );

    await expectLater(
      client.call('session.list', 'session.list', {}),
      throwsA(isA<DshTransportException>()),
    );
  });

  test('respond accepts a receipt silently', () async {
    final client = HttpDshRpcClient(
      Uri.parse('http://127.0.0.1:3080'),
      httpClient: MockClient(
        (request) async =>
            http.Response(jsonEncode(RpcReceipt(accepted: true).toJson()), 200),
      ),
    );

    await client.respond('rpc-1', RpcResult(ok: true));
  });

  test('respond rejection surfaces a DshBusinessException', () async {
    final client = HttpDshRpcClient(
      Uri.parse('http://127.0.0.1:3080'),
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode(RpcReceipt(accepted: false, reason: 'gone').toJson()),
          200,
        ),
      ),
    );

    await expectLater(
      client.respond('rpc-1', RpcResult(ok: true)),
      throwsA(isA<DshBusinessException>()),
    );
  });

  test('connectTimeout config is exposed', () {
    final client = HttpDshRpcClient(
      Uri.parse('http://127.0.0.1:3080'),
      httpClient: MockClient((request) async => http.Response('{}', 200)),
      connectTimeout: const Duration(seconds: 3),
    );
    expect(client.connectTimeout, const Duration(seconds: 3));
  });
}
