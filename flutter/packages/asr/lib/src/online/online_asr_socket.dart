/// Websocket transport seam for online ASR engines.
///
/// Engines talk to a [OnlineAsrSocket], never to `dart:io` directly, so unit
/// tests script a fake socket instead of opening real connections. The
/// production opener wraps `WebSocket.connect`; message events surface as
/// [Uint8List] (binary frames) or [String] (text frames), exactly the two
/// event kinds a `dart:io` websocket emits.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Opens an online ASR websocket session to [uri] with [headers].
typedef OnlineAsrSocketOpener = Future<OnlineAsrSocket> Function(
  Uri uri,
  Map<String, String> headers,
);

/// One live websocket session to an online speech service.
abstract interface class OnlineAsrSocket {
  /// Server frames: [Uint8List] for binary, [String] for text.
  ///
  /// The stream completes when the connection closes (either side). Failures
  /// surface as stream errors; engines treat any error as session death.
  Stream<Object> get messages;

  /// Sends one binary frame (never re-buffered; callers chunk their audio).
  void sendBinary(List<int> bytes);

  /// Sends one text frame (Tencent end-of-audio signal).
  void sendText(String text);

  /// Closes the session with a normal closure code. Best effort: errors on
  /// an already-dead socket are swallowed.
  Future<void> close();
}

/// `dart:io` production implementation of [OnlineAsrSocket].
class IoOnlineAsrSocket implements OnlineAsrSocket {
  IoOnlineAsrSocket._(this._socket);

  final WebSocket _socket;

  /// The production [OnlineAsrSocketOpener].
  static Future<OnlineAsrSocket> connect(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final WebSocket socket = await WebSocket.connect(
      uri.toString(),
      headers: headers,
    );
    return IoOnlineAsrSocket._(socket);
  }

  @override
  Stream<Object> get messages => _socket.cast<Object>();

  @override
  void sendBinary(List<int> bytes) {
    _socket.add(bytes);
  }

  @override
  void sendText(String text) {
    _socket.add(text);
  }

  @override
  Future<void> close() async {
    try {
      await _socket.close(WebSocketStatus.normalClosure);
    } on Exception {
      // A socket that already died does not make the session outcome worse.
    }
  }
}
