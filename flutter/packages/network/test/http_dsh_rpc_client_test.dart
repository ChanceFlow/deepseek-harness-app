/// Tests for the HTTP JSON-RPC client against an in-memory `MockClient`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:network/dsh_exceptions.dart';
import 'package:network/http_dsh_rpc_client.dart';
import 'package:network/rpc_envelope.dart';

/// A valid success envelope answering [request]'s rpcId, optionally padded so
/// the response body has a known order of magnitude.
http.Response _okResponse(http.Request request, {int padding = 0}) {
  final sent = jsonDecode(request.body) as Map<String, Object?>;
  return http.Response(
    jsonEncode(
      ServerResponse(
        rpcId: sent['rpcId'] as String,
        result: RpcResult(
          ok: true,
          value: <String, Object?>{if (padding > 0) 'pad': 'x' * padding},
        ),
      ).toJson(),
    ),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  test('call decodes the server response and echoes rpcId', () async {
    final client = HttpDshRpcClient(
      Uri.parse('http://127.0.0.1:3080'),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/session/list');
        final sent = jsonDecode(request.body) as Map<String, Object?>;
        expect(sent['payload'], <String, Object?>{'args': <String, Object?>{}});
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

    final result = await client.call('session/list', 'session/list', {});
    expect(result.ok, isTrue);
    expect(result.value, <String, Object?>{'sessions': <Object?>[]});
  });

  test('non-2xx response surfaces a DshTransportException', () async {
    final client = HttpDshRpcClient(
      Uri.parse('http://127.0.0.1:3080'),
      httpClient: MockClient((request) async => http.Response('boom', 500)),
    );

    // The status travels as a field, so a classifier never parses it back out
    // of the message.
    await expectLater(
      client.call('session/list', 'session/list', {}),
      throwsA(
        isA<DshTransportException>().having(
          (error) => error.httpStatus,
          'httpStatus',
          500,
        ),
      ),
    );
  });

  test('a transport failure with no response carries no status', () async {
    final client = HttpDshRpcClient(
      Uri.parse('http://127.0.0.1:3080'),
      httpClient: MockClient(
        (request) async => throw http.ClientException('connection refused'),
      ),
    );

    await expectLater(
      client.call('session/list', 'session/list', {}),
      throwsA(
        isA<DshTransportException>()
            .having((error) => error.httpStatus, 'httpStatus', isNull)
            .having(
              (error) => error.message,
              'message',
              startsWith('transport failure'),
            ),
      ),
    );
  });

  test('invalid JSON response surfaces a DshTransportException', () async {
    final client = HttpDshRpcClient(
      Uri.parse('http://127.0.0.1:3080'),
      httpClient: MockClient((request) async => http.Response('not json', 200)),
    );

    await expectLater(
      client.call('session/list', 'session/list', {}),
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
      client.call('session/list', 'session/list', {}),
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

  group('caller headers', () {
    test('a supplied header reaches the outgoing HTTP request', () async {
      late http.BaseRequest sent;
      final client = HttpDshRpcClient(
        Uri.parse('http://127.0.0.1:3080'),
        headers: {'X-Caller-Header': 'caller-value'},
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode(
              ServerResponse(
                rpcId:
                    (jsonDecode(request.body) as Map<String, Object?>)['rpcId']
                        as String,
                result: RpcResult(ok: true),
              ).toJson(),
            ),
            200,
          );
        }),
      );

      final result = await client.call('session/list', 'session/list', {});
      expect(result.ok, isTrue);
      // The package never interprets the header; it only passes it on, so the
      // name and value are opaque test data.
      expect(sent.headers['X-Caller-Header'], 'caller-value');
      expect(sent.headers['Content-Type'], 'application/json; charset=utf-8');
    });

    test('the caller may override Content-Type, in any casing', () async {
      late http.BaseRequest sent;
      final client = HttpDshRpcClient(
        Uri.parse('http://127.0.0.1:3080'),
        headers: {'content-type': 'application/json'},
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode(
              ServerResponse(
                rpcId:
                    (jsonDecode(request.body) as Map<String, Object?>)['rpcId']
                        as String,
                result: RpcResult(ok: true),
              ).toJson(),
            ),
            200,
          );
        }),
      );

      await client.call('session/list', 'session/list', {});
      expect(sent.headers['content-type'], 'application/json');
      // Exactly one content type, never the default appended beside it.
      expect(
        sent.headers.keys.where((key) => key.toLowerCase() == 'content-type'),
        ['content-type'],
      );
    });

    test('no headers supplied leaves the request byte-identical', () async {
      late http.BaseRequest sent;
      final client = HttpDshRpcClient(
        Uri.parse('http://127.0.0.1:3080'),
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode(
              ServerResponse(
                rpcId:
                    (jsonDecode(request.body) as Map<String, Object?>)['rpcId']
                        as String,
                result: RpcResult(ok: true),
              ).toJson(),
            ),
            200,
          );
        }),
      );

      await client.call('session/list', 'session/list', {});
      expect(client.headers, isEmpty);
      expect(sent.headers, {'Content-Type': 'application/json; charset=utf-8'});
    });

    test('the caller map is copied, so later mutation cannot leak in', () {
      final supplied = <String, String>{'X-One': '1'};
      final client = HttpDshRpcClient(
        Uri.parse('http://127.0.0.1:3080'),
        headers: supplied,
        httpClient: MockClient((request) async => http.Response('{}', 200)),
      );
      supplied['X-Two'] = '2';
      expect(client.headers, {'X-One': '1'});
      expect(client.effectiveHeaders, {
        'Content-Type': 'application/json; charset=utf-8',
        'X-One': '1',
      });
    });
  });

  group('request deadline', () {
    test('a per-call deadline surfaces as DshTransportException', () {
      // Deterministic time: `fake_async` owns the clock, and `MockClient`'s
      // handler leaves the future pending without ever touching a real timer,
      // so nothing can race. Doing the work inside `flushMicrotasks` (rather
      // than an async callback) keeps `fakeAsync`'s zone in charge.
      fakeAsync((async) {
        Object? observed;
        final client = HttpDshRpcClient(
          Uri.parse('http://127.0.0.1:3080'),
          httpClient: MockClient(
            (request) => Completer<http.Response>().future,
          ),
        );

        // `onError` records the failure instead of leaving it unhandled in the
        // fake zone; the handler returns null, which is a valid RpcResult?.
        final pending = client.call(
          'session/list',
          'session/list',
          {},
          timeout: const Duration(seconds: 5),
        );
        unawaited(
          pending.then(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              observed = error;
            },
          ),
        );

        async.flushMicrotasks();
        expect(observed, isNull, reason: 'the response is still pending');

        async.elapse(const Duration(seconds: 5));
        expect(observed, isA<DshTransportException>());
        final failure = observed! as DshTransportException;
        expect(failure.message, contains('5000ms'));
        // Reports the deadline itself, not a cause-less HTTP-status failure.
        expect(failure.cause, isA<TimeoutException>());
      });
    });

    test('no deadline leaves a slow response unbounded', () {
      fakeAsync((async) {
        final responses = <RpcResult>[];
        final client = HttpDshRpcClient(
          Uri.parse('http://127.0.0.1:3080'),
          httpClient: MockClient(
            (request) => Future<http.Response>.delayed(
              const Duration(seconds: 90),
              () => http.Response(
                jsonEncode(
                  ServerResponse(
                    rpcId:
                        (jsonDecode(request.body)
                                as Map<String, Object?>)['rpcId']
                            as String,
                    result: RpcResult(ok: true),
                  ).toJson(),
                ),
                200,
              ),
            ),
          ),
        );

        final pending = client.call('session/list', 'session/list', {});
        unawaited(pending.then(responses.add));
        async.flushMicrotasks();

        async.elapse(const Duration(minutes: 2));
        async.flushMicrotasks();
        expect(responses, hasLength(1));
        expect(responses.single.ok, isTrue);
      });
    });
  });

  group('exchange listener', () {
    test(
      'reports the path, response bytes and elapsed time of one call',
      () async {
        final exchanges = <(String, int, Duration)>[];
        final client = HttpDshRpcClient(
          Uri.parse('http://127.0.0.1:3080'),
          httpClient: MockClient(
            (request) async => _okResponse(request, padding: 4096),
          ),
          onExchange: (path, responseBytes, elapsed) =>
              exchanges.add((path, responseBytes, elapsed)),
        );

        await client.call('session/list', 'session/list', {});

        expect(exchanges, hasLength(1));
        expect(exchanges.single.$1, 'api/session/list');
        expect(exchanges.single.$2, greaterThan(4096));
        expect(exchanges.single.$3, greaterThanOrEqualTo(Duration.zero));
      },
    );

    test('measures the exchange wall time, not just dispatch', () async {
      final elapsed = <Duration>[];
      final client = HttpDshRpcClient(
        Uri.parse('http://127.0.0.1:3080'),
        httpClient: MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          return _okResponse(request);
        }),
        onExchange: (path, responseBytes, duration) => elapsed.add(duration),
      );

      await client.call('session/list', 'session/list', {});

      // The Stopwatch covers the awaited response, so a slow host is visible.
      expect(elapsed.single, greaterThan(const Duration(milliseconds: 100)));
    });

    test('an HTTP failure reports zero bytes through the listener', () async {
      final exchanges = <(String, int, Duration)>[];
      final client = HttpDshRpcClient(
        Uri.parse('http://127.0.0.1:3080'),
        httpClient: MockClient((request) async => http.Response('boom', 500)),
        onExchange: (path, responseBytes, elapsed) =>
            exchanges.add((path, responseBytes, elapsed)),
      );

      await expectLater(
        client.call('session/list', 'session/list', {}),
        throwsA(isA<DshTransportException>()),
      );

      expect(exchanges, hasLength(1));
      expect(exchanges.single.$1, 'api/session/list');
      expect(exchanges.single.$2, 0);
    });

    test(
      'a transport failure reports zero bytes through the listener',
      () async {
        final exchanges = <(String, int, Duration)>[];
        final client = HttpDshRpcClient(
          Uri.parse('http://127.0.0.1:3080'),
          httpClient: MockClient(
            (request) async => throw http.ClientException('connection refused'),
          ),
          onExchange: (path, responseBytes, elapsed) =>
              exchanges.add((path, responseBytes, elapsed)),
        );

        await expectLater(
          client.call('session/list', 'session/list', {}),
          throwsA(isA<DshTransportException>()),
        );

        expect(exchanges, hasLength(1));
        expect(exchanges.single.$2, 0);
      },
    );

    test('a throwing listener never changes a successful result', () async {
      final client = HttpDshRpcClient(
        Uri.parse('http://127.0.0.1:3080'),
        httpClient: MockClient((request) async => _okResponse(request)),
        onExchange: (path, responseBytes, elapsed) =>
            throw StateError('listener blew up'),
      );

      final result = await client.call('session/list', 'session/list', {});
      expect(result.ok, isTrue);
    });

    test('a throwing listener never masks the transport failure', () async {
      final client = HttpDshRpcClient(
        Uri.parse('http://127.0.0.1:3080'),
        httpClient: MockClient((request) async => http.Response('boom', 500)),
        onExchange: (path, responseBytes, elapsed) =>
            throw StateError('listener blew up'),
      );

      await expectLater(
        client.call('session/list', 'session/list', {}),
        throwsA(
          isA<DshTransportException>().having(
            (error) => error.message,
            'message',
            startsWith('HTTP 500'),
          ),
        ),
      );
    });
  });
}
