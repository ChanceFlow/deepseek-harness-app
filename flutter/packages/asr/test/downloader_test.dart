import 'dart:async';
import 'dart:convert';
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
  group('AsrDownloader', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('asr_dl_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    const AsrModelInfo testModel = AsrModelInfo(
      id: 'test-model',
      name: 'Test Model',
      descriptionZh: '测试',
      descriptionEn: 'Test',
      languages: 'en',
      estimatedSizeBytes: 10,
      license: 'MIT',
      huggingFaceRepo: 'test/repo',
      files: <AsrModelFile>[
        AsrModelFile(
          name: 'test.onnx',
          sizeBytes: 10,
          sha256: '84d89877f0d4041efb6bf91a16f0248f2fd573e6af05c19f96bedb9f882f7882', // sha256 of "0123456789"
          hfMirrorUrl: 'https://hf-mirror.com/test.onnx',
          huggingFaceUrl: 'https://huggingface.co/test.onnx',
        ),
      ],
    );

    test('downloads model file from 200 OK response', () async {
      final MockHttpClient client = MockHttpClient((http.BaseRequest request) async {
        final Stream<List<int>> stream = Stream<List<int>>.value(utf8.encode('0123456789'));
        return http.StreamedResponse(stream, 200, contentLength: 10);
      });

      final AsrDownloader downloader = AsrDownloader(httpClient: client);
      final List<DownloadProgress> progressList = <DownloadProgress>[];

      await downloader.downloadModel(
        model: testModel,
        sourceClient: const HfMirrorSourceClient(),
        targetDir: tempDir,
        onProgress: progressList.add,
      );

      final File downloadedFile = File('${tempDir.path}/test.onnx');
      expect(await downloadedFile.exists(), isTrue);
      expect(await downloadedFile.readAsString(), equals('0123456789'));
      expect(progressList.isNotEmpty, isTrue);
    });

    test('rejects content that fails SHA-256 verification', () async {
      final MockHttpClient client = MockHttpClient((http.BaseRequest request) async {
        // Wrong bytes for the manifest's checksum (hash of '0123456789').
        final Stream<List<int>> stream =
            Stream<List<int>>.value(utf8.encode('abcdefghij'));
        return http.StreamedResponse(stream, 200, contentLength: 10);
      });

      final AsrDownloader downloader = AsrDownloader(httpClient: client);

      await expectLater(
        downloader.downloadModel(
          model: testModel,
          sourceClient: const HfMirrorSourceClient(),
          targetDir: tempDir,
          onProgress: (_) {},
        ),
        throwsA(
          isA<DownloadFailedException>().having(
            (DownloadFailedException e) => e.message,
            'message',
            contains('SHA-256 mismatch'),
          ),
        ),
      );

      // The corrupt partial is removed so the next attempt starts fresh.
      expect(await File('${tempDir.path}/test.onnx.downloading').exists(), isFalse);
      expect(await File('${tempDir.path}/test.onnx').exists(), isFalse);
    });

    test('skips hash verification when the manifest checksum is unprovisioned',
        () async {
      const AsrModelInfo unprovisionedModel = AsrModelInfo(
        id: 'unprovisioned-model',
        name: 'Unprovisioned Model',
        descriptionZh: '测试',
        descriptionEn: 'Test',
        languages: 'en',
        estimatedSizeBytes: 10,
        license: 'MIT',
        huggingFaceRepo: 'test/repo',
        files: <AsrModelFile>[
          AsrModelFile(
            name: 'test.onnx',
            sizeBytes: 10,
            sha256: '', // unprovisioned
            hfMirrorUrl: 'https://hf-mirror.com/test.onnx',
            huggingFaceUrl: 'https://huggingface.co/test.onnx',
          ),
        ],
      );

      final MockHttpClient client = MockHttpClient((http.BaseRequest request) async {
        final Stream<List<int>> stream =
            Stream<List<int>>.value(utf8.encode('deadbeef!!'));
        return http.StreamedResponse(stream, 200, contentLength: 10);
      });

      final AsrDownloader downloader = AsrDownloader(httpClient: client);
      await downloader.downloadModel(
        model: unprovisionedModel,
        sourceClient: const HfMirrorSourceClient(),
        targetDir: tempDir,
        onProgress: (_) {},
      );

      final File downloadedFile = File('${tempDir.path}/test.onnx');
      expect(await downloadedFile.exists(), isTrue);
      expect(await downloadedFile.readAsString(), equals('deadbeef!!'));
    });

    test('resumes partial download using Range 206 Partial Content', () async {
      final File partialFile = File('${tempDir.path}/test.onnx.downloading');
      await partialFile.writeAsString('01234'); // 5 bytes

      final MockHttpClient client = MockHttpClient((http.BaseRequest request) async {
        final String? range = request.headers['Range'];
        expect(range, equals('bytes=5-'));
        final Stream<List<int>> stream = Stream<List<int>>.value(utf8.encode('56789'));
        return http.StreamedResponse(stream, 206, contentLength: 5);
      });

      final AsrDownloader downloader = AsrDownloader(httpClient: client);
      await downloader.downloadModel(
        model: testModel,
        sourceClient: const HfMirrorSourceClient(),
        targetDir: tempDir,
        onProgress: (_) {},
      );

      final File downloadedFile = File('${tempDir.path}/test.onnx');
      expect(await downloadedFile.exists(), isTrue);
      expect(await downloadedFile.readAsString(), equals('0123456789'));
    });

    test('recovers from 416 Range Not Satisfiable by downloading fresh', () async {
      final File partialFile = File('${tempDir.path}/test.onnx.downloading');
      await partialFile.writeAsString('corrupted-data');

      int callCount = 0;
      final MockHttpClient client = MockHttpClient((http.BaseRequest request) async {
        callCount++;
        if (callCount == 1) {
          return http.StreamedResponse(const Stream<List<int>>.empty(), 416);
        }
        final Stream<List<int>> stream = Stream<List<int>>.value(utf8.encode('0123456789'));
        return http.StreamedResponse(stream, 200, contentLength: 10);
      });

      final AsrDownloader downloader = AsrDownloader(httpClient: client);
      await downloader.downloadModel(
        model: testModel,
        sourceClient: const HfMirrorSourceClient(),
        targetDir: tempDir,
        onProgress: (_) {},
      );

      final File downloadedFile = File('${tempDir.path}/test.onnx');
      expect(await downloadedFile.exists(), isTrue);
      expect(await downloadedFile.readAsString(), equals('0123456789'));
      expect(callCount, equals(2));
    });

    test('cancels in-flight download cleanly', () async {
      final MockHttpClient client = MockHttpClient((http.BaseRequest request) async {
        return http.StreamedResponse(const Stream<List<int>>.empty(), 200, contentLength: 10);
      });

      final AsrDownloader downloader = AsrDownloader(httpClient: client);
      downloader.cancel();

      final Future<void> downloadFuture = downloader.downloadModel(
        model: testModel,
        sourceClient: const HfMirrorSourceClient(),
        targetDir: tempDir,
        onProgress: (_) {},
      );

      await expectLater(
        downloadFuture,
        throwsA(isA<DownloadCanceledException>()),
      );
    });
  });
}
