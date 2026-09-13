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
    AsrRuntimeManager? runtimeManager,
    AudioInputSource? audioRecorder,
    this.engine,
    this.onTranscriptionUpdate,
    AsrEngineFactory? engineFactory,
    this._cloudSettings,
    OnlineAsrEngineFactory? cloudEngineFactory,
  }) : _recorder = audioRecorder ?? PlatformAudioRecorder(),
       _runtimeManager = runtimeManager,
       _engineFactory =
           engineFactory ??
           ((AsrModelInfo? model) =>
               _defaultEngineFactory(model, runtimeManager)),
       _cloudEngineFactory = cloudEngineFactory ?? _defaultCloudEngineFactory {
    _init();
  }

  final AsrModelManager manager;

  /// Owns the downloadable on-device runtime; null on a surface that maps the
  /// sherpa libraries itself, in which case the runtime gate stays open.
  final AsrRuntimeManager? _runtimeManager;
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
  StreamSubscription<AsrRuntimeState>? _runtimeSub;
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

  /// Session generation: bumped by every start and every ending. Each await
  /// boundary in [startRecording] re-reads it before it touches state, so the
  /// tail of a session the reader already ended — a permission prompt, a model
  /// load, the native recorder's own `start` — can never publish `recording`
  /// over the ending that followed it. Without this a cancel or a release
  /// landing while the engine was still preparing read as a dead control: the
  /// in-flight start put the capture back on screen a moment later.
  int _epoch = 0;

  /// The finish in flight. One session finishes once, however many times the
  /// ending arrives (a release, a repeated callback): a second
  /// [AsrEngine.finish] over the same audio decodes nothing and reports a
  /// duplicate final transcript over the draft.
  Future<String>? _finishInFlight;

  /// Whether [epoch]'s session was ended or replaced while it was awaiting.
  bool _stale(int epoch) => epoch != _epoch;

  /// Releases an engine this controller owns. An injected engine belongs to
  /// its caller, which gets it back reset rather than disposed.
  void _release(AsrEngine target) {
    if (engine == null) {
      unawaited(target.dispose());
    } else {
      target.reset();
    }
  }

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
    if (_runtimeManager case final AsrRuntimeManager runtime) {
      _runtimeSub = runtime.states.listen((_) => _refreshModelStatus());
      unawaited(runtime.refresh());
    }
  }

  void _refreshModelStatus() {
    final active = manager.getActiveModel();
    final hasInstalled = manager.installedCount > 0;
    final OnlineAsrSettings? cloud = _cloudSettings?.settings;
    _emit(
      _state.copyWith(
        activeModel: active,
        hasInstalledModels: hasInstalled,
        runtimeInstalled:
            _runtimeManager?.state.isReady ?? _state.runtimeInstalled,
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
    // A capture already in flight owns the session; a session that ended in an
    // error does not. Refusing the press on every non-idle phase left the
    // control dead after the first failure, with nothing on screen to clear it.
    if (_state.isSessionActive) return;

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
    if (mode == VoiceInputMode.offline && !_state.runtimeInstalled) {
      // The engine itself is an install (`AsrRuntimeManager`): refuse before
      // opening the microphone so the reader gets the setup dialog instead of
      // a capture that dies at initialize.
      _emit(
        _state.copyWith(
          phase: VoiceInputPhase.error,
          errorMessage: 'RUNTIME_NOT_INSTALLED',
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

    // This session's generation, claimed before the first await: everything
    // below that the reader cancels or releases past is void, and the checks
    // after each await are what stop this start from publishing over it.
    final int epoch = ++_epoch;

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
      if (_stale(epoch)) return;
      if (!hasPerm) {
        final granted = await recorder.requestPermission();
        if (_stale(epoch)) return;
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

    AsrEngine? constructing;
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
      // The engine is published only once its native initialize has returned:
      // an ending that lands during the load therefore has nothing to dispose
      // underneath it, and an abandoned engine is released by the start that
      // created it.
      constructing = activeEngine;
      await activeEngine.initialize(modelForEngine, modelDir);
      if (_stale(epoch)) {
        _release(activeEngine);
        return;
      }
      _activeEngine = activeEngine;
      constructing = null;

      await _transcriptionSub?.cancel();
      if (_stale(epoch)) return;
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
        if (_stale(epoch)) return;
        _errorSub = recorder.errors.listen((Object error) {
          unawaited(_failInput(error));
        });
      }

      // Subscribe to the audio/amplitude streams before capture starts:
      // both are broadcast (non-buffering), so events emitted between
      // start() and subscription would otherwise be dropped, losing the
      // first ~100ms of input.
      await _audioSub?.cancel();
      if (_stale(epoch)) return;
      _audioSub = _recorder.audioStream.listen((samples) {
        _pendingShape = _subPeakShape(samples);
        activeEngine.acceptAudio(samples);
      });

      await _amplitudeSub?.cancel();
      if (_stale(epoch)) return;
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
        if (_stale(epoch)) return;
        await _teardown();
        if (_stale(epoch)) return;
        _emit(
          _state.copyWith(
            phase: VoiceInputPhase.error,
            errorMessage: 'RECORD_START_FAILED',
          ),
        );
        return;
      }
      if (_stale(epoch)) {
        // The ending stopped a recorder that was not running yet; the start
        // that just returned is this session's to undo, or the microphone
        // stays hot under a session nobody owns.
        await _recorder.stop();
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
      // An engine that never reached the session is this start's to release;
      // a published one belongs to [_teardown].
      if (constructing case final abandoned?) _release(abandoned);
      // A session the reader already ended reports no failure: the ending,
      // not the load it interrupted, is what they asked for.
      if (_stale(epoch)) return;
      await _teardown();
      if (_stale(epoch)) return;
      // Engines reject unsupported models and unconfigured/failed online
      // sessions loudly; map each to a stable, localizable code instead of
      // leaking the raw exception message.
      final String message = switch (e) {
        AsrRuntimeMissingException() => 'RUNTIME_NOT_INSTALLED',
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
  ///
  /// Idempotent for the life of one session: the first call owns the finish and
  /// every later one joins it, so a release plus a repeated callback run one
  /// [AsrEngine.finish] rather than two over the same audio.
  Future<String> stopRecording() {
    final Future<String>? inFlight = _finishInFlight;
    if (inFlight != null) return inFlight;
    if (!_state.isRecording) return Future<String>.value('');

    final Future<String> finish = _finishSession();
    _finishInFlight = finish;
    return finish.whenComplete(() {
      if (identical(_finishInFlight, finish)) _finishInFlight = null;
    });
  }

  Future<String> _finishSession() async {
    // Claim the session before anything else: a start still in flight may not
    // publish `recording` over a capture the reader has already ended.
    final int epoch = ++_epoch;

    if (_state.phase != VoiceInputPhase.recording) {
      // The release landed while the engine still held the session — the
      // model was loading, or the tail is already decoding. There is no
      // complete capture to send, so this ends as a cancel instead of a
      // finalize that would emit an empty transcript over the draft.
      await _teardown();
      if (_stale(epoch)) return '';
      _emit(_resting(VoiceInputPhase.idle));
      return '';
    }

    _emit(_state.copyWith(phase: VoiceInputPhase.finalizing));
    _durationTimer?.cancel();
    _durationTimer = null;
    _debugTickTimer?.cancel();
    _debugTickTimer = null;
    await _audioSub?.cancel();
    _audioSub = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;

    String finalResult = '';
    final AsrEngine? activeEngine = _activeEngine;
    try {
      await _recorder.stop();
      if (activeEngine == null) {
        // Session never initialized an engine (e.g. cancelled mid-start);
        // nothing to transcribe.
        return '';
      }
      finalResult = await activeEngine.finish();
      if (_stale(epoch)) return '';
      onTranscriptionUpdate?.call(finalResult, true);
    } catch (e) {
      if (_stale(epoch)) return '';
      // Online session failures surface here (the service's final verdict
      // arrives at finish); map to a stable, localizable code.
      final String message = e is OnlineAsrException
          ? 'ONLINE_ASR_FAILED'
          : e.toString();
      _emit(
        _state.copyWith(phase: VoiceInputPhase.error, errorMessage: message),
      );
    } finally {
      // Only the engine this finish still owns is released here; a teardown
      // that landed mid-finish already released its own.
      if (activeEngine != null && identical(_activeEngine, activeEngine)) {
        _activeEngine = null;
        _release(activeEngine);
      }
      if (!_stale(epoch) && _state.phase != VoiceInputPhase.error) {
        _emit(_resting(VoiceInputPhase.idle));
      }
    }
    return finalResult;
  }

  /// Cancels recording and discards audio buffers.
  ///
  /// Cancelling a session the engine is still preparing is a real cancel: the
  /// bumped generation voids the start still in flight, which is what stops a
  /// capture from appearing after the reader already dismissed it.
  Future<void> cancelRecording() async {
    _epoch++;
    await _teardown();
    _emit(_resting(VoiceInputPhase.idle));
  }

  /// The state every ending rests in: no elapsed clock, no level, and no
  /// half-transcribed text left over from the session that just closed.
  VoiceInputUiState _resting(VoiceInputPhase phase) => _state.copyWith(
    phase: phase,
    duration: Duration.zero,
    amplitude: 0.0,
    envelope: const <double>[],
    liveTranscription: '',
  );

  /// Ends the running capture without touching [state]: the caller states the
  /// outcome, which is what separates "the reader cancelled" from "the capture
  /// failed". Idempotent, so an ending that arrives twice costs one teardown.
  Future<void> _teardown() async {
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

    final AsrEngine? active = _activeEngine;
    _activeEngine = null;
    if (active != null) _release(active);
  }

  /// Mid-recording capture failure: end the session with a real error
  /// state instead of leaving a phantom dock on screen.
  Future<void> _failInput(Object error) async {
    _epoch++;
    await _teardown();
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

  static AsrEngine _defaultEngineFactory(
    AsrModelInfo? model,
    AsrRuntimeManager? runtimeManager,
  ) {
    if (model == null) return MockAsrEngine();
    // SherpaOfflineAsrEngine supports streaming Paraformer and transducer
    // Zipformer models as well as offline SenseVoice, Fun-ASR-Nano CTC, and
    // (discontinued, installed-only) Whisper models, and throws
    // UnsupportedError for unknown models.
    return SherpaOfflineAsrEngine(runtimeManager: runtimeManager);
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
    unawaited(_runtimeSub?.cancel());
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
