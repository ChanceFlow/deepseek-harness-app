import 'dart:io';

import 'package:asr/asr.dart';
import 'package:test/test.dart';

void main() {
  group('ModelsRegistry', () {
    late Directory tempDir;
    late File registryFile;
    late ModelsRegistry registry;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('asr_reg_test_');
      registryFile = File('${tempDir.path}/models_registry.json');
      registry = ModelsRegistry(registryFile: registryFile);
    });

    tearDown(() async {
      await registry.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('loads empty when registry file does not exist', () async {
      await registry.load();
      expect(registry.entries, isEmpty);
      expect(registry.installedCount, equals(0));
    });

    test('saves and loads model entries cleanly', () async {
      final ModelRegistryEntry entry = ModelRegistryEntry(
        modelId: 'sensevoice-small',
        source: ModelSource.hfMirror,
        localDir: '${tempDir.path}/sensevoice-small',
        status: AsrModelStatus.downloaded,
        totalBytes: 157286400,
        downloadedBytes: 157286400,
        downloadedAt: DateTime.utc(2026, 8, 25),
      );

      await registry.updateEntry(entry);
      expect(await registryFile.exists(), isTrue);

      final ModelsRegistry reloaded = ModelsRegistry(registryFile: registryFile);
      await reloaded.load();

      expect(reloaded.entries.length, equals(1));
      final ModelRegistryEntry loadedEntry = reloaded.getEntry('sensevoice-small', defaultLocalDir: '');
      expect(loadedEntry.status, equals(AsrModelStatus.downloaded));
      expect(loadedEntry.totalBytes, equals(157286400));
      expect(loadedEntry.isDownloaded, isTrue);
      expect(reloaded.installedCount, equals(1));

      await reloaded.dispose();
    });

    test('recovers gracefully from corrupted json file', () async {
      await registryFile.writeAsString('{ broken json: [1, 2, 3');
      await registry.load();
      expect(registry.entries, isEmpty);
    });

    test('marks in-flight downloading status as canceled on cold start', () async {
      final ModelRegistryEntry entry = ModelRegistryEntry(
        modelId: 'sensevoice-small',
        source: ModelSource.hfMirror,
        localDir: '${tempDir.path}/sensevoice-small',
        status: AsrModelStatus.downloading,
        totalBytes: 157286400,
        downloadedBytes: 50000000,
      );
      await registry.updateEntry(entry);

      final ModelsRegistry reloaded = ModelsRegistry(registryFile: registryFile);
      await reloaded.load();

      final ModelRegistryEntry loaded = reloaded.getEntry('sensevoice-small', defaultLocalDir: '');
      expect(loaded.status, equals(AsrModelStatus.canceled));
      expect(loaded.lastError, contains('interrupted'));

      await reloaded.dispose();
    });

    test('removes entry and updates count', () async {
      final ModelRegistryEntry entry = ModelRegistryEntry(
        modelId: 'sensevoice-small',
        source: ModelSource.hfMirror,
        localDir: '${tempDir.path}/sensevoice-small',
        status: AsrModelStatus.downloaded,
        totalBytes: 100,
        downloadedBytes: 100,
      );
      await registry.updateEntry(entry);
      expect(registry.installedCount, equals(1));

      await registry.removeEntry('sensevoice-small');
      expect(registry.entries, isEmpty);
      expect(registry.installedCount, equals(0));
    });
  });
}
