/// The HTTP/3 engine factory never throws outside Android and always
/// yields null there, so every host-side test surface (and CI) rides the
/// default `IOClient` path unchanged. The Android branch itself is not
/// unit-testable on this host: it is covered by the Gradle build smoke
/// (cronet-embedded packaging) and real-device grayscale, per the
/// [HTTP/3 engine decision note](../../../../.agents/notes/implemented/feature/2026-09-02-http3-cronet-engine-default.md).
library;

import 'package:app/di/http_engine.dart';
import 'package:app/di/providers.dart';
import 'package:domain/model/backend.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

final class _ThrowingOnCloseHttpClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError();
  }

  @override
  void close() {
    closed = true;
    throw Exception(
      'java.lang.IllegalStateException: Cannot shutdown with running requests.',
    );
  }
}

void main() {
  tearDown(() {
    customHttpEngineBuilder = null;
    resetCronetEngineForTesting();
  });

  test('non-Android host returns null (default engine fallback)', () {
    expect(dshHttp3Engine(), isNull);
  });

  test('customHttpEngineBuilder allows overriding engine in tests', () {
    final client = _ThrowingOnCloseHttpClient();
    customHttpEngineBuilder = () => client;
    expect(dshHttp3Engine(), same(client));
  });

  test('dshRpcClientProvider swallows engine close errors on dispose', () {
    final client = _ThrowingOnCloseHttpClient();
    customHttpEngineBuilder = () => client;

    final container = ProviderContainer();
    final clientInstance = container.read(
      dshRpcClientProvider(Uri.parse('http://127.0.0.1:3080')),
    );
    expect(clientInstance, isNotNull);

    // Disposing the container must not throw even though client.close() throws.
    expect(() => container.dispose(), returnsNormally);
    expect(client.closed, isTrue);
  });

  test('the certificate rule accepts the exact host only', () {
    expect(trustedCertificateHostMatches('gw.internal', 'gw.internal'), isTrue);
    expect(
      trustedCertificateHostMatches('gw.internal', 'evil.internal'),
      isFalse,
    );
    expect(
      trustedCertificateHostMatches('gw.internal', 'gw.internal.evil'),
      isFalse,
    );
    expect(trustedCertificateHostMatches('gw.internal', '127.0.0.1'), isFalse);
  });

  test('a trusted https backend bypasses the Cronet engine', () {
    final fake = _ThrowingOnCloseHttpClient();
    var engineBuilt = false;
    customHttpEngineBuilder = () {
      engineBuilt = true;
      return fake;
    };
    final uri = Uri.parse('https://gw.internal:8443');
    final container = ProviderContainer(
      overrides: [
        backendRegistryStateProvider.overrideWithValue(
          AsyncData<BackendRegistryState>(
            BackendRegistryState(
              backends: [
                BackendConfig(
                  id: 'gw',
                  label: 'Gateway',
                  baseUri: uri,
                  trustHostCertificate: true,
                ),
              ],
              activeId: 'gw',
            ),
          ),
        ),
      ],
    );

    final client = container.read(dshRpcClientProvider(uri));
    expect(client, isNot(same(fake)));
    expect(engineBuilt, isFalse);
    container.dispose();
  });

  test('an untrusted https backend keeps the Cronet engine', () {
    final engine = _ThrowingOnCloseHttpClient();
    customHttpEngineBuilder = () => engine;
    final uri = Uri.parse('https://gw.internal:8443');
    final container = ProviderContainer(
      overrides: [
        backendRegistryStateProvider.overrideWithValue(
          AsyncData<BackendRegistryState>(
            BackendRegistryState(
              backends: [
                BackendConfig(id: 'gw', label: 'Gateway', baseUri: uri),
              ],
              activeId: 'gw',
            ),
          ),
        ),
      ],
    );

    final client = container.read(dshRpcClientProvider(uri));
    expect(client, isNotNull);
    container.dispose();
    expect(engine.closed, isTrue);
  });
}
