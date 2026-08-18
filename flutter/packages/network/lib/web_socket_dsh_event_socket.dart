/// Downlink-only WebSocket event stream over `package:web_socket_channel`.
library;

import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'dsh_event_socket.dart';
import 'dsh_exceptions.dart';
import 'rpc_envelope.dart';

final class WebSocketDshEventSocket implements DshEventSocket {
  WebSocketDshEventSocket(this._baseUrl);

  final Uri _baseUrl;

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) async* {
    final channel = WebSocketChannel.connect(_websocketUri(path));
    try {
      await channel.ready;
    } catch (error) {
      throw DshTransportException('event stream $path failed', error);
    }
    onOpen?.call();
    try {
      await for (final frame in channel.stream) {
        final text = frame as String;
        final Object? decoded;
        try {
          decoded = jsonDecode(text);
        } catch (error) {
          throw DshTransportException(
              'invalid server-request on $path', error);
        }
        yield ServerRequest.fromJson(decoded);
      }
    } finally {
      await channel.sink.close();
    }
  }

  Uri _websocketUri(String path) {
    final httpUri = _baseUrl.resolve(path);
    final scheme = httpUri.scheme == 'https' ? 'wss' : 'ws';
    return httpUri.replace(scheme: scheme);
  }
}
