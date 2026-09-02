/// Tencent Cloud real-time ASR engine running the Hunyuan
/// (`Hy-ASR-3.0-preview`) engine, mirroring the official
/// `speech_recognizer.py` websocket client.
///
/// The session URL signs itself: a per-session query string (sorted keys,
/// raw values) is HMAC-SHA1-signed with the SecretKey and Base64-encoded,
/// then appended percent-encoded. Audio rides as raw 16 kHz mono 16-bit PCM
/// binary frames (`voice_format=1`); results arrive as JSON text frames.
/// The session ends with the SDK's `{"type":"end"}` text frame.
///
/// The Hunyuan preview accepts at most one minute of audio per session.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'online_asr_config.dart';
import 'online_asr_engine_base.dart';
import 'online_asr_socket.dart';

/// Builds the per-session query parameters (all string-valued), mirroring
/// the official client's default set. [timestampSeconds] seeds both
/// `timestamp` and (as the SDK does when no nonce is set) `nonce`.
Map<String, String> tencentAsrQueryParams({
  required TencentHunyuanAsrConfig config,
  required String voiceId,
  required int timestampSeconds,
}) => <String, String>{
  'appid': config.appId,
  'sub_service_type': '1',
  'engine_model_type': config.engineModelType,
  'filter_dirty': '0',
  'filter_modal': '0',
  'filter_punc': '0',
  'needvad': '0',
  'convert_num_mode': '0',
  'word_info': '0',
  'language_judgment': '0',
  'secretid': config.secretId,
  'voice_format': '1',
  'voice_id': voiceId,
  'timestamp': '$timestampSeconds',
  'nonce': '$timestampSeconds',
  'expired': '${timestampSeconds + 24 * 60 * 60}',
  'reinforce_hotword': '0',
  'noise_threshold': '0',
  'speaker_diarization': '0',
};

/// The string the signature is computed over: `host/path?` + the sorted
/// `key=value` pairs minus `appid` (which lives in the path), with raw
/// — never percent-encoded — values.
String tencentAsrSignString({
  required String appId,
  required Map<String, String> params,
}) {
  final List<String> sortedKeys = params.keys.toList()..sort();
  final String pairs = sortedKeys
      .where((String key) => key != 'appid')
      .map((String key) => '$key=${params[key]}')
      .join('&');
  return 'asr.cloud.tencent.com/asr/v2/$appId?$pairs';
}

/// HMAC-SHA1 + Base64 signature of [signString] with [secretKey].
String tencentAsrSignature(String signString, String secretKey) =>
    base64.encode(
      Hmac(sha1, utf8.encode(secretKey)).convert(utf8.encode(signString)).bytes,
    );

/// Percent-encodes one query value the way Python's `quote(v, safe='')`
/// does: everything outside the unreserved set gets `%XX`-escaped.
String _quote(String value) => Uri.encodeComponent(value);

/// Assembles the signed websocket URL for one recognition session.
String tencentAsrSignedUrl({
  required TencentHunyuanAsrConfig config,
  required String voiceId,
  required int timestampSeconds,
}) {
  final Map<String, String> params = tencentAsrQueryParams(
    config: config,
    voiceId: voiceId,
    timestampSeconds: timestampSeconds,
  );
  final String signString = tencentAsrSignString(
    appId: config.appId,
    params: params,
  );
  final String signature = tencentAsrSignature(signString, config.secretKey);
  final List<String> sortedKeys = params.keys.toList()..sort();
  final String query = sortedKeys
      .where((String key) => key != 'appid')
      .map((String key) => '$key=${_quote(params[key]!)}')
      .join('&');
  return '${config.effectiveEndpoint}/${config.appId}'
      '?$query&signature=${_quote(signature)}';
}

/// One recording session against Tencent Hunyuan real-time ASR.
class TencentHunyuanAsrEngine extends OnlineAsrEngineBase {
  TencentHunyuanAsrEngine({
    required this.config,
    this.opener = IoOnlineAsrSocket.connect,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Session credentials (AppID, SecretId/SecretKey, endpoint).
  final TencentHunyuanAsrConfig config;
  final OnlineAsrSocketOpener opener;
  final DateTime Function() _clock;

  OnlineAsrSocket? _socket;
  StreamSubscription<Object>? _messagesSub;
  bool _sessionEnded = false;

  /// Finalized pieces by their result `index`, joined in order.
  final Map<int, String> _finalPieces = <int, String>{};
  String _currentPartial = '';

  @override
  bool get audioSent => _audioBytesSent;
  bool _audioBytesSent = false;

  @override
  Future<void> startSession() async {
    if (!config.isConfigured) {
      throw const OnlineAsrException(
        'Tencent AppID / SecretId / SecretKey are not fully configured',
      );
    }
    clearSessionOutcome();
    _sessionEnded = false;
    _finalPieces.clear();
    _currentPartial = '';

    final String url = tencentAsrSignedUrl(
      config: config,
      voiceId: onlineAsrUuidV4(),
      timestampSeconds: _clock().millisecondsSinceEpoch ~/ 1000,
    );
    final Uri uri =
        Uri.tryParse(url) ??
        (throw OnlineAsrException('Invalid Tencent endpoint: $url'));

    final OnlineAsrSocket socket = await opener(uri, const <String, String>{});
    _socket = socket;
    _messagesSub = socket.messages.listen(
      _onMessage,
      onError: (Object error) {
        failSession('websocket error: $error');
      },
      onDone: markSessionComplete,
    );
  }

  @override
  void handleAudioBytes(Uint8List pcm) {
    if (_sessionEnded || _socket == null) {
      return;
    }
    _send(pcm);
    _audioBytesSent = true;
  }

  @override
  Future<String> completeSession() async {
    if (!_sessionEnded) {
      // The official client's end-of-audio signal.
      _sendText('{"type":"end"}');
      _sessionEnded = true;
      await waitForFinalResult();
    }
    await closeSocket();
    final String text = _assemble();
    if (hasFailure && text.isEmpty) {
      throwIfFailed();
    }
    return text;
  }

  @override
  void abortSession() {
    _sessionEnded = true;
    unawaited(_messagesSub?.cancel());
    _messagesSub = null;
    unawaited(closeSocket());
  }

  /// The transcript so far: finalized pieces in order, then the piece
  /// still being recognized.
  String _assemble() {
    final List<int> orderedIndices = _finalPieces.keys.toList()..sort();
    final String finalized = orderedIndices
        .map((int index) => _finalPieces[index] ?? '')
        .join();
    return finalized + _currentPartial;
  }

  void _onMessage(Object event) {
    if (event is! String) {
      return; // The service answers in text frames only.
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(event);
    } on FormatException {
      failSession('malformed response payload');
      return;
    }
    if (decoded is! Map<String, Object?>) {
      failSession('malformed response payload');
      return;
    }
    final Object? code = decoded['code'];
    if (code is int && code != 0) {
      failSession('[$code] ${decoded['message'] ?? 'recognition failed'}');
      return;
    }
    if (decoded['final'] == 1) {
      markSessionComplete();
      return;
    }
    final Object? result = decoded['result'];
    if (result is! Map<String, Object?>) {
      return;
    }
    final Object? sliceType = result['slice_type'];
    final Object? text = result['voice_text_str'];
    final String piece = text is String ? text : '';
    if (sliceType == 2) {
      // One piece finalized; its text never changes again.
      final Object? index = result['index'];
      _finalPieces[index is int ? index : _finalPieces.length] = piece;
      _currentPartial = '';
      emitPartial(_assemble());
    } else if (sliceType == 1) {
      _currentPartial = piece;
      emitPartial(_assemble());
    } else if (sliceType == 0) {
      _currentPartial = '';
    }
  }

  void _send(Uint8List bytes) {
    final OnlineAsrSocket? socket = _socket;
    if (socket == null || _sessionEnded) {
      return;
    }
    try {
      socket.sendBinary(bytes);
    } on StateError {
      _sessionEnded = true;
    }
  }

  void _sendText(String text) {
    final OnlineAsrSocket? socket = _socket;
    if (socket == null || _sessionEnded) {
      return;
    }
    try {
      socket.sendText(text);
    } on StateError {
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
