/// Reachability probe for one dsh base URL.
///
/// A configured host fails in several ways that look identical to the UI —
/// a wrong address, a stopped gateway, an unreachable upstream, an
/// untrusted certificate, a deployment that demands authentication the
/// client does not carry. This probe runs one real public-plane RPC over
/// the app's existing transport seam and classifies the outcome so the
/// Settings host sheet can name the failure honestly instead of leaving the
/// user with an empty session list.
///
/// It lives in `lib/di/` because [DshTransportException] is a `network`
/// type. The exported [DshProbeResult] carries no wire vocabulary, so the
/// UI stays on the app side of the import gate
/// (`scripts/check_dart_imports.py`).
///
/// Probing is explicit: [DshReachabilityProbe.probe] is called for one
/// address on user action, never from a `build` method.
library;

import 'dart:async' show TimeoutException;
import 'dart:io' show HandshakeException, HttpClient, TlsException;

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;
import 'package:network/dsh_exceptions.dart';
import 'package:network/dsh_rpc_client.dart';
import 'package:network/http_dsh_rpc_client.dart';
import 'package:network/rpc_envelope.dart';

import 'http_engine.dart';

/// The public-plane RPC the probe sends.
///
/// `settings/describe` is the clearest available liveness signal: on the
/// pinned host it needs no argument beyond the empty `args` wrapper and a
/// healthy gateway answers `200` with `result.ok: true` and a well-formed
/// value (verified against `http://127.0.0.1:8102/`). `session/list`
/// answers with the same empty wrapper (it never throws a transport error)
/// but only as a `gateway/arguments-invalid` business error, so it proves
/// liveness through a rejection the probe would have to read as success.
/// `settings/describe` is also the call the Settings surface itself makes,
/// so a green probe predicts the page it gates.
const String kDshReachabilityProbeMethod = 'settings/describe';

/// The probe's request deadline.
///
/// Bounded so a black-holed address settles the sheet's in-progress state
/// instead of hanging it; longer than a healthy exchange and shorter than
/// the transport's 10s connection timeout (`kDshRpcConnectTimeout`).
const Duration kDshReachabilityProbeTimeout = Duration(seconds: 8);

/// How one probe attempt ended, as far as the client can tell.
enum DshProbeOutcome {
  /// A well-formed JSON-RPC envelope came back — `ok: true`, or `ok: false`
  /// with a business error (`gateway/arguments-invalid`, say), which proves
  /// the contract is live just as strongly.
  reachable,

  /// Connection refused, DNS failure, or the request deadline elapsed:
  /// nothing is listening, or the gateway is not running.
  unreachable,

  /// The TLS handshake failed. The user's per-host certificate opt-in is
  /// the remedy this class exists to point at.
  certificateNotTrusted,

  /// The host answered `401`. Either the gateway is deployed with
  /// authentication (`DSH_GW_AUTH=device`/`session`) or a raw `dsh web` host
  /// demands the URL token it prints; this client performs neither, so the
  /// host requires pairing or credentials the client does not have. Never
  /// reported as unreachable — something answered.
  authenticationRequired,

  /// The host answered `404` on the probe route: something is listening,
  /// but it is not a dsh host.
  notDshSurface,

  /// The host answered with a non-2xx status other than `401`/`404`, or
  /// with a body that is not a JSON-RPC envelope. Something answered, but
  /// not as the dsh contract.
  unexpectedResponse,

  /// The failure carried no signal this classifier recognizes. Reported as
  /// itself rather than folded into a class it might not belong to.
  unknown,
}

/// The alternative a class may equally be, when the available signal cannot
/// separate the two.
enum DshProbeAmbiguity {
  /// The class is proven by the signal.
  none,

  /// A TLS handshake failed without naming a certificate: a certificate the
  /// system rejects and any other TLS mismatch (plaintext port, protocol
  /// version) look the same here. Classified as
  /// [DshProbeOutcome.certificateNotTrusted] because the trust toggle is
  /// the remedy when it is the certificate.
  tlsHandshakeUnspecified,

  /// An exception outside the transport's vocabulary, or a transport
  /// failure with no recognizable shape.
  unrecognizedFailure,
}

/// One probe's classified outcome.
///
/// The class is the model's answer; [httpStatus], [rpcErrorCode], and
/// [ambiguity] carry the raw evidence and any residual doubt so no surface
/// has to guess from the class alone.
final class DshProbeResult {
  const DshProbeResult({
    required this.outcome,
    this.httpStatus,
    this.rpcErrorCode,
    this.ambiguity = DshProbeAmbiguity.none,
  });

  final DshProbeOutcome outcome;

  /// The HTTP status the transport reported, when the failure was a
  /// non-2xx response; null otherwise.
  final int? httpStatus;

  /// The business error code of a well-formed `ok: false` answer; null for
  /// every other outcome.
  final String? rpcErrorCode;

  /// The alternative the class may equally be; [DshProbeAmbiguity.none]
  /// when the signal proves the class.
  final DshProbeAmbiguity ambiguity;

  /// Whether the address reached the dsh contract.
  bool get reachable => outcome == DshProbeOutcome.reachable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DshProbeResult &&
          other.outcome == outcome &&
          other.httpStatus == httpStatus &&
          other.rpcErrorCode == rpcErrorCode &&
          other.ambiguity == ambiguity);

  @override
  int get hashCode => Object.hash(outcome, httpStatus, rpcErrorCode, ambiguity);

  @override
  String toString() =>
      'DshProbeResult(${outcome.name}, httpStatus: $httpStatus, '
      'rpcErrorCode: $rpcErrorCode, ambiguity: ${ambiguity.name})';
}

/// The transport one probe attempt rides, plus the release hook for what
/// the factory opened. The probe closes the handle when the attempt ends.
final class DshProbeTransport {
  const DshProbeTransport(this.client, {this.close});

  final DshRpcClient client;

  /// Releases the client's sockets; null when the client owns no closeable
  /// resource. Teardown errors are swallowed by the probe.
  final void Function()? close;
}

/// Builds the transport for one (URL, trust) pair.
typedef DshProbeTransportFactory = DshProbeTransport Function(
  Uri baseUri, {
  required bool trustHostCertificate,
});

/// Builds the probe's transport with the app's existing policy.
///
/// The trust opt-in is passed in rather than read from the registry: the
/// host sheet probes URLs the registry does not know yet, so the family
/// seam (`dshRpcClientProvider`, which selects trust out of the registry by
/// URL) cannot answer for an unsaved edit. The construction matches that
/// seam otherwise — `https` plus the opt-in rides the dart:io certificate
/// override for that exact host, everything else rides the shared Cronet
/// engine when it exists. Unlike the family seam, the probe always owns a
/// closeable client and releases it.
DshProbeTransport buildProbeTransport(
  Uri baseUri, {
  required bool trustHostCertificate,
}) {
  if (trustHostCertificate && baseUri.scheme == 'https') {
    final http.Client trusted = trustedHostRpcClient(
      baseUri.host,
      connectionTimeout: kDshRpcConnectTimeout,
    );
    return DshProbeTransport(
      HttpDshRpcClient(baseUri, httpClient: trusted),
      close: trusted.close,
    );
  }
  final http.Client? engine = dshHttp3Engine();
  if (engine != null) {
    return DshProbeTransport(
      HttpDshRpcClient(baseUri, httpClient: engine),
      close: engine.close,
    );
  }
  // Non-Android hosts and Cronet construction failure: the same dart:io
  // default `HttpDshRpcClient` falls back to, built here so the probe can
  // close it.
  final http.Client fallback = IOClient(
    HttpClient()..connectionTimeout = kDshRpcConnectTimeout,
  );
  return DshProbeTransport(
    HttpDshRpcClient(baseUri, httpClient: fallback),
    close: fallback.close,
  );
}

/// Runs one bounded probe and classifies the result.
final class DshReachabilityProbe {
  const DshReachabilityProbe({
    this.timeout = kDshReachabilityProbeTimeout,
    this.transportFactory = buildProbeTransport,
  });

  final Duration timeout;
  final DshProbeTransportFactory transportFactory;

  /// Sends [kDshReachabilityProbeMethod] to [baseUri] and returns the
  /// classified outcome. Never throws: every failure is a classified
  /// result, so callers cannot mistake an exception for a state they did
  /// not handle.
  Future<DshProbeResult> probe(
    Uri baseUri, {
    required bool trustHostCertificate,
  }) async {
    final DshProbeTransport transport = transportFactory(
      baseUri,
      trustHostCertificate: trustHostCertificate,
    );
    try {
      final RpcResult result;
      try {
        result = await transport.client.call(
          kDshReachabilityProbeMethod,
          kDshReachabilityProbeMethod,
          const <String, Object?>{'args': <String, Object?>{}},
          timeout: timeout,
        );
      } catch (error) {
        return classifyDshProbeFailure(error);
      }
      return classifyDshProbeResult(result);
    } finally {
      final void Function()? close = transport.close;
      if (close != null) {
        try {
          close();
        } catch (_) {
          // Swallowed: probe teardown must never crash the app.
        }
      }
    }
  }
}

/// Classifies a JSON-RPC answer.
///
/// Both arms prove a live contract: `ok: false` is a well-formed envelope
/// carrying a business error, not an unreachable host.
DshProbeResult classifyDshProbeResult(RpcResult result) {
  return DshProbeResult(
    outcome: DshProbeOutcome.reachable,
    rpcErrorCode: result.ok ? null : result.error?.code,
  );
}

/// Classifies a thrown failure.
///
/// The transport seam (`network`'s `HttpDshRpcClient`) reports every
/// failure as [DshTransportException] and does not expose a typed status
/// code, so an HTTP status is read from the message it stamps
/// (`HTTP <status> for <path>`). The `network` package is out of this
/// change's scope; a typed status is the cleaner seam and is reported as
/// such in the decision note.
DshProbeResult classifyDshProbeFailure(Object error) {
  if (error is! DshTransportException) {
    return const DshProbeResult(
      outcome: DshProbeOutcome.unknown,
      ambiguity: DshProbeAmbiguity.unrecognizedFailure,
    );
  }
  final int? status = _httpStatusOf(error.message);
  if (status != null) {
    return switch (status) {
      401 => const DshProbeResult(
        outcome: DshProbeOutcome.authenticationRequired,
        httpStatus: 401,
      ),
      404 => const DshProbeResult(
        outcome: DshProbeOutcome.notDshSurface,
        httpStatus: 404,
      ),
      _ => DshProbeResult(
        outcome: DshProbeOutcome.unexpectedResponse,
        httpStatus: status,
      ),
    };
  }
  if (_isEnvelopeDecodeFailure(error)) {
    return const DshProbeResult(outcome: DshProbeOutcome.unexpectedResponse);
  }
  if (_isDeadline(error)) {
    return const DshProbeResult(outcome: DshProbeOutcome.unreachable);
  }
  if (_isTlsFailure(error)) {
    return DshProbeResult(
      outcome: DshProbeOutcome.certificateNotTrusted,
      ambiguity: _namesCertificate(error)
          ? DshProbeAmbiguity.none
          : DshProbeAmbiguity.tlsHandshakeUnspecified,
    );
  }
  if (error.message.startsWith('transport failure')) {
    return const DshProbeResult(outcome: DshProbeOutcome.unreachable);
  }
  return const DshProbeResult(
    outcome: DshProbeOutcome.unknown,
    ambiguity: DshProbeAmbiguity.unrecognizedFailure,
  );
}

final RegExp _httpStatusPattern = RegExp(r'^HTTP (\d{3}) ');

int? _httpStatusOf(String message) {
  final RegExpMatch? match = _httpStatusPattern.firstMatch(message);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// A 2xx body the transport could not decode as a JSON-RPC envelope, or an
/// envelope carrying an unexpected `rpcId`.
bool _isEnvelopeDecodeFailure(DshTransportException error) =>
    error.message.startsWith('invalid server-response') ||
    error.message.startsWith('rpcId mismatch');

bool _isDeadline(DshTransportException error) =>
    error.message.startsWith('request deadline') ||
    error.cause is TimeoutException;

bool _isTlsFailure(DshTransportException error) {
  final Object? cause = error.cause;
  if (cause is HandshakeException || cause is TlsException) return true;
  // Cronet surfaces its certificate errors as `ClientException` messages
  // (`net::ERR_CERT_*`), so the text is the portable signal.
  final String text = error.toString().toLowerCase();
  return text.contains('handshake') ||
      text.contains('err_ssl') ||
      text.contains('err_cert') ||
      text.contains('certificate');
}

bool _namesCertificate(DshTransportException error) =>
    error.toString().toLowerCase().contains('cert');
