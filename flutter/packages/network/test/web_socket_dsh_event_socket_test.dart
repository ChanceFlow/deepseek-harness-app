/// In-process tests for the `dart:io` WebSocket downlink seam against a local
/// `HttpServer` upgraded with `WebSocketTransformer`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:network/dsh_exceptions.dart';
import 'package:network/rpc_envelope.dart';
import 'package:network/web_socket_dsh_event_socket.dart';

/// Starts one in-process WebSocket server on an ephemeral loopback port.
///
/// [onUpgrade] receives the request (for header assertions) and the
/// server-side socket; its return value decides what the server sends.
/// Returns the server plus the pending upgrade, which resolves once a
/// client connects.
Future<(HttpServer, Future<WebSocket>)> startServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final upgraded = Completer<WebSocket>();
  server.listen((request) async {
    try {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      if (!upgraded.isCompleted) upgraded.complete(socket);
    } catch (error) {
      if (!upgraded.isCompleted) {
        upgraded.completeError(error);
      }
    }
  });
  return (server, upgraded.future);
}

void main() {
  test('onOpen fires and server-request frames decode', () async {
    final (server, upsert) = await startServer();
    addTearDown(() => server.close(force: true));
    final socket = WebSocketDshEventSocket(
      Uri.parse('http://127.0.0.1:${server.port}'),
    );
    final opened = Completer<void>();
    final frames = <ServerRequest>[];
    final subscription = socket
        .connect('/api/events.mux', onOpen: opened.complete)
        .listen(frames.add);
    addTearDown(() => subscription.cancel());

    await opened.future;
    final serverSocket = await upsert;
    serverSocket.add(
      jsonEncode(
        ServerRequest(
          rpcId: 'rpc-1',
          method: 'session/event',
          payload: <String, Object?>{'type': 'session/event'},
        ).toJson(),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(frames, hasLength(1));
    expect(frames.single.rpcId, 'rpc-1');
    expect(frames.single.method, 'session/event');
    await serverSocket.close();
  });

  test('offers permessage-deflate on the handshake', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    String? offered;
    server.listen((request) async {
      offered = request.headers.value('Sec-WebSocket-Extensions');
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        await WebSocketTransformer.upgrade(request);
      } else {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      }
    });
    addTearDown(() => server.close(force: true));

    final socket = WebSocketDshEventSocket(
      Uri.parse('http://127.0.0.1:${server.port}'),
    );
    final opened = Completer<void>();
    final subscription = socket
        .connect('/api/events.mux', onOpen: opened.complete)
        .listen((_) {});
    addTearDown(() => subscription.cancel());
    await opened.future;
    expect(offered, contains('permessage-deflate'));
  });

  test('negotiated deflate round-trips a large frame intact', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(
          request,
          compression: CompressionOptions.compressionDefault,
        );
        final body = 'chunk=${'x' * 512};' * 64;
        socket.add(
          jsonEncode(
            ServerRequest(
              rpcId: 'rpc-big',
              method: 'test/frame',
              payload: <String, Object?>{'body': body},
            ).toJson(),
          ),
        );
        await socket.close();
      } else {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      }
    });
    addTearDown(() => server.close(force: true));

    final socket = WebSocketDshEventSocket(
      Uri.parse('http://127.0.0.1:${server.port}'),
    );
    final frames = await socket.connect('/api/events.mux').toList();
    expect(frames, hasLength(1));
    expect(frames.single.payload['body'], contains('chunk=xxx'));
    expect(
      (frames.single.payload['body'] as String).length,
      greaterThan(30000),
    );
  });

  test('malformed JSON frame surfaces a DshTransportException', () async {
    final (server, upsert) = await startServer();
    addTearDown(() => server.close(force: true));
    final socket = WebSocketDshEventSocket(
      Uri.parse('http://127.0.0.1:${server.port}'),
    );
    final stream = socket.connect('/api/events.mux');
    final expectation = expectLater(
      stream,
      emitsError(isA<DshTransportException>()),
    );
    final serverSocket = await upsert;
    serverSocket.add('this is not json');
    await serverSocket.close();
    await expectation;
  });

  test('binary frame surfaces a DshTransportException', () async {
    final (server, upsert) = await startServer();
    addTearDown(() => server.close(force: true));
    final socket = WebSocketDshEventSocket(
      Uri.parse('http://127.0.0.1:${server.port}'),
    );
    final stream = socket.connect('/api/events.mux');
    final expectation = expectLater(
      stream,
      emitsError(isA<DshTransportException>()),
    );
    final serverSocket = await upsert;
    serverSocket.add(<int>[1, 2, 3]);
    await serverSocket.close();
    await expectation;
  });

  test('server close completes the stream', () async {
    final (server, upsert) = await startServer();
    addTearDown(() => server.close(force: true));
    final socket = WebSocketDshEventSocket(
      Uri.parse('http://127.0.0.1:${server.port}'),
    );
    final stream = socket.connect('/api/events.mux');
    final done = Completer<void>();
    stream.listen((_) {}, onDone: done.complete);
    final serverSocket = await upsert;
    await serverSocket.close();
    await done.future;
  });

  test('cancel does not hang when the peer never closes', () async {
    final (server, upsert) = await startServer();
    addTearDown(() => server.close(force: true));
    final socket = WebSocketDshEventSocket(
      Uri.parse('http://127.0.0.1:${server.port}'),
    );
    expect(socket.compression, same(CompressionOptions.compressionDefault));
    final opened = Completer<void>();
    final subscription = socket
        .connect('/api/events.mux', onOpen: opened.complete)
        .listen((_) {});
    await opened.future;
    await upsert;
    // The server never answers the close frame; cancel must still settle
    // within the bounded close (2 s) instead of hanging forever.
    await subscription.cancel().timeout(const Duration(seconds: 5));
  });

  test('connection failure surfaces a DshTransportException', () async {
    final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = dead.port;
    await dead.close(force: true);
    final socket = WebSocketDshEventSocket(
      Uri.parse('http://127.0.0.1:$port'),
    );
    await expectLater(
      socket.connect('/api/events.mux'),
      emitsError(isA<DshTransportException>()),
    );
  });
}