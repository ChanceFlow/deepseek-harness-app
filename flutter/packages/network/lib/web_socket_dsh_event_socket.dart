/// Downlink-only WebSocket event stream over `dart:io`'s `WebSocket`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dsh_event_socket.dart';
import 'dsh_exceptions.dart';
import 'rpc_envelope.dart';

final class WebSocketDshEventSocket implements DshEventSocket {
  WebSocketDshEventSocket(
    this._baseUrl, {
    this.compression = CompressionOptions.compressionDefault,
  });

  final Uri _baseUrl;

  /// permessage-deflate offer sent in the handshake; the server decides
  /// whether it negotiates.
  final CompressionOptions compression;

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
          );
          if (cancelled) {
            await webSocket!.close();
            return;
          }
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
          controller.addError(
            DshTransportException('event stream $path failed', error),
          );
          unawaited(controller.close());
        }
      },
      onCancel: () async {
        cancelled = true;
        await webSocketSub?.cancel();
        await _closeQuietly(webSocket);
      },
    );
    return controller.stream;
  }

  Future<void> _closeQuietly(WebSocket? webSocket) async {
    if (webSocket == null || webSocket.readyState != WebSocket.open) return;
    try {
      // Bounded graceful close: a peer that never answers the close frame
      // must not hang the caller (subscription cancel / generation teardown).
      await webSocket
          .close()
          .timeout(const Duration(seconds: 2), onTimeout: () {});
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