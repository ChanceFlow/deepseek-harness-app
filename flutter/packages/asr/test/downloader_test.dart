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
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
}

/// A body that delivers [prefix] and then dies with the exact error the
/// HF xet CDN produces on a dropped connection mid-transfer.
Stream<List<int>> brokenBody(List<int> prefix) async* {
  yield prefix;
  throw http.ClientException('Connection closed while receiving data');
}

/// A body that delivers [prefix] and then goes silent for far longer than
/// any injected stall timeout before resuming.
Stream<List<int>> stalledBody(List<int> prefix) async* {
  yield prefix;
  await Future<void>.delayed(const Duration(milliseconds: 200));
  yield utf8.encode('456789');
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
      final MockHttpClient client = MockHttpClient((
        http.BaseRequest request,
      ) async {
        final Stream<List<int>> stream = Stream<List<int>>.value(
          utf8.encode('0123456789'),
        );
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
      int callCount = 0;
      final MockHttpClient client = MockHttpClient((
        http.BaseRequest request,
      ) async {
        callCount++;
        // Wrong bytes for the manifest's checksum (hash of '0123456789').
        final Stream<List<int>> stream = Stream<List<int>>.value(
          utf8.encode('abcdefghij'),
        );
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

      // The corrupt partial is removed so the next attempt starts fresh,
      // and deterministic corruption is not retried.
      expect(callCount, equals(1));
      expect(
        await File('${tempDir.path}/test.onnx.downloading').exists(),
        isFalse,
      );
      expect(await File('${tempDir.path}/test.onnx').exists(), isFalse);
    });

    test(
      'skips hash verification when the manifest checksum is unprovisioned',
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

        final MockHttpClient client = MockHttpClient((
          http.BaseRequest request,
        ) async {
          final Stream<List<int>> stream = Stream<List<int>>.value(
            utf8.encode('deadbeef!!'),
          );
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
      },
    );

    test('resumes partial download using Range 206 Partial Content', () async {
      final File partialFile = File('${tempDir.path}/test.onnx.downloading');
      await partialFile.writeAsString('01234'); // 5 bytes

      final MockHttpClient client = MockHttpClient((
        http.BaseRequest request,
      ) async {
        final String? range = request.headers['Range'];
        expect(range, equals('bytes=5-'));
        final Stream<List<int>> stream = Stream<List<int>>.value(
          utf8.encode('56789'),
        );
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

    test(
      'recovers from 416 Range Not Satisfiable by downloading fresh',
      () async {
        final File partialFile = File('${tempDir.path}/test.onnx.downloading');
        await partialFile.writeAsString('corrupted-data');

        int callCount = 0;
        final MockHttpClient client = MockHttpClient((
          http.BaseRequest request,
        ) async {
          callCount++;
          if (callCount == 1) {
            return http.StreamedResponse(const Stream<List<int>>.empty(), 416);
          }
          final Stream<List<int>> stream = Stream<List<int>>.value(
            utf8.encode('0123456789'),
          );
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
      },
    );

    test('cancels in-flight download cleanly', () async {
      final MockHttpClient client = MockHttpClient((
        http.BaseRequest request,
      ) async {
        return http.StreamedResponse(
          const Stream<List<int>>.empty(),
          200,
          contentLength: 10,
        );
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

    test('retries and resumes after a mid-body connection drop', () async {
      final List<http.BaseRequest> requests = <http.BaseRequest>[];
      final MockHttpClient client = MockHttpClient((
        http.BaseRequest request,
      ) async {
        requests.add(request);
        if (requests.length == 1) {
          return http.StreamedResponse(
            brokenBody(utf8.encode('0123')),
            200,
            contentLength: 10,
          );
        }
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode('456789')),
          206,
          contentLength: 6,
        );
      });

      final AsrDownloader downloader = AsrDownloader(
        httpClient: client,
        retryDelayHandler: (_) async {},
      );
      await downloader.downloadModel(
        model: testModel,
        sourceClient: const HfMirrorSourceClient(),
        targetDir: tempDir,
        onProgress: (_) {},
      );

      final File downloadedFile = File('${tempDir.path}/test.onnx');
      expect(await downloadedFile.exists(), isTrue);
      expect(await downloadedFile.readAsString(), equals('0123456789'));
      expect(requests.length, equals(2));
      expect(requests[1].headers['Range'], equals('bytes=4-'));
    });

    test(
      'fails loudly after exhausting retries on a dying connection',
      () async {
        int callCount = 0;
        final MockHttpClient client = MockHttpClient((_) async {
          callCount++;
          return http.StreamedResponse(
            brokenBody(utf8.encode('0123')),
            200,
            contentLength: 10,
          );
        });

        final AsrDownloader downloader = AsrDownloader(
          httpClient: client,
          maxAttemptsPerFile: 3,
          retryDelayHandler: (_) async {},
        );

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
              contains('Connection interrupted'),
            ),
          ),
        );
        expect(callCount, equals(3));
        // The partial survives so the next download attempt resumes.
        expect(
          await File('${tempDir.path}/test.onnx.downloading').exists(),
          isTrue,
        );
      },
    );

    test('does not retry permanent HTTP failures', () async {
      int callCount = 0;
      final MockHttpClient client = MockHttpClient((_) async {
        callCount++;
        return http.StreamedResponse(
          const Stream<List<int>>.empty(),
          404,
          reasonPhrase: 'Not Found',
        );
      });

      final AsrDownloader downloader = AsrDownloader(
        httpClient: client,
        retryDelayHandler: (_) async {},
      );

      await expectLater(
        downloader.downloadModel(
          model: testModel,
          sourceClient: const HfMirrorSourceClient(),
          targetDir: tempDir,
          onProgress: (_) {},
        ),
        throwsA(
          isA<DownloadFailedException>().having(
            (DownloadFailedException e) => e.statusCode,
            'statusCode',
            equals(404),
          ),
        ),
      );
      expect(callCount, equals(1));
    });

    test('retries a transient HTTP 500 and completes', () async {
      int callCount = 0;
      final MockHttpClient client = MockHttpClient((_) async {
        callCount++;
        if (callCount == 1) {
          return http.StreamedResponse(
            const Stream<List<int>>.empty(),
            500,
            reasonPhrase: 'Internal Server Error',
          );
        }
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode('0123456789')),
          200,
          contentLength: 10,
        );
      });

      final AsrDownloader downloader = AsrDownloader(
        httpClient: client,
        retryDelayHandler: (_) async {},
      );
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

    test('treats a stalled body as a retryable failure and resumes', () async {
      final List<http.BaseRequest> requests = <http.BaseRequest>[];
      final MockHttpClient client = MockHttpClient((
        http.BaseRequest request,
      ) async {
        requests.add(request);
        if (requests.length == 1) {
          return http.StreamedResponse(
            stalledBody(utf8.encode('0123')),
            200,
            contentLength: 10,
          );
        }
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode('456789')),
          206,
          contentLength: 6,
        );
      });

      final AsrDownloader downloader = AsrDownloader(
        httpClient: client,
        stallTimeout: const Duration(milliseconds: 50),
        retryDelayHandler: (_) async {},
      );
      await downloader.downloadModel(
        model: testModel,
        sourceClient: const HfMirrorSourceClient(),
        targetDir: tempDir,
        onProgress: (_) {},
      );

      final File downloadedFile = File('${tempDir.path}/test.onnx');
      expect(await downloadedFile.exists(), isTrue);
      expect(await downloadedFile.readAsString(), equals('0123456789'));
      expect(requests.length, equals(2));
      expect(requests[1].headers['Range'], equals('bytes=4-'));
    });

    test('cancel during the retry backoff stops the download', () async {
      final MockHttpClient client = MockHttpClient((_) async {
        return http.StreamedResponse(
          brokenBody(utf8.encode('0123')),
          200,
          contentLength: 10,
        );
      });

      late final AsrDownloader downloader;
      downloader = AsrDownloader(
        httpClient: client,
        retryDelayHandler: (_) async {
          downloader.cancel();
        },
      );

      await expectLater(
        downloader.downloadModel(
          model: testModel,
          sourceClient: const HfMirrorSourceClient(),
          targetDir: tempDir,
          onProgress: (_) {},
        ),
        throwsA(isA<DownloadCanceledException>()),
      );
    });
  });
}
