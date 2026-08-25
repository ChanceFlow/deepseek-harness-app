/// UDF Controller managing voice recording, VAD/silence timers, and speech engine dispatch.
library;

import 'dart:async';

import 'package:asr/asr.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../../platform/audio_recorder.dart';
import '../../../platform/sherpa_offline_asr_engine.dart';
import 'voice_input_ui_state.dart';

/// Callback invoked when transcription updates arrive (partial or final).
typedef OnTranscriptionUpdate = void Function(String text, bool isFinal);

/// Creates the session engine when none is injected. Exposed as a seam so
/// tests can assert the engine instance is reused across acceptAudio and
/// finish (the phone path uses [SherpaOfflineAsrEngine]).
typedef AsrEngineFactory = AsrEngine Function(AsrModelInfo? model);

/// Controller driving on-device voice input and streaming state.
class VoiceInputController {
  VoiceInputController({
    required this.manager,
    AudioInputSource? audioRecorder,
    this.engine,
    this.onTranscriptionUpdate,
    AsrEngineFactory? engineFactory,
  })  : _recorder = audioRecorder ?? PlatformAudioRecorder(),
        _engineFactory = engineFactory ?? _defaultEngineFactory {
    _init();
  }

  final AsrModelManager manager;
  final AudioInputSource _recorder;
  final AsrEngine? engine;
  final AsrEngineFactory _engineFactory;
  final OnTranscriptionUpdate? onTranscriptionUpdate;

  final StreamController<VoiceInputUiState> _stateController =
      StreamController<VoiceInputUiState>.broadcast();

  VoiceInputUiState _state = const VoiceInputUiState();
  VoiceInputUiState get state => _state;
  Stream<VoiceInputUiState> get uiState => _stateController.stream;

  StreamSubscription<Float32List>? _audioSub;
  StreamSubscription<double>? _amplitudeSub;
  StreamSubscription<Object>? _errorSub;
  StreamSubscription<AsrTranscriptionChunk>? _transcriptionSub;
  StreamSubscription<Map<String, ModelRegistryEntry>>? _registrySub;
  Timer? _durationTimer;
  Timer? _debugTickTimer;
  DateTime? _recordingStartTime;

  /// The engine serving the current session. Created in [startRecording]
  /// and reused by [stopRecording]/[cancelRecording] so the audio accumulated
  /// via [AsrEngine.acceptAudio] reaches the same instance that decodes in
  /// [AsrEngine.finish]. Recreating the engine at finish time handed the
  /// recorder a fresh, empty engine and silently lost every sample.
  AsrEngine? _activeEngine;

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
      // Prepare engine. The instance is kept in _activeEngine so finish()
      // later decodes the very audio accumulated here.
      final modelDir = manager.getModelDir(activeModel.id);
      final activeEngine = engine ?? _createEngineForModel(activeModel);
      _activeEngine = activeEngine;
      await activeEngine.initialize(activeModel, modelDir);

      await _transcriptionSub?.cancel();
      _transcriptionSub = activeEngine.transcriptionStream.listen((chunk) {
        _emit(_state.copyWith(liveTranscription: chunk.text));
        onTranscriptionUpdate?.call(chunk.text, chunk.isFinal);
      });

      // A mid-session capture failure (event-channel error, or the native
      // input_silent watchdog after ~2s of zeros) must end the recording
      // visibly — never a phantom dock.
      final recorder = _recorder;
      if (recorder is PlatformAudioRecorder) {
        await _errorSub?.cancel();
        _errorSub = recorder.errors.listen((Object error) {
          _failInput(error);
        });
      }

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

      // Debug strip: poll native capture stats so the data flow is
      // visible on-screen (no adb/logcat needed).
      _debugTickTimer?.cancel();
      _debugTickTimer = null;
      if (kDebugMode && recorder is PlatformAudioRecorder) {
        _debugTickTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
          unawaited(recorder.debugStats().then((stats) {
            _emit(_state.copyWith(debugStats: stats));
          }));
        });
      }

      _emit(_state.copyWith(phase: VoiceInputPhase.recording));
    } catch (e) {
      await cancelRecording();
      // Engines reject unsupported models loudly (e.g. the streaming
      // Zipformer in the offline-only scope); map that to a stable,
      // localizable code instead of leaking the raw exception message.
      final message = e is UnsupportedError
          ? 'MODEL_UNSUPPORTED'
          : e.toString();
      _emit(_state.copyWith(
        phase: VoiceInputPhase.error,
        errorMessage: message,
      ));
    }
  }

  /// Completes the recording, finalizes speech-to-text, and returns final text.
  Future<String> stopRecording() async {
    if (!_state.isRecording) return '';

    _emit(_state.copyWith(phase: VoiceInputPhase.finalizing));

    _durationTimer?.cancel();
    _durationTimer = null;
    _debugTickTimer?.cancel();
    _debugTickTimer = null;
    await _audioSub?.cancel();
    _audioSub = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    await _recorder.stop();

    String finalResult = '';
    try {
      final activeEngine = _activeEngine;
      if (activeEngine == null) {
        // Session never initialized an engine (e.g. cancelled mid-start);
        // nothing to transcribe.
        return '';
      }
      finalResult = await activeEngine.finish();
      onTranscriptionUpdate?.call(finalResult, true);
    } catch (e) {
      _emit(_state.copyWith(
        phase: VoiceInputPhase.error,
        errorMessage: e.toString(),
      ));
    } finally {
      unawaited(_activeEngine?.dispose());
      _activeEngine = null;
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
    _debugTickTimer?.cancel();
    _debugTickTimer = null;
    await _audioSub?.cancel();
    _audioSub = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    await _transcriptionSub?.cancel();
    _transcriptionSub = null;
    await _errorSub?.cancel();
    _errorSub = null;
    await _recorder.stop();

    if (engine case final injected?) {
      injected.reset();
    } else {
      unawaited(_activeEngine?.dispose());
      _activeEngine = null;
    }

    _emit(_state.copyWith(
      phase: VoiceInputPhase.idle,
      duration: Duration.zero,
      amplitude: 0.0,
      liveTranscription: '',
    ));
  }

  /// Mid-recording capture failure: end the session with a real error
  /// state instead of leaving a phantom dock on screen.
  Future<void> _failInput(Object error) async {
    await cancelRecording();
    _emit(_state.copyWith(
      phase: VoiceInputPhase.error,
      errorMessage: error is PlatformException && error.code == 'input_silent'
          ? 'RECORD_SILENT_INPUT'
          : 'RECORD_INPUT_FAILED',
    ));
  }

  void dismissError() {
    _emit(_state.copyWith(
      phase: VoiceInputPhase.idle,
      clearError: true,
    ));
  }

  AsrEngine _createEngineForModel(AsrModelInfo? model) {
    return _engineFactory(model);
  }

  static AsrEngine _defaultEngineFactory(AsrModelInfo? model) {
    if (model == null) return MockAsrEngine();
    // SherpaOfflineAsrEngine throws a clear UnsupportedError for models
    // outside the offline-only scope (e.g. the streaming Zipformer), which
    // startRecording's handler surfaces instead of the old stub runner
    // silently returning empty text.
    return SherpaOfflineAsrEngine();
  }

  void dispose() {
    _durationTimer?.cancel();
    _debugTickTimer?.cancel();
    unawaited(_audioSub?.cancel());
    unawaited(_amplitudeSub?.cancel());
    unawaited(_errorSub?.cancel());
    unawaited(_transcriptionSub?.cancel());
    unawaited(_registrySub?.cancel());
    unawaited(_recorder.dispose());
    // Self-created engines are owned by the controller; injected engines
    // belong to the caller (e.g. a test). Only dispose our own.
    if (engine == null) {
      unawaited(_activeEngine?.dispose());
    }
    _activeEngine = null;
    unawaited(_stateController.close());
  }
}