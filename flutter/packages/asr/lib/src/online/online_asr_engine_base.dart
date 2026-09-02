/// Shared session machinery for online streaming ASR engines.
///
/// An online engine is a one-session object: [initialize] opens the socket,
/// [acceptAudio] streams PCM to the service, [finish] ends the session and
/// returns the final text. Failures surface by throwing from [finish] —
/// never via [Stream.addError] on the transcription stream, whose consumers
/// listen without an error handler.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../engine/asr_engine.dart';
import '../manifest/model_manifest.dart';

/// An online speech session failed; the message carries the service's own
/// error description when the wire provided one.
class OnlineAsrException implements Exception {
  const OnlineAsrException(this.message);

  final String message;

  @override
  String toString() => 'OnlineAsrException: $message';
}

/// Generates a UUIDv4 session id (voice/request id for the wire).
String onlineAsrUuidV4() {
  final Random random = Random.secure();
  final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final String hex = bytes
      .map((int b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Converts 16 kHz mono float32 samples ([-1.0, 1.0]) to little-endian
/// 16-bit PCM bytes, the format both providers require.
Uint8List pcm16FromFloat32(Float32List samples) {
  final ByteData data = ByteData(samples.length * 2);
  for (int i = 0; i < samples.length; i++) {
    final double scaled = samples[i] * 32767.0;
    data.setInt16(i * 2, scaled.round().clamp(-32768, 32767), Endian.little);
  }
  return data.buffer.asUint8List();
}

/// Template state machine behind `VolcengineDoubaoAsrEngine` and
/// `TencentHunyuanAsrEngine`.
abstract class OnlineAsrEngineBase implements AsrEngine {
  /// How long [finish] waits for the service's final result before
  /// returning whatever partial text arrived.
  static const Duration kFinalResultTimeout = Duration(seconds: 8);

  final StreamController<AsrTranscriptionChunk> _chunkController =
      // Buffered (not broadcast): events emitted before the controller's
      // listen attaches are delivered, never dropped.
      StreamController<AsrTranscriptionChunk>();

  AsrEngineState _state = AsrEngineState.uninitialized;
  String _lastText = '';
  Object? _failure;
  Completer<void> _finalCompleter = Completer<void>();

  @override
  AsrEngineState get state => _state;

  @override
  Stream<AsrTranscriptionChunk> get transcriptionStream =>
      _chunkController.stream;

  /// Whether at least one audio chunk reached the session.
  bool get audioSent;

  @override
  Future<void> initialize(AsrModelInfo? model, Directory? modelDir) async {
    if (_state == AsrEngineState.disposed) {
      throw StateError('Online ASR engine already disposed');
    }
    if (_state != AsrEngineState.uninitialized) {
      return;
    }
    // An online session is created per recording; a second initialize is a
    // caller bug. startSession throwing surfaces the connect/auth failure
    // to the caller before any audio is recorded.
    _state = AsrEngineState.ready;
    try {
      await startSession();
    } on Object {
      _state = AsrEngineState.uninitialized;
      rethrow;
    }
  }

  /// Opens the transport and sends the protocol-level start message.
  Future<void> startSession();

  /// Sends one PCM chunk to the live session. Ignored when the session is
  /// not capturing (already ended, or dead) — audio after the session
  /// closed is not an error the reader can act on.
  void handleAudioBytes(Uint8List pcm);

  /// Ends the session and returns the final transcription, throwing
  /// [OnlineAsrException] when the service reported a failure and no text.
  Future<String> completeSession();

  @override
  void acceptAudio(Float32List samples) {
    if (_state != AsrEngineState.ready && _state != AsrEngineState.listening) {
      return;
    }
    _state = AsrEngineState.listening;
    final Uint8List pcm = pcm16FromFloat32(samples);
    if (pcm.isEmpty) {
      return;
    }
    handleAudioBytes(pcm);
  }

  @override
  Future<String> finish() async {
    if (_state != AsrEngineState.ready && _state != AsrEngineState.listening) {
      return _lastText;
    }
    _state = AsrEngineState.transcribing;
    final String text = await completeSession();
    if (text.isNotEmpty) {
      _lastText = text;
    }
    if (_lastText.isNotEmpty) {
      _chunkController.add(
        AsrTranscriptionChunk(text: _lastText, isFinal: true),
      );
    }
    _state = AsrEngineState.ready;
    return _lastText;
  }

  @override
  void reset() {
    abortSession();
    _lastText = '';
    _failure = null;
    if (_state != AsrEngineState.disposed) {
      _state = AsrEngineState.ready;
    }
  }

  @override
  Future<void> dispose() async {
    abortSession();
    _state = AsrEngineState.disposed;
    // Close, but never await: a buffered (non-broadcast) controller's
    // done-future only settles once a listener consumes it, and a session
    // that failed before anyone listened would hang dispose forever.
    unawaited(_chunkController.close());
  }

  /// Streams an interim transcription to the UI.
  void emitPartial(String text) {
    if (text.isEmpty || _state == AsrEngineState.disposed) {
      return;
    }
    _lastText = text;
    if (!_chunkController.isClosed) {
      _chunkController.add(AsrTranscriptionChunk(text: text, isFinal: false));
    }
  }

  /// Marks the session failed with the service's error description.
  void failSession(String message) {
    _failure ??= OnlineAsrException(message);
    _completeFinal();
  }

  /// Marks the session ended from the wire side (final package or close).
  void markSessionComplete() => _completeFinal();

  /// The newest text the session produced (partial or final). Subclass
  /// [completeSession] implementations read it to honor partial results
  /// when the session ends without a final package.
  String get lastText => _lastText;

  /// Whether the wire reported a session failure.
  bool get hasFailure => _failure != null;

  /// The recorded failure, if any.
  Object? get failure => _failure;

  /// Whether the final result (or session end) already arrived.
  bool get isFinalArrived => _finalCompleter.isCompleted;

  /// Resets the per-session final marker; called by [startSession] users
  /// through [clearSessionOutcome] before a new wait.
  void clearSessionOutcome() {
    _failure = null;
    _lastText = '';
    _finalCompleter = Completer<void>();
  }

  /// Waits for the final result (bounded by [kFinalResultTimeout]).
  Future<void> waitForFinalResult() =>
      _finalCompleter.future.timeout(kFinalResultTimeout, onTimeout: () {});

  /// Throws the recorded failure, if the session ended in one.
  void throwIfFailed() {
    final Object? failure = _failure;
    if (failure != null) {
      throw failure;
    }
  }

  void _completeFinal() {
    if (!_finalCompleter.isCompleted) {
      _finalCompleter.complete();
    }
  }

  /// Tears the transport down without waiting for a result.
  void abortSession();
}
