import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/platform/audio_recorder.dart';
import 'package:app/ui/chat/voice_input/voice_input_controller.dart';
import 'package:app/ui/chat/voice_input/voice_input_ui_state.dart';
import 'package:asr/asr.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoiceInputController', () {
    late Directory tempDir;
    late File registryFile;
    late ModelsRegistry registry;
    late AsrModelManager manager;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('voice_ctrl_test_');
      registryFile = File('${tempDir.path}/models_registry.json');
      registry = ModelsRegistry(registryFile: registryFile);
      await registry.load();
      manager = AsrModelManager(baseModelsDir: tempDir, registry: registry);
    });

    tearDown(() async {
      await registry.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('transitions to error when no models are installed', () async {
      final controller = VoiceInputController(
        manager: manager,
        audioRecorder: MockAudioInputSource(),
        engine: MockAsrEngine(),
      );

      expect(controller.state.hasInstalledModels, isFalse);
      expect(controller.state.activeModel, isNull);

      await controller.startRecording();
      expect(controller.state.phase, equals(VoiceInputPhase.error));
      expect(controller.state.errorMessage, equals('NO_MODEL_INSTALLED'));

      controller.dismissError();
      expect(controller.state.phase, equals(VoiceInputPhase.idle));
      expect(controller.state.errorMessage, isNull);

      controller.dispose();
    });

    test(
      'drives recording session, streams audio to engine, and emits final text',
      () async {
        // Mark model as downloaded
        final modelDir = Directory('${tempDir.path}/sensevoice-small');
        await modelDir.create(recursive: true);
        await registry.updateEntry(
          ModelRegistryEntry(
            modelId: 'sensevoice-small',
            source: ModelSource.hfMirror,
            localDir: modelDir.path,
            status: AsrModelStatus.downloaded,
          ),
        );

        final mockEngine = MockAsrEngine(
          simulatedChunks: <String>['今天', '天气', '很好'],
          finalTranscription: '今天天气很好。',
        );
        final mockRecorder = MockAudioInputSource();

        final List<String> transcriptionUpdates = <String>[];
        final controller = VoiceInputController(
          manager: manager,
          audioRecorder: mockRecorder,
          engine: mockEngine,
          onTranscriptionUpdate: (text, isFinal) {
            transcriptionUpdates.add(text);
          },
        );

        expect(controller.state.hasInstalledModels, isTrue);
        expect(controller.state.activeModel?.id, equals('sensevoice-small'));

        await controller.startRecording();
        expect(controller.state.phase, equals(VoiceInputPhase.recording));
        expect(controller.state.isRecording, isTrue);

        // Supply some audio
        mockEngine.acceptAudio(Float32List(1600));
        mockEngine.acceptAudio(Float32List(1600));

        expect(transcriptionUpdates.isNotEmpty, isTrue);

        final finalText = await controller.stopRecording();
        expect(finalText, equals('今天天气很好。'));
        expect(controller.state.phase, equals(VoiceInputPhase.idle));
        expect(controller.state.isRecording, isFalse);

        controller.dispose();
      },
    );

    test(
      'pairs each capture chunk with its sub-peak envelope for the meter',
      () async {
        final modelDir = Directory('${tempDir.path}/sensevoice-small');
        await modelDir.create(recursive: true);
        await registry.updateEntry(
          ModelRegistryEntry(
            modelId: 'sensevoice-small',
            source: ModelSource.hfMirror,
            localDir: modelDir.path,
            status: AsrModelStatus.downloaded,
          ),
        );

        final controller = VoiceInputController(
          manager: manager,
          audioRecorder: _ShapedAudioSource(),
          engine: MockAsrEngine(),
        );

        await controller.startRecording();
        await pumpEventQueue();

        final envelope = controller.state.envelope;
        expect(envelope, hasLength(kVoiceEnvelopeBands));
        // The chunk's own level rides on the band that holds its peak, and the
        // quiet windows keep their real proportion of it: the meter draws the
        // shape inside the chunk, not one flat bar.
        expect(controller.state.amplitude, closeTo(0.5, 0.001));
        expect(envelope.first, closeTo(0.5, 0.001));
        for (final quiet in envelope.skip(1)) {
          expect(quiet, closeTo(0.125, 0.001));
        }

        controller.dispose();
      },
    );

    test('cancelRecording discards in-flight buffers cleanly', () async {
      final modelDir = Directory('${tempDir.path}/sensevoice-small');
      await modelDir.create(recursive: true);
      await registry.updateEntry(
        ModelRegistryEntry(
          modelId: 'sensevoice-small',
          source: ModelSource.hfMirror,
          localDir: modelDir.path,
          status: AsrModelStatus.downloaded,
        ),
      );

      final controller = VoiceInputController(
        manager: manager,
        audioRecorder: MockAudioInputSource(),
        engine: MockAsrEngine(),
      );

      await controller.startRecording();
      expect(controller.state.isRecording, isTrue);

      await controller.cancelRecording();
      expect(controller.state.isRecording, isFalse);
      expect(controller.state.phase, equals(VoiceInputPhase.idle));

      controller.dispose();
    });

    test(
      'surfaces a native startRecording failure instead of a phantom recording',
      () async {
        final modelDir = Directory('${tempDir.path}/sensevoice-small');
        await modelDir.create(recursive: true);
        await registry.updateEntry(
          ModelRegistryEntry(
            modelId: 'sensevoice-small',
            source: ModelSource.hfMirror,
            localDir: modelDir.path,
            status: AsrModelStatus.downloaded,
          ),
        );

        const MethodChannel methodChannel = MethodChannel(kAudioRecordChannel);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (MethodCall call) async {
              switch (call.method) {
                case 'hasPermission':
                case 'requestPermission':
                  return true;
                case 'startRecording':
                  throw PlatformException(
                    code: 'record_error',
                    message: 'Failed to initialize AudioRecord',
                  );
                default:
                  return null;
              }
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(methodChannel, null);
        });

        final controller = VoiceInputController(
          manager: manager,
          audioRecorder: PlatformAudioRecorder(),
          engine: MockAsrEngine(),
        );

        await controller.startRecording();

        // The controller must NOT present a phantom recording dock when the
        // native recorder failed to start: the user sees no waveform and no
        // audio, with no way to know capture never began.
        expect(controller.state.phase, isNot(VoiceInputPhase.recording));
        expect(controller.state.isRecording, isFalse);
        expect(controller.state.errorMessage, equals('RECORD_START_FAILED'));

        controller.dispose();
      },
    );

    test('ends a phantom recording with RECORD_SILENT_INPUT when the native watchdog reports silence', () async {
      final modelDir = Directory('${tempDir.path}/sensevoice-small');
      await modelDir.create(recursive: true);
      await registry.updateEntry(
        ModelRegistryEntry(
          modelId: 'sensevoice-small',
          source: ModelSource.hfMirror,
          localDir: modelDir.path,
          status: AsrModelStatus.downloaded,
        ),
      );

      const MethodChannel methodChannel = MethodChannel(kAudioRecordChannel);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (MethodCall call) async {
            switch (call.method) {
              case 'hasPermission':
              case 'requestPermission':
              case 'startRecording':
              case 'stopRecording':
                return true;
              default:
                return null;
            }
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, null);
      });

      final controller = VoiceInputController(
        manager: manager,
        audioRecorder: PlatformAudioRecorder(),
        engine: MockAsrEngine(),
      );

      await controller.startRecording();
      expect(controller.state.phase, equals(VoiceInputPhase.recording));

      // A mid-session capture failure must end the recording with a real
      // error. Deliver a native error envelope on the audio stream channel
      // exactly as the platform would (EventChannel → onError → errors
      // stream → controller).
      const codec = StandardMethodCodec();
      unawaited(
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              kAudioStreamChannel,
              codec.encodeErrorEnvelope(
                code: 'input_silent',
                message: 'No audio signal detected from the microphone',
                details: null,
              ),
              (_) {},
            ),
      );

      // Let the error envelope flow through the event channel to the
      // controller's error subscription and settle.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.phase, equals(VoiceInputPhase.error));
      expect(controller.state.errorMessage, equals('RECORD_SILENT_INPUT'));
      expect(controller.state.isRecording, isFalse);

      controller.dispose();
    });

    test('reuses one engine instance across acceptAudio and finish', () async {
      final modelDir = Directory('${tempDir.path}/sensevoice-small');
      await modelDir.create(recursive: true);
      await registry.updateEntry(
        ModelRegistryEntry(
          modelId: 'sensevoice-small',
          source: ModelSource.hfMirror,
          localDir: modelDir.path,
          status: AsrModelStatus.downloaded,
        ),
      );

      final engine = _TrackingEngine();
      var factoryCalls = 0;
      final controller = VoiceInputController(
        manager: manager,
        audioRecorder: MockAudioInputSource(),
        engineFactory: (_) {
          factoryCalls++;
          return engine;
        },
      );

      await controller.startRecording();
      expect(controller.state.phase, equals(VoiceInputPhase.recording));

      // The mock recorder emits 1600-sample frames every 100 ms; wait for
      // a couple of frames to flow from recorder -> engine.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(
        engine.audioFrames,
        greaterThan(0),
        reason: 'recorder audio must reach the session engine',
      );

      final text = await controller.stopRecording();
      expect(text, '识别结果');
      expect(
        factoryCalls,
        1,
        reason:
            'stopRecording must finish on the same engine that '
            'received audio, not a freshly created one',
      );
      expect(engine.finishCalls, 1);
      expect(
        engine.samplesAtFinish,
        greaterThan(0),
        reason: 'finish() must see the accumulated audio',
      );
      expect(controller.state.isRecording, isFalse);

      controller.dispose();
    });

    test('maps an unsupported engine model to MODEL_UNSUPPORTED', () async {
      final modelDir = Directory('${tempDir.path}/sensevoice-small');
      await modelDir.create(recursive: true);
      await registry.updateEntry(
        ModelRegistryEntry(
          modelId: 'sensevoice-small',
          source: ModelSource.hfMirror,
          localDir: modelDir.path,
          status: AsrModelStatus.downloaded,
        ),
      );

      final controller = VoiceInputController(
        manager: manager,
        audioRecorder: MockAudioInputSource(),
        engineFactory: (_) => _UnsupportedModelEngine(),
      );

      await controller.startRecording();

      // The engine rejects the model; the controller must surface the
      // stable localizable code, not the raw exception text.
      expect(controller.state.phase, equals(VoiceInputPhase.error));
      expect(controller.state.errorMessage, equals('MODEL_UNSUPPORTED'));
      expect(controller.state.isRecording, isFalse);

      controller.dispose();
    });

    test(
      'online mode starts through the cloud engine without models',
      () async {
        final store = OnlineAsrSettingsStore(
          File('${tempDir.path}/online_asr_settings.json'),
        );
        await store.load();
        await store.setMode(VoiceInputMode.online);
        await store.setVolcengine(
          const VolcengineDoubaoAsrConfig(apiKey: 'k-online'),
        );

        final cloudEngine = _ScriptedCloudEngine();
        OnlineAsrSettings? captured;
        final controller = VoiceInputController(
          manager: manager,
          audioRecorder: MockAudioInputSource(),
          cloudSettings: store,
          cloudEngineFactory: (settings) {
            captured = settings;
            return cloudEngine;
          },
        );

        // No on-device model is installed, yet online voice input is armed:
        // the state reflects the mode and the provider's readiness.
        expect(controller.state.inputMode, equals(VoiceInputMode.online));
        expect(controller.state.onlineReady, isTrue);
        expect(controller.state.hasInstalledModels, isFalse);

        await controller.startRecording();
        expect(controller.state.phase, equals(VoiceInputPhase.recording));
        expect(captured?.provider, equals(OnlineAsrProvider.volcengineDoubao));
        expect(captured?.volcengine.apiKey, equals('k-online'));
        expect(cloudEngine.initializeCalls, 1);

        final text = await controller.stopRecording();
        expect(text, equals('在线识别结果'));
        expect(cloudEngine.finishCalls, 1);
        expect(controller.state.isRecording, isFalse);

        controller.dispose();
        await store.dispose();
      },
    );

    test('online mode without credentials reports a stable error', () async {
      final store = OnlineAsrSettingsStore(
        File('${tempDir.path}/online_asr_settings.json'),
      );
      await store.load();
      await store.setMode(VoiceInputMode.online);
      // No provider configured.

      var factoryCalled = false;
      final controller = VoiceInputController(
        manager: manager,
        audioRecorder: MockAudioInputSource(),
        cloudSettings: store,
        cloudEngineFactory: (_) {
          factoryCalled = true;
          return _ScriptedCloudEngine();
        },
      );

      expect(controller.state.onlineReady, isFalse);
      await controller.startRecording();
      expect(controller.state.phase, equals(VoiceInputPhase.error));
      expect(controller.state.errorMessage, equals('ONLINE_NOT_CONFIGURED'));
      expect(factoryCalled, isFalse);

      controller.dispose();
      await store.dispose();
    });
  });
}

/// [AsrEngine] standing in for an online-session engine: records how it
/// was initialized and what [finish] returns.
class _ScriptedCloudEngine implements AsrEngine {
  int initializeCalls = 0;
  int finishCalls = 0;
  AsrEngineState _state = AsrEngineState.uninitialized;

  final StreamController<AsrTranscriptionChunk> _chunks =
      StreamController<AsrTranscriptionChunk>.broadcast(sync: true);

  @override
  AsrEngineState get state => _state;

  @override
  Stream<AsrTranscriptionChunk> get transcriptionStream => _chunks.stream;

  @override
  Future<void> initialize(AsrModelInfo? model, Directory? modelDir) async {
    expect(model, isNull, reason: 'online engines carry no on-device model');
    expect(modelDir, isNull);
    initializeCalls++;
    _state = AsrEngineState.ready;
  }

  @override
  void acceptAudio(Float32List samples) {}

  @override
  Future<String> finish() async {
    finishCalls++;
    _state = AsrEngineState.ready;
    return '在线识别结果';
  }

  @override
  void reset() {}

  @override
  Future<void> dispose() async {
    _state = AsrEngineState.disposed;
    await _chunks.close();
  }
}

/// [AsrEngine] that records how much audio it received before [finish],
/// so a test can tell whether the instance that decoded was the same one
/// that accumulated audio.
class _TrackingEngine implements AsrEngine {
  int audioFrames = 0;
  int samplesAtFinish = 0;
  int finishCalls = 0;

  final StreamController<AsrTranscriptionChunk> _chunks =
      StreamController<AsrTranscriptionChunk>.broadcast(sync: true);

  AsrEngineState _state = AsrEngineState.ready;

  @override
  AsrEngineState get state => _state;

  @override
  Stream<AsrTranscriptionChunk> get transcriptionStream => _chunks.stream;

  @override
  Future<void> initialize(AsrModelInfo? model, Directory? modelDir) async {
    _state = AsrEngineState.ready;
  }

  @override
  void acceptAudio(Float32List samples) {
    audioFrames++;
    samplesAtFinish += samples.length;
  }

  @override
  Future<String> finish() async {
    finishCalls++;
    if (!_chunks.isClosed) {
      _chunks.add(const AsrTranscriptionChunk(text: '识别结果', isFinal: true));
    }
    _state = AsrEngineState.ready;
    return '识别结果';
  }

  @override
  void reset() {
    _state = AsrEngineState.ready;
  }

  @override
  Future<void> dispose() async {
    _state = AsrEngineState.disposed;
    await _chunks.close();
  }
}

/// [AsrEngine] whose [initialize] rejects the model, standing in for the
/// real engine's loud refusal of streaming/unsupported models.
class _UnsupportedModelEngine implements AsrEngine {
  final StreamController<AsrTranscriptionChunk> _chunks =
      StreamController<AsrTranscriptionChunk>.broadcast(sync: true);

  final AsrEngineState _state = AsrEngineState.uninitialized;

  @override
  AsrEngineState get state => _state;

  @override
  Stream<AsrTranscriptionChunk> get transcriptionStream => _chunks.stream;

  @override
  Future<void> initialize(AsrModelInfo? model, Directory? modelDir) async {
    if (model == null) {
      throw UnsupportedError('Model is required');
    }
    throw UnsupportedError('Model ${model.id} is not supported');
  }

  @override
  void acceptAudio(Float32List samples) {}

  @override
  Future<String> finish() async => '';

  @override
  void reset() {}

  @override
  Future<void> dispose() async {
    await _chunks.close();
  }
}

/// [AudioInputSource] that emits exactly one chunk of known shape: its first
/// quarter at 0.8 and the rest at 0.2, followed by the level event the real
/// recorder emits for the same frame.
class _ShapedAudioSource implements AudioInputSource {
  final StreamController<Float32List> _audio =
      StreamController<Float32List>.broadcast();
  final StreamController<double> _levels = StreamController<double>.broadcast();

  bool _recording = false;

  @override
  Stream<Float32List> get audioStream => _audio.stream;

  @override
  Stream<double> get amplitudeStream => _levels.stream;

  @override
  bool get isRecording => _recording;

  @override
  Future<void> start({int sampleRate = 16000}) async {
    _recording = true;
    final chunk = Float32List(1600);
    for (var i = 0; i < chunk.length; i++) {
      chunk[i] = i < 400 ? 0.8 : 0.2;
    }
    _audio.add(chunk);
    _levels.add(0.5);
  }

  @override
  Future<void> stop() async => _recording = false;

  @override
  Future<void> dispose() async {
    await _audio.close();
    await _levels.close();
  }
}
