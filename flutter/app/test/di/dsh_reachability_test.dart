/// Reachability-probe tests: the classifier against every failure class the
/// transport seam can produce, plus the probe's own call shape.
///
/// The transport is stubbed at [DshRpcClient] — no socket is opened here;
/// the `HttpDshRpcClient` wrapping is exercised by `http_engine_test.dart`
/// and the live host, not by unit tests.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/di/dsh_reachability.dart';
import 'package:app/di/providers.dart';

/// One recorded stub call: endpoint, method, payload, deadline.
typedef _ProbeCall = (String, String, JsonMap, Duration?);

final class _StubClient implements DshRpcClient {
  _StubClient(this._respond);

  final Future<RpcResult> Function() _respond;
  final List<_ProbeCall> calls = <_ProbeCall>[];

  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) {
    calls.add((endpoint, method, payload, timeout));
    return _respond();
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

/// A probe whose one transport call answers or throws [error].
DshReachabilityProbe _probeThrowing(Object error) {
  final _StubClient client = _StubClient(() async {
    throw error;
  });
  return DshReachabilityProbe(
    transportFactory: (Uri baseUri, {required bool trustHostCertificate}) =>
        DshProbeTransport(client),
  );
}

void main() {
  group('classifyDshProbeResult', () {
    test('a well-formed ok answer is reachable', () {
      final DshProbeResult result = classifyDshProbeResult(
        RpcResult(ok: true, value: <String, Object?>{'writable': true}),
      );
      expect(result.outcome, DshProbeOutcome.reachable);
      expect(result.rpcErrorCode, isNull);
      expect(result.reachable, isTrue);
    });

    test('a well-formed business error is reachable and carries its code', () {
      final DshProbeResult result = classifyDshProbeResult(
        RpcResult(
          ok: false,
          error: RpcError(
            code: 'gateway/arguments-invalid',
            message: 'args fields do not match the descriptor',
          ),
        ),
      );
      expect(result.outcome, DshProbeOutcome.reachable);
      expect(result.rpcErrorCode, 'gateway/arguments-invalid');
    });
  });

  group('classifyDshProbeFailure', () {
    test('connection refused is unreachable', () {
      final DshProbeResult result = classifyDshProbeFailure(
        DshTransportException(
          'transport failure for api/settings/describe',
          const SocketException('Connection refused'),
        ),
      );
      expect(result.outcome, DshProbeOutcome.unreachable);
      expect(result.httpStatus, isNull);
    });

    test('a DNS lookup failure is unreachable', () {
      final DshProbeResult result = classifyDshProbeFailure(
        DshTransportException(
          'transport failure for api/settings/describe',
          const SocketException('Failed host lookup: no-such-host'),
        ),
      );
      expect(result.outcome, DshProbeOutcome.unreachable);
    });

    test('an elapsed request deadline is unreachable', () {
      final DshProbeResult result = classifyDshProbeFailure(
        DshTransportException(
          'request deadline 8000ms exceeded for api/settings/describe',
          TimeoutException('deadline'),
        ),
      );
      expect(result.outcome, DshProbeOutcome.unreachable);
    });

    test(
      'a named certificate failure is certificateNotTrusted, unambiguous',
      () {
        final DshProbeResult result = classifyDshProbeFailure(
          DshTransportException(
            'transport failure for api/settings/describe',
            const HandshakeException(
              'Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED: '
              'self signed certificate(handshake.cc:393))',
            ),
          ),
        );
        expect(result.outcome, DshProbeOutcome.certificateNotTrusted);
        expect(result.ambiguity, DshProbeAmbiguity.none);
      },
    );

    test('a TLS handshake error that names no certificate stays ambiguous', () {
      final DshProbeResult result = classifyDshProbeFailure(
        DshTransportException(
          'transport failure for api/settings/describe',
          const HandshakeException('Connection terminated during handshake'),
        ),
      );
      expect(result.outcome, DshProbeOutcome.certificateNotTrusted);
      expect(result.ambiguity, DshProbeAmbiguity.tlsHandshakeUnspecified);
    });

    test('a Cronet certificate error is certificateNotTrusted', () {
      final DshProbeResult result = classifyDshProbeFailure(
        DshTransportException(
          'transport failure for api/settings/describe',
          Exception('CronetClientException: net::ERR_CERT_AUTHORITY_INVALID'),
        ),
      );
      expect(result.outcome, DshProbeOutcome.certificateNotTrusted);
      expect(result.ambiguity, DshProbeAmbiguity.none);
    });

    test('HTTP 401 is authenticationRequired, not unreachable', () {
      final DshProbeResult result = classifyDshProbeFailure(
        DshTransportException.http(
          'HTTP 401 for api/settings/describe: Unauthorized',
          401,
        ),
      );
      expect(result.outcome, DshProbeOutcome.authenticationRequired);
      expect(result.httpStatus, 401);
    });

    test('HTTP 404 is its own class, separate from a connect failure', () {
      final DshProbeResult result = classifyDshProbeFailure(
        DshTransportException.http(
          'HTTP 404 for api/settings/describe: not found',
          404,
        ),
      );
      expect(result.outcome, DshProbeOutcome.notDshSurface);
      expect(result.httpStatus, 404);
    });

    test('any other non-2xx status is unexpectedResponse with its status', () {
      final DshProbeResult result = classifyDshProbeFailure(
        DshTransportException.http(
          'HTTP 502 for api/settings/describe: bad gateway',
          502,
        ),
      );
      expect(result.outcome, DshProbeOutcome.unexpectedResponse);
      expect(result.httpStatus, 502);
    });

    test('a status stamped in the message alone is not a status', () {
      // The classifier reads the typed field: a message that merely reads
      // like an HTTP failure must not fabricate one, or the class would come
      // from prose instead of from the exchange.
      final DshProbeResult result = classifyDshProbeFailure(
        DshTransportException(
          'HTTP 401 for api/settings/describe: Unauthorized',
        ),
      );
      expect(result.outcome, DshProbeOutcome.unknown);
      expect(result.httpStatus, isNull);
    });

    test('a 2xx body that is not an envelope is unexpectedResponse', () {
      final DshProbeResult result = classifyDshProbeFailure(
        DshTransportException(
          'invalid server-response for api/settings/describe',
          const FormatException('Unexpected character'),
        ),
      );
      expect(result.outcome, DshProbeOutcome.unexpectedResponse);
      expect(result.httpStatus, isNull);
    });

    test('a mismatched rpcId is unexpectedResponse', () {
      final DshProbeResult result = classifyDshProbeFailure(
        DshTransportException(
          'rpcId mismatch for api/settings/describe: expected a, got b',
        ),
      );
      expect(result.outcome, DshProbeOutcome.unexpectedResponse);
    });

    test('an unrecognized exception is unknown and flagged', () {
      final DshProbeResult result = classifyDshProbeFailure(
        StateError('the transport threw something else'),
      );
      expect(result.outcome, DshProbeOutcome.unknown);
      expect(result.ambiguity, DshProbeAmbiguity.unrecognizedFailure);
    });
  });

  group('DshReachabilityProbe', () {
    test(
      'sends the probe envelope with the deadline and closes the transport',
      () async {
        final _StubClient client = _StubClient(
          () async => RpcResult(ok: true, value: <String, Object?>{}),
        );
        bool closed = false;
        Uri? seenUri;
        bool? seenTrust;
        final DshReachabilityProbe probe = DshReachabilityProbe(
          timeout: const Duration(seconds: 3),
          transportFactory:
              (Uri baseUri, {required bool trustHostCertificate}) {
                seenUri = baseUri;
                seenTrust = trustHostCertificate;
                return DshProbeTransport(client, close: () => closed = true);
              },
        );

        final DshProbeResult result = await probe.probe(
          Uri.parse('https://box.example:8443'),
          trustHostCertificate: true,
        );

        expect(result.outcome, DshProbeOutcome.reachable);
        expect(seenUri, Uri.parse('https://box.example:8443'));
        expect(seenTrust, isTrue);
        expect(client.calls, hasLength(1));
        final _ProbeCall call = client.calls.single;
        expect(call.$1, kDshReachabilityProbeMethod);
        expect(call.$2, kDshReachabilityProbeMethod);
        expect(call.$3, <String, Object?>{'args': <String, Object?>{}});
        expect(call.$4, const Duration(seconds: 3));
        expect(closed, isTrue);
      },
    );

    test(
      'classifies a thrown failure and still closes the transport',
      () async {
        final _StubClient client = _StubClient(() async {
          throw DshTransportException(
            'transport failure for api/settings/describe',
            const SocketException('Connection refused'),
          );
        });
        bool closed = false;
        final DshReachabilityProbe probe = DshReachabilityProbe(
          transportFactory: (
            Uri baseUri, {
            required bool trustHostCertificate,
          }) => DshProbeTransport(client, close: () => closed = true),
        );

        final DshProbeResult result = await probe.probe(
          Uri.parse('http://127.0.0.1:1'),
          trustHostCertificate: false,
        );

        expect(result.outcome, DshProbeOutcome.unreachable);
        expect(closed, isTrue);
      },
    );

    test('the default trust flag is passed through as false', () async {
      final _StubClient client = _StubClient(
        () async => RpcResult(ok: true, value: <String, Object?>{}),
      );
      bool? seenTrust;
      final DshReachabilityProbe probe = DshReachabilityProbe(
        transportFactory: (Uri baseUri, {required bool trustHostCertificate}) {
          seenTrust = trustHostCertificate;
          return DshProbeTransport(client);
        },
      );

      await probe.probe(
        Uri.parse('http://127.0.0.1:3080'),
        trustHostCertificate: false,
      );

      expect(seenTrust, isFalse);
    });

    test(
      'a probe that throws an unclassifiable error returns, never throws',
      () async {
        final DshReachabilityProbe probe = _probeThrowing(StateError('boom'));
        final DshProbeResult result = await probe.probe(
          Uri.parse('http://127.0.0.1:3080'),
          trustHostCertificate: false,
        );
        expect(result.outcome, DshProbeOutcome.unknown);
      },
    );
  });
}
