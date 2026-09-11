/// Downlink-only WebSocket event stream over `dart:io`'s `WebSocket`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dsh_event_socket.dart';
import 'dsh_exceptions.dart';
import 'rpc_envelope.dart';

final class WebSocketDshEventSocket implements DshWritableEventSocket {
  WebSocketDshEventSocket(
    this._baseUrl, {
    this.compression = CompressionOptions.compressionDefault,
    this.customClient,
    Map<String, String> headers = const <String, String>{},
  }) : _headers = Map<String, String>.unmodifiable(headers);

  final Uri _baseUrl;

  /// permessage-deflate offer sent in the handshake; the server decides
  /// whether it negotiates.
  final CompressionOptions compression;

  /// Optional `dart:io` client the handshake rides. The DI layer supplies a
  /// client whose certificate policy is already scoped (for a host the user
  /// opted to trust); null keeps the platform default. The caller owns the
  /// client's lifecycle.
  final HttpClient? customClient;

  final Map<String, String> _headers;

  /// Headers sent on every handshake. This package never reads, names, or
  /// validates their meaning — whatever the caller hands in is passed
  /// straight to `WebSocket.connect`, and the transport's own handshake
  /// headers are added by `dart:io` on top.
  Map<String, String> get headers => _headers;

  final Map<String, WebSocket> _sockets = <String, WebSocket>{};

  @override
  void send(String path, String message) {
    final socket = _sockets[path];
    if (socket == null || socket.readyState != WebSocket.open) {
      throw DshTransportException('cannot send on $path: socket is not open');
    }
    socket.add(message);
  }

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    // Not an async* generator: one suspended in `await for` on a dart:io
    // WebSocket never unwinds on subscription cancel (it never observes the
    // cancel), so cancel() would hang forever. The controller owns teardown
    // explicitly instead: onCancel cancels the web socket subscription and
    // closes the socket with a bound.
    late final StreamController<ServerRequest> controller;
    StreamSubscription<dynamic>? webSocketSub;
    WebSocket? webSocket;
    var cancelled = false;

    controller = StreamController<ServerRequest>(
      onListen: () async {
        try {
          webSocket = await WebSocket.connect(
            _websocketUri(path).toString(),
            compression: compression,
            customClient: customClient,
            headers: _headers,
          );
          if (cancelled) {
            await webSocket!.close();
            return;
          }
          _sockets[path] = webSocket!;
          onOpen?.call();
          webSocketSub = webSocket!.listen(
            (frame) {
              if (frame is! String) {
                controller.addError(
                  DshTransportException(
                    'invalid server-request on $path: non-text frame',
                  ),
                );
                return;
              }
              final Object? decoded;
              try {
                decoded = jsonDecode(frame);
              } catch (error) {
                controller.addError(
                  DshTransportException(
                    'invalid server-request on $path',
                    error,
                  ),
                );
                return;
              }
              controller.add(ServerRequest.fromJson(decoded));
            },
            onError: (Object error) {
              controller.addError(
                DshTransportException('event stream $path failed', error),
              );
            },
            onDone: () => unawaited(controller.close()),
            cancelOnError: true,
          );
        } catch (error) {
          if (identical(_sockets[path], webSocket)) {
            _sockets.remove(path);
          }
          await _closeQuietly(webSocket);
          controller.addError(
            DshTransportException('event stream $path failed', error),
          );
          unawaited(controller.close());
        }
      },
      onCancel: () async {
        cancelled = true;
        if (identical(_sockets[path], webSocket)) {
          _sockets.remove(path);
        }
        await webSocketSub?.cancel();
        await _closeQuietly(webSocket);
      },
    );
    return controller.stream;
  }

  Future<void> _closeQuietly(WebSocket? webSocket) async {
    if (webSocket == null ||
        (webSocket.readyState != WebSocket.open &&
            webSocket.readyState != WebSocket.connecting)) {
      return;
    }
    try {
      // Bounded graceful close: a peer that never answers the close frame
      // must not hang the caller (subscription cancel / generation teardown).
      await webSocket.close().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    } on Exception {
      // Abandon the socket to the OS; nothing else to clean up.
    }
  }

  Uri _websocketUri(String path) {
    final httpUri = _baseUrl.resolve(path);
    final scheme = httpUri.scheme == 'https' ? 'wss' : 'ws';
    return httpUri.replace(scheme: scheme);
  }
}
