/// UDF Controller managing voice recording, VAD/silence timers, and speech engine dispatch.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:asr/asr.dart';
import 'package:flutter/services.dart';
import '../../../platform/audio_recorder.dart';
import 'voice_input_ui_state.dart';

/// Callback invoked when transcription updates arrive (partial or final).
typedef OnTranscriptionUpdate = void Function(String text, bool isFinal);

/// Controller driving on-device voice input and streaming state.
class VoiceInputController {
  VoiceInputController({
    required this.manager,
    AudioInputSource? audioRecorder,
    this.engine,
    this.onTranscriptionUpdate,
  })  : _recorder = audioRecorder ?? PlatformAudioRecorder() {
    _init();
  }

  final AsrModelManager manager;
  final AudioInputSource _recorder;
  final AsrEngine? engine;
  final OnTranscriptionUpdate? onTranscriptionUpdate;

  final StreamController<VoiceInputUiState> _stateController =
      StreamController<VoiceInputUiState>.broadcast();

  VoiceInputUiState _state = const VoiceInputUiState();
  VoiceInputUiState get state => _state;
  Stream<VoiceInputUiState> get uiState => _stateController.stream;

  StreamSubscription<Float32List>? _audioSub;
  StreamSubscription<double>? _amplitudeSub;
  StreamSubscription<AsrTranscriptionChunk>? _transcriptionSub;
  StreamSubscription<Map<String, ModelRegistryEntry>>? _registrySub;
  Timer? _durationTimer;
  DateTime? _recordingStartTime;

  void _init() {
    _refreshModelStatus();
    _registrySub = manager.updates.listen((_) => _refreshModelStatus());
  }

  void _refreshModelStatus() {
    final active = manager.getActiveModel();
    final hasInstalled = manager.installedCount > 0;
    _emit(_state.copyWith(
      activeModel: active,
      hasInstalledModels: hasInstalled,
    ));
  }

  void _emit(VoiceInputUiState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  /// Starts voice recording session using the configured active model.
  Future<void> startRecording() async {
    if (_state.isBusy) return;

    final activeModel = manager.getActiveModel();
    if (activeModel == null) {
      _emit(_state.copyWith(
        phase: VoiceInputPhase.error,
        errorMessage: 'NO_MODEL_INSTALLED',
      ));
      return;
    }

    _emit(_state.copyWith(
      phase: VoiceInputPhase.initializing,
      duration: Duration.zero,
      amplitude: 0.0,
      liveTranscription: '',
      clearError: true,
      activeModel: activeModel,
    ));

    // Request permissions if needed
    final recorder = _recorder;
    if (recorder is PlatformAudioRecorder) {
      final hasPerm = await recorder.checkPermission();
      if (!hasPerm) {
        final granted = await recorder.requestPermission();
        if (!granted) {
          _emit(_state.copyWith(
            phase: VoiceInputPhase.error,
            errorMessage: 'PERMISSION_DENIED',
          ));
          return;
        }
      }
    }

    try {
      // Prepare engine
      final modelDir = manager.getModelDir(activeModel.id);
      final activeEngine = engine ?? _createEngineForModel(activeModel);
      await activeEngine.initialize(activeModel, modelDir);

      await _transcriptionSub?.cancel();
      _transcriptionSub = activeEngine.transcriptionStream.listen((chunk) {
        _emit(_state.copyWith(liveTranscription: chunk.text));
        onTranscriptionUpdate?.call(chunk.text, chunk.isFinal);
      });

      // Subscribe to the audio/amplitude streams before capture starts:
      // both are broadcast (non-buffering), so events emitted between
      // start() and subscription would otherwise be dropped, losing the
      // first ~100ms of input.
      await _audioSub?.cancel();
      _audioSub = _recorder.audioStream.listen((samples) {
        activeEngine.acceptAudio(samples);
      });

      await _amplitudeSub?.cancel();
      _amplitudeSub = _recorder.amplitudeStream.listen((amp) {
        _emit(_state.copyWith(amplitude: amp));
      });

      try {
        await _recorder.start();
      } on PlatformException {
        // Native AudioRecord failed to start (e.g. device/emulator input
        // unavailable). Surface a stable, localizable error instead of a
        // phantom recording dock whose waveform never moves.
        await cancelRecording();
        _emit(_state.copyWith(
          phase: VoiceInputPhase.error,
          errorMessage: 'RECORD_START_FAILED',
        ));
        return;
      }

      _recordingStartTime = DateTime.now();
      _durationTimer?.cancel();
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_recordingStartTime != null) {
          final elapsed = DateTime.now().difference(_recordingStartTime!);
          _emit(_state.copyWith(duration: elapsed));
        }
      });

      _emit(_state.copyWith(phase: VoiceInputPhase.recording));
    } catch (e) {
      await cancelRecording();
      _emit(_state.copyWith(
        phase: VoiceInputPhase.error,
        errorMessage: e.toString(),
      ));
    }
  }

  /// Completes the recording, finalizes speech-to-text, and returns final text.
  Future<String> stopRecording() async {
    if (!_state.isRecording) return '';

    _emit(_state.copyWith(phase: VoiceInputPhase.finalizing));

    _durationTimer?.cancel();
    _durationTimer = null;
    await _audioSub?.cancel();
    _audioSub = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    await _recorder.stop();

    String finalResult = '';
    try {
      final activeEngine = engine ?? _createEngineForModel(_state.activeModel);
      finalResult = await activeEngine.finish();
      onTranscriptionUpdate?.call(finalResult, true);
    } catch (e) {
      _emit(_state.copyWith(
        phase: VoiceInputPhase.error,
        errorMessage: e.toString(),
      ));
    } finally {
      _emit(_state.copyWith(
        phase: VoiceInputPhase.idle,
        duration: Duration.zero,
        amplitude: 0.0,
      ));
    }
    return finalResult;
  }

  /// Cancels recording and discards audio buffers.
  Future<void> cancelRecording() async {
    _durationTimer?.cancel();
    _durationTimer = null;
    await _audioSub?.cancel();
    _audioSub = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    await _transcriptionSub?.cancel();
    _transcriptionSub = null;
    await _recorder.stop();

    engine?.reset();

    _emit(_state.copyWith(
      phase: VoiceInputPhase.idle,
      duration: Duration.zero,
      amplitude: 0.0,
      liveTranscription: '',
    ));
  }

  void dismissError() {
    _emit(_state.copyWith(
      phase: VoiceInputPhase.idle,
      clearError: true,
    ));
  }

  AsrEngine _createEngineForModel(AsrModelInfo? model) {
    if (model == null) return MockAsrEngine();
    if (model.id == 'zipformer-bilingual') {
      return StreamingZipformerEngine();
    }
    return NonStreamingAsrEngine();
  }

  void dispose() {
    _durationTimer?.cancel();
    unawaited(_audioSub?.cancel());
    unawaited(_amplitudeSub?.cancel());
    unawaited(_transcriptionSub?.cancel());
    unawaited(_registrySub?.cancel());
    unawaited(_recorder.dispose());
    unawaited(_stateController.close());
  }
}