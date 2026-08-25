import 'dart:io';
import 'dart:typed_data';

import 'package:app/ui/chat/voice_input/voice_input_controller.dart';
import 'package:app/ui/chat/voice_input/voice_input_ui_state.dart';
import 'package:asr/asr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      manager = AsrModelManager(
        baseModelsDir: tempDir,
        registry: registry,
      );
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

    test('drives recording session, streams audio to engine, and emits final text', () async {
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
    });

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
  });
}