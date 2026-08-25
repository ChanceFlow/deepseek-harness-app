import 'dart:async';
import 'dart:io';

import 'package:asr/asr.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class MockHttpClient extends http.BaseClient {
  MockHttpClient(this._handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _handler(request);
}

void main() {
  group('AsrModelManager', () {
    late Directory tempDir;
    late File registryFile;
    late ModelsRegistry registry;
    late AsrModelManager manager;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('asr_mgr_test_');
      registryFile = File('${tempDir.path}/models_registry.json');
      registry = ModelsRegistry(registryFile: registryFile);
      await registry.load();
    });

    tearDown(() async {
      await registry.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('blocks cellular download when not allowed', () async {
      manager = AsrModelManager(
        baseModelsDir: tempDir,
        registry: registry,
        allowCellular: false,
      );

      await expectLater(
        manager.startDownload('sensevoice-small', isCellular: true),
        throwsA(isA<DownloadFailedException>()),
      );
    });

    test('blocks download when disk space is insufficient', () async {
      manager = AsrModelManager(
        baseModelsDir: tempDir,
        registry: registry,
        diskSpaceChecker: (_) async => 1024, // only 1KB available
      );

      await expectLater(
        manager.startDownload('sensevoice-small'),
        throwsA(isA<DownloadFailedException>()),
      );

      final ModelRegistryEntry entry = manager.getStatus('sensevoice-small');
      expect(entry.status, equals(AsrModelStatus.failed));
      expect(entry.lastError, contains('Insufficient storage space'));
    });

    test('enforces single concurrency across downloads', () async {
      final Completer<void> streamStarted = Completer<void>();
      final StreamController<List<int>> streamController = StreamController<List<int>>();

      final MockHttpClient client = MockHttpClient((http.BaseRequest request) async {
        if (!streamStarted.isCompleted) {
          streamStarted.complete();
        }
        return http.StreamedResponse(streamController.stream, 200, contentLength: 154140672);
      });

      manager = AsrModelManager(
        baseModelsDir: tempDir,
        registry: registry,
        downloader: AsrDownloader(httpClient: client),
      );

      // Start first download
      final Future<void> firstDownload = manager.startDownload('sensevoice-small');
      await streamStarted.future;

      // Try starting second download while first is in-flight
      await expectLater(
        manager.startDownload('zipformer-bilingual'),
        throwsA(isA<StateError>()),
      );

      // Cleanup
      await manager.cancelDownload('sensevoice-small');
      try {
        await streamController.close();
      } catch (_) {}
      try {
        await firstDownload;
      } catch (_) {}
    });

    test('deletes model folder and removes registry entry', () async {
      final Directory modelDir = Directory('${tempDir.path}/sensevoice-small');
      await modelDir.create(recursive: true);
      final File dummyFile = File('${modelDir.path}/model.int8.onnx');
      await dummyFile.writeAsString('test-model-content');

      await registry.updateEntry(
        ModelRegistryEntry(
          modelId: 'sensevoice-small',
          source: ModelSource.modelScope,
          localDir: modelDir.path,
          status: AsrModelStatus.downloaded,
          totalBytes: 18,
          downloadedBytes: 18,
        ),
      );

      manager = AsrModelManager(
        baseModelsDir: tempDir,
        registry: registry,
      );

      expect(manager.installedCount, equals(1));
      expect(await dummyFile.exists(), isTrue);

      await manager.deleteModel('sensevoice-small');

      expect(manager.installedCount, equals(0));
      expect(await modelDir.exists(), isFalse);
    });
  });
}
