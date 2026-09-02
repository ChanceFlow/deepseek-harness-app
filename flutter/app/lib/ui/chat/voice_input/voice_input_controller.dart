/// UDF Controller managing voice recording, VAD/silence timers, and speech engine dispatch.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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

/// Creates the online-session engine for the selected provider. Exposed as
/// a seam so tests can inject a scripted cloud engine.
typedef OnlineAsrEngineFactory = AsrEngine Function(OnlineAsrSettings settings);

/// Controller driving voice input — on-device or online — and streaming state.
class VoiceInputController {
  VoiceInputController({
    required this.manager,
    AudioInputSource? audioRecorder,
    this.engine,
    this.onTranscriptionUpdate,
    AsrEngineFactory? engineFactory,
    this._cloudSettings,
    OnlineAsrEngineFactory? cloudEngineFactory,
  }) : _recorder = audioRecorder ?? PlatformAudioRecorder(),
       _engineFactory = engineFactory ?? _defaultEngineFactory,
       _cloudEngineFactory = cloudEngineFactory ?? _defaultCloudEngineFactory {
    _init();
  }

  final AsrModelManager manager;
  final AudioInputSource _recorder;
  final AsrEngine? engine;
  final AsrEngineFactory _engineFactory;
  final OnTranscriptionUpdate? onTranscriptionUpdate;

  /// Voice-input mode/credentials store; null keeps the controller offline
  /// (the shape tests and older call sites rely on).
  final OnlineAsrSettingsStore? _cloudSettings;
  final OnlineAsrEngineFactory _cloudEngineFactory;

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
  StreamSubscription<OnlineAsrSettings>? _cloudSettingsSub;
  Timer? _durationTimer;
  Timer? _debugTickTimer;
  DateTime? _recordingStartTime;

  /// The engine serving the current session. Created in [startRecording]
  /// and reused by [stopRecording]/[cancelRecording] so the audio accumulated
  /// via [AsrEngine.acceptAudio] reaches the same instance that decodes in
  /// [AsrEngine.finish]. Recreating the engine at finish time handed the
  /// recorder a fresh, empty engine and silently lost every sample.
  AsrEngine? _activeEngine;

  /// The sub-peak shape of the chunk currently in flight, waiting for the
  /// level event the recorder emits for that same chunk right after its
  /// samples. Pairing them here keeps the meter's bands in the same
  /// normalized space as [VoiceInputUiState.amplitude] without a second
  /// peak tracker or a duplicate of the recorder's adaptive release.
  Float32List? _pendingShape;

  void _init() {
    _refreshModelStatus();
    _registrySub = manager.updates.listen((_) => _refreshModelStatus());
    _cloudSettingsSub = _cloudSettings?.updates.listen((_) {
      _refreshModelStatus();
    });
  }

  void _refreshModelStatus() {
    final active = manager.getActiveModel();
    final hasInstalled = manager.installedCount > 0;
    final OnlineAsrSettings? cloud = _cloudSettings?.settings;
    _emit(
      _state.copyWith(
        activeModel: active,
        hasInstalledModels: hasInstalled,
        inputMode: cloud?.mode ?? VoiceInputMode.offline,
        onlineReady: cloud?.isOnlineReady ?? false,
      ),
    );
  }

  void _emit(VoiceInputUiState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  /// Starts voice recording session using the configured input mode: the
  /// active on-device model, or the selected online provider's credentials.
  Future<void> startRecording() async {
    if (_state.isBusy) return;

    final VoiceInputMode mode =
        _cloudSettings?.settings.mode ?? VoiceInputMode.offline;
    final OnlineAsrSettings? cloudSettings = _cloudSettings?.settings;
    final AsrModelInfo? activeModel = manager.getActiveModel();

    if (mode == VoiceInputMode.offline && activeModel == null) {
      _emit(
        _state.copyWith(
          phase: VoiceInputPhase.error,
          errorMessage: 'NO_MODEL_INSTALLED',
        ),
      );
      return;
    }
    if (mode == VoiceInputMode.online &&
        (cloudSettings == null || !cloudSettings.isOnlineReady)) {
      _emit(
        _state.copyWith(
          phase: VoiceInputPhase.error,
          errorMessage: 'ONLINE_NOT_CONFIGURED',
        ),
      );
      return;
    }

    _emit(
      _state.copyWith(
        phase: VoiceInputPhase.initializing,
        duration: Duration.zero,
        amplitude: 0.0,
        envelope: const <double>[],
        liveTranscription: '',
        clearError: true,
        activeModel: activeModel,
      ),
    );

    // Request permissions if needed
    final recorder = _recorder;
    if (recorder is PlatformAudioRecorder) {
      final hasPerm = await recorder.checkPermission();
      if (!hasPerm) {
        final granted = await recorder.requestPermission();
        if (!granted) {
          _emit(
            _state.copyWith(
              phase: VoiceInputPhase.error,
              errorMessage: 'PERMISSION_DENIED',
            ),
          );
          return;
        }
      }
    }

    try {
      // Prepare engine. The instance is kept in _activeEngine so finish()
      // later receives the very audio accumulated here. Online sessions
      // pass null model/dir — the engine carries its own credentials.
      final AsrEngine activeEngine;
      final AsrModelInfo? modelForEngine;
      final Directory? modelDir;
      if (mode == VoiceInputMode.online) {
        activeEngine = engine ?? _cloudEngineFactory(cloudSettings!);
        modelForEngine = null;
        modelDir = null;
      } else {
        modelForEngine = activeModel!;
        modelDir = manager.getModelDir(modelForEngine.id);
        activeEngine = engine ?? _createEngineForModel(modelForEngine);
      }
      _activeEngine = activeEngine;
      await activeEngine.initialize(modelForEngine, modelDir);

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
          unawaited(_failInput(error));
        });
      }

      // Subscribe to the audio/amplitude streams before capture starts:
      // both are broadcast (non-buffering), so events emitted between
      // start() and subscription would otherwise be dropped, losing the
      // first ~100ms of input.
      await _audioSub?.cancel();
      _audioSub = _recorder.audioStream.listen((samples) {
        _pendingShape = _subPeakShape(samples);
        activeEngine.acceptAudio(samples);
      });

      await _amplitudeSub?.cancel();
      _amplitudeSub = _recorder.amplitudeStream.listen((amp) {
        // The recorder emits a chunk's samples and then its level from the
        // same frame, so the shape in flight belongs to this level.
        final shape = _pendingShape;
        _pendingShape = null;
        _emit(
          _state.copyWith(
            amplitude: amp,
            envelope: shape == null
                ? const <double>[]
                : _scaleToLevel(shape, amp),
          ),
        );
      });

      try {
        await _recorder.start();
      } on PlatformException {
        // Native AudioRecord failed to start (e.g. device/emulator input
        // unavailable). Surface a stable, localizable error instead of a
        // phantom recording dock whose waveform never moves.
        await cancelRecording();
        _emit(
          _state.copyWith(
            phase: VoiceInputPhase.error,
            errorMessage: 'RECORD_START_FAILED',
          ),
        );
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
        _debugTickTimer = Timer.periodic(const Duration(milliseconds: 500), (
          _,
        ) {
          unawaited(
            recorder.debugStats().then((stats) {
              _emit(_state.copyWith(debugStats: stats));
            }),
          );
        });
      }

      _emit(_state.copyWith(phase: VoiceInputPhase.recording));
    } catch (e) {
      await cancelRecording();
      // Engines reject unsupported models and unconfigured/failed online
      // sessions loudly; map each to a stable, localizable code instead of
      // leaking the raw exception message.
      final String message = switch (e) {
        UnsupportedError() => 'MODEL_UNSUPPORTED',
        OnlineAsrException() => 'ONLINE_ASR_FAILED',
        _ when mode == VoiceInputMode.online => 'ONLINE_CONNECT_FAILED',
        _ => e.toString(),
      };
      _emit(
        _state.copyWith(phase: VoiceInputPhase.error, errorMessage: message),
      );
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
      // Online session failures surface here (the service's final verdict
      // arrives at finish); map to a stable, localizable code.
      final String message = e is OnlineAsrException
          ? 'ONLINE_ASR_FAILED'
          : e.toString();
      _emit(
        _state.copyWith(phase: VoiceInputPhase.error, errorMessage: message),
      );
    } finally {
      unawaited(_activeEngine?.dispose());
      _activeEngine = null;
      _emit(
        _state.copyWith(
          phase: VoiceInputPhase.idle,
          duration: Duration.zero,
          amplitude: 0.0,
        ),
      );
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

    _emit(
      _state.copyWith(
        phase: VoiceInputPhase.idle,
        duration: Duration.zero,
        amplitude: 0.0,
        liveTranscription: '',
      ),
    );
  }

  /// Mid-recording capture failure: end the session with a real error
  /// state instead of leaving a phantom dock on screen.
  Future<void> _failInput(Object error) async {
    await cancelRecording();
    _emit(
      _state.copyWith(
        phase: VoiceInputPhase.error,
        errorMessage: error is PlatformException && error.code == 'input_silent'
            ? 'RECORD_SILENT_INPUT'
            : 'RECORD_INPUT_FAILED',
      ),
    );
  }

  void dismissError() {
    _emit(_state.copyWith(phase: VoiceInputPhase.idle, clearError: true));
  }

  AsrEngine _createEngineForModel(AsrModelInfo? model) {
    return _engineFactory(model);
  }

  /// Splits one PCM chunk into [kVoiceEnvelopeBands] equal time windows and
  /// returns each window's peak relative to the chunk's own peak (0..1). This
  /// is what turns a single 10Hz level into a 40Hz meter: the dynamics inside
  /// a chunk — the attack of a consonant, the drop between syllables — reach
  /// the screen instead of being averaged into one bar.
  static Float32List _subPeakShape(Float32List samples) {
    final shape = Float32List(kVoiceEnvelopeBands);
    if (samples.isEmpty) return shape;
    final window = math.max(1, samples.length ~/ kVoiceEnvelopeBands);
    var chunkPeak = 0.0;
    for (var i = 0; i < samples.length; i++) {
      final v = samples[i].abs();
      if (v > chunkPeak) chunkPeak = v;
      final band = math.min(kVoiceEnvelopeBands - 1, i ~/ window);
      if (v > shape[band]) shape[band] = v;
    }
    if (chunkPeak == 0.0) return shape;
    for (var b = 0; b < kVoiceEnvelopeBands; b++) {
      shape[b] = shape[b] / chunkPeak;
    }
    return shape;
  }

  /// Puts a chunk's relative shape into the same 0..1 space as the chunk
  /// level: `subPeak / chunkPeak * (chunkPeak / adaptivePeak)`.
  static List<double> _scaleToLevel(Float32List shape, double level) =>
      <double>[for (final ratio in shape) ratio * level];

  static AsrEngine _defaultEngineFactory(AsrModelInfo? model) {
    if (model == null) return MockAsrEngine();
    // SherpaOfflineAsrEngine supports streaming Paraformer and transducer
    // Zipformer models as well as offline SenseVoice, Fun-ASR-Nano CTC, and
    // (discontinued, installed-only) Whisper models, and throws
    // UnsupportedError for unknown models.
    return SherpaOfflineAsrEngine();
  }

  /// Builds the online-session engine for the selected provider. Both
  /// engines are per-recording session objects; the recording dock's
  /// lifecycle disposes them with the session.
  static AsrEngine _defaultCloudEngineFactory(OnlineAsrSettings settings) =>
      switch (settings.provider) {
        OnlineAsrProvider.volcengineDoubao => VolcengineDoubaoAsrEngine(
          config: settings.volcengine,
        ),
        OnlineAsrProvider.tencentHunyuan => TencentHunyuanAsrEngine(
          config: settings.tencent,
        ),
      };

  void dispose() {
    _durationTimer?.cancel();
    _debugTickTimer?.cancel();
    unawaited(_audioSub?.cancel());
    unawaited(_amplitudeSub?.cancel());
    unawaited(_errorSub?.cancel());
    unawaited(_transcriptionSub?.cancel());
    unawaited(_registrySub?.cancel());
    unawaited(_cloudSettingsSub?.cancel());
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
