/// Volcengine Doubao full-duplex streaming ASR engine.
///
/// Wire protocol (mirrored from the official Python demo): a binary
/// websocket where the session opens with a full client request (JSON) and
/// audio rides as audio-only requests, each carrying a 4-byte sequence
/// number; the last package carries a negative one. The service replies
/// with JSON responses whose `result.text` is the running transcript.
///
/// Auth rides the `X-Api-Key` header (speech-console API key) plus the
/// required `X-Api-Resource-Id` and `X-Api-Request-Id` headers; no appid.
library;

import 'dart:async';
import 'dart:typed_data';

import 'online_asr_config.dart';
import 'online_asr_engine_base.dart';
import 'online_asr_socket.dart';
import 'volcengine_asr_protocol.dart';

/// One recording session against Volcengine Doubao streaming ASR.
class VolcengineDoubaoAsrEngine extends OnlineAsrEngineBase {
  VolcengineDoubaoAsrEngine({
    required this.config,
    this.opener = IoOnlineAsrSocket.connect,
    this.uid = 'dsh-android',
  });

  /// Session credentials (API key, endpoint, resource id).
  final VolcengineDoubaoAsrConfig config;

  /// Transport seam; production opens a `dart:io` websocket.
  final OnlineAsrSocketOpener opener;

  /// Client-side user id reported in the start request.
  final String uid;

  OnlineAsrSocket? _socket;
  StreamSubscription<Object>? _messagesSub;
  int _sequence = 1;
  bool _audioSent = false;
  bool _sessionEnded = false;

  @override
  bool get audioSent => _audioSent;

  @override
  Future<void> startSession() async {
    if (!config.isConfigured) {
      throw const OnlineAsrException('Volcengine API key is not configured');
    }
    final Uri uri =
        Uri.tryParse(config.effectiveEndpoint) ??
        (throw OnlineAsrException(
          'Invalid Volcengine endpoint: ${config.effectiveEndpoint}',
        ));
    clearSessionOutcome();
    _sequence = 1;
    _audioSent = false;
    _sessionEnded = false;

    final OnlineAsrSocket socket = await opener(uri, <String, String>{
      'X-Api-Key': config.apiKey,
      'X-Api-Resource-Id': config.resourceId,
      'X-Api-Request-Id': onlineAsrUuidV4(),
    });
    _socket = socket;
    _messagesSub = socket.messages.listen(
      _onMessage,
      onError: (Object error) {
        failSession('websocket error: $error');
      },
      onDone: markSessionComplete,
    );
    _send(AsrV3Request.fullClientRequest(_startPayload(), _sequence));
    _sequence++;
  }

  /// Session-opening JSON, matching the documented request body.
  Map<String, Object?> _startPayload() => <String, Object?>{
    'user': <String, Object?>{'uid': uid},
    'audio': <String, Object?>{
      'format': 'pcm',
      'codec': 'raw',
      'rate': 16000,
      'bits': 16,
      'channel': 1,
    },
    'request': <String, Object?>{
      'model_name': 'bigmodel',
      'enable_punc': true,
      'enable_itn': true,
      'result_type': 'full',
    },
  };

  @override
  void handleAudioBytes(Uint8List pcm) {
    if (_sessionEnded || _socket == null) {
      return;
    }
    _send(
      AsrV3Request.audioOnlyRequest(pcm, sequence: _sequence, isLast: false),
    );
    _sequence++;
    _audioSent = true;
  }

  @override
  Future<String> completeSession() async {
    if (_audioSent && !_sessionEnded) {
      // End-of-stream marker: an empty audio package with a negative
      // sequence, the live-streaming counterpart of the demo's final
      // file segment.
      _send(
        AsrV3Request.audioOnlyRequest(
          const <int>[],
          sequence: _sequence,
          isLast: true,
        ),
      );
      _sessionEnded = true;
      await waitForFinalResult();
    }
    await closeSocket();
    if (hasFailure && lastText.isEmpty) {
      throwIfFailed();
    }
    return lastText;
  }

  @override
  void abortSession() {
    _sessionEnded = true;
    unawaited(_messagesSub?.cancel());
    _messagesSub = null;
    unawaited(closeSocket());
  }

  void _onMessage(Object event) {
    if (event is! Uint8List) {
      return; // The service answers in binary frames only.
    }
    try {
      final AsrV3ServerFrame frame = AsrV3ResponseParser.parse(event);
      switch (frame) {
        case AsrV3ErrorResponse(:final int code, :final String message):
          failSession('[$code] $message');
        case AsrV3FullResponse(:final bool isLastPackage, :final payloadMsg):
          final Object? code = payloadMsg['code'];
          if (code is int && code != 0) {
            final Object? message = payloadMsg['message'];
            failSession('[$code] ${message ?? 'recognition failed'}');
            return;
          }
          final Object? result = payloadMsg['result'];
          if (result is Map<String, Object?>) {
            final Object? text = result['text'];
            if (text is String && text.isNotEmpty) {
              emitPartial(text);
            }
          }
          if (isLastPackage) {
            markSessionComplete();
          }
        case AsrV3IgnoredFrame():
          break;
      }
    } on ArgumentError catch (error) {
      failSession('malformed response frame: ${error.message}');
    } on FormatException {
      failSession('malformed response payload');
    }
  }

  void _send(Uint8List frame) {
    final OnlineAsrSocket? socket = _socket;
    if (socket == null || _sessionEnded) {
      return;
    }
    try {
      socket.sendBinary(frame);
    } on StateError {
      // The socket died between events and our knowledge of it; the
      // session ends and finish() reports whatever text arrived.
      _sessionEnded = true;
    }
  }

  Future<void> closeSocket() async {
    final OnlineAsrSocket? socket = _socket;
    _socket = null;
    await _messagesSub?.cancel();
    _messagesSub = null;
    await socket?.close();
  }
}
