/// The downloadable on-device ASR runtime: manifest shape, download-and-verify
/// install, marker-gated readiness, and uninstall.
///
/// The published manifest pins real 15–25 MB libraries, so the download path
/// runs against a tiny [AsrRuntimeArtifact] override served by a real
/// `MockClient`: the manager's own URL building, `AsrDownloader` verification,
/// marker write and directory layout are all the production ones.
library;

import 'dart:convert';
import 'dart:io';

import 'package:asr/asr.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Bytes a fake release serves for one library.
List<int> _libBytes(String seed) => utf8.encode('library:$seed:${'x' * 64}');

AsrRuntimeArtifact _artifactFor(List<int> onnx, List<int> cApi) =>
    AsrRuntimeArtifact(
      abi: 'arm64-v8a',
      libs: <AsrRuntimeLib>[
        AsrRuntimeLib(
          name: 'libonnxruntime.so',
          sizeBytes: onnx.length,
          sha256: sha256.convert(onnx).toString(),
        ),
        AsrRuntimeLib(
          name: 'libsherpa-onnx-c-api.so',
          sizeBytes: cApi.length,
          sha256: sha256.convert(cApi).toString(),
        ),
      ],
    );

void main() {
  group('published manifest', () {
    test('covers every shipped ABI with both libraries', () {
      expect(
        kAsrRuntimeArtifacts.keys,
        containsAll(<String>['arm64-v8a', 'armeabi-v7a', 'x86_64']),
      );
      for (final MapEntry<String, AsrRuntimeArtifact> entry
          in kAsrRuntimeArtifacts.entries) {
        final AsrRuntimeArtifact artifact = entry.value;
        expect(artifact.abi, entry.key);
        expect(artifact.libs.map((AsrRuntimeLib lib) => lib.name), <String>[
          'libonnxruntime.so',
          'libsherpa-onnx-c-api.so',
        ], reason: 'onnxruntime must precede the c-api library that needs it');
        for (final AsrRuntimeLib lib in artifact.libs) {
          expect(lib.sizeBytes, greaterThan(1000000));
          expect(lib.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
          expect(
            lib.assetName(entry.key),
            'asr-runtime-$kSherpaOnnxVersion-${entry.key}-${lib.name}',
          );
        }
      }
    });
  });

  group('AsrRuntimeManager', () {
    late Directory baseDir;
    late List<Uri> requested;

    setUp(() {
      baseDir = Directory.systemTemp.createTempSync('asr_runtime_test');
      requested = <Uri>[];
    });

    tearDown(() {
      if (baseDir.existsSync()) baseDir.deleteSync(recursive: true);
    });

    AsrRuntimeManager managerFor(
      AsrRuntimeArtifact artifact,
      Map<String, List<int>> bodies, {
      Map<String, List<int>>? overrides,
    }) {
      final MockClient client = MockClient((http.Request request) async {
        requested.add(request.url);
        final String name = request.url.pathSegments.last;
        final List<int>? body = overrides?[name] ?? bodies[name];
        if (body == null) return http.Response('not found', 404);
        return http.Response.bytes(body, 200);
      });
      return AsrRuntimeManager(
        baseDir: baseDir,
        baseUrl: 'https://example.test/releases/download',
        tag: 'dev',
        abi: artifact.abi,
        downloader: AsrDownloader(
          httpClient: client,
          retryDelayHandler: (int _) async {},
        ),
        artifactOverride: artifact,
      );
    }

    test(
      'install downloads both libraries, verifies them, and marks ready',
      () async {
        final List<int> onnx = _libBytes('onnx');
        final List<int> cApi = _libBytes('capi');
        final AsrRuntimeArtifact artifact = _artifactFor(onnx, cApi);
        final AsrRuntimeManager manager = managerFor(
          artifact,
          <String, List<int>>{
            'asr-runtime-$kSherpaOnnxVersion-arm64-v8a-libonnxruntime.so': onnx,
            'asr-runtime-$kSherpaOnnxVersion-arm64-v8a-libsherpa-onnx-c-api.so':
                cApi,
          },
        );
        addTearDown(manager.dispose);

        expect((await manager.refresh()).status, AsrRuntimeStatus.missing);
        await manager.install();

        expect(manager.state.status, AsrRuntimeStatus.ready);
        expect(await manager.isInstalled(), isTrue);
        expect(await manager.installedLibraryDir(), manager.runtimeDir.path);
        expect(
          File('${manager.runtimeDir.path}/libonnxruntime.so')
              .readAsBytesSync(),
          onnx,
        );
        // Every request went to this build's release assets.
        expect(requested, hasLength(2));
        for (final Uri url in requested) {
          expect(url.path, startsWith('/releases/download/dev/asr-runtime-'));
        }
      },
    );

    test(
      'a library whose bytes do not match the manifest never installs',
      () async {
        final List<int> onnx = _libBytes('onnx');
        final List<int> cApi = _libBytes('capi');
        final AsrRuntimeArtifact artifact = _artifactFor(onnx, cApi);
        final AsrRuntimeManager manager = managerFor(
          artifact,
          <String, List<int>>{
            'asr-runtime-$kSherpaOnnxVersion-arm64-v8a-libonnxruntime.so': onnx,
            'asr-runtime-$kSherpaOnnxVersion-arm64-v8a-libsherpa-onnx-c-api.so':
                cApi,
          },
          // The c-api asset serves different bytes than the manifest pins.
          overrides: <String, List<int>>{
            'asr-runtime-$kSherpaOnnxVersion-arm64-v8a-libsherpa-onnx-c-api.so':
                _libBytes('swapped'),
          },
        );
        addTearDown(manager.dispose);

        await expectLater(manager.install(), throwsA(isA<Exception>()));
        expect(manager.state.status, AsrRuntimeStatus.failed);
        expect(await manager.isInstalled(), isFalse);
        expect(await manager.installedLibraryDir(), isNull);
      },
    );

    test('uninstall removes the libraries and returns to missing', () async {
      final List<int> onnx = _libBytes('onnx');
      final List<int> cApi = _libBytes('capi');
      final AsrRuntimeArtifact artifact = _artifactFor(onnx, cApi);
      final AsrRuntimeManager manager = managerFor(
        artifact,
        <String, List<int>>{
          'asr-runtime-$kSherpaOnnxVersion-arm64-v8a-libonnxruntime.so': onnx,
          'asr-runtime-$kSherpaOnnxVersion-arm64-v8a-libsherpa-onnx-c-api.so':
              cApi,
        },
      );
      addTearDown(manager.dispose);

      await manager.install();
      await manager.uninstall();

      expect(manager.state.status, AsrRuntimeStatus.missing);
      expect(manager.runtimeDir.existsSync(), isFalse);
    });

    test('an ABI with no published runtime stays unavailable', () async {
      final AsrRuntimeManager manager = AsrRuntimeManager(
        baseDir: baseDir,
        baseUrl: 'https://example.test/releases/download',
        tag: 'dev',
        abi: 'mips',
        downloader: AsrDownloader(
          httpClient: MockClient((_) async => http.Response('', 404)),
        ),
      );
      addTearDown(manager.dispose);

      expect(manager.artifact, isNull);
      expect((await manager.refresh()).status, AsrRuntimeStatus.missing);
      expect(await manager.installedLibraryDir(), isNull);
      await expectLater(manager.install(), throwsA(isA<StateError>()));
    });
  });
}
