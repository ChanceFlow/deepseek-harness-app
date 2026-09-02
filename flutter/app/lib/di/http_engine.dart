/// HTTP engine selection for the RPC transport seam: Android RPC rides
/// embedded Cronet (HTTP/2 with opportunistic HTTP/3 against the gateway's
/// Caddy edge) instead of dart:io `HttpClient` (HTTP/1.1 only).
///
/// Graceful degradation is the contract: any engine-construction failure
/// returns null and the caller falls back to `HttpDshRpcClient`'s default
/// `IOClient` path. QUIC itself is opportunistic — Cronet upgrades via
/// Alt-Svc after the first TCP request and silently falls back to h2/h1
/// when UDP 443 is blocked, so no client-side fallback exists for that;
/// only construction-time failure is caught here. Per-request failures
/// surface as `DshTransportException` through the normal path.
library;

import 'dart:io' show Platform;

import 'package:cronet_http/cronet_http.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// Returns the HTTP/3-capable engine, or null when the platform default
/// should be used (non-Android hosts, or engine construction failure —
/// e.g. a GMS-mode build on a device without Google Play Services).
///
/// The engine carries a distinctive `User-Agent` (for example
/// `dsh-android/1.2.3 http3`) while the dart:io default is `Dart/x.y`, so
/// the gateway's Caddy access log attributes this client's traffic per UA
/// group and reads the h1/h2/h3 protocol share from its protocol field.
///
/// Cronet request configuration has no dart:io `connectionTimeout`
/// equivalent, so the flag-on path bounds connection establishment on a
/// best-effort basis only; the standing "no request deadline" rule
/// (long-running RPCs like compaction stay unconstrained) is unchanged.
http.Client? dshHttp3Engine() {
  if (!Platform.isAndroid) return null;
  try {
    final engine = CronetEngine.build(
      userAgent: 'dsh-android/$kDshAppVersion http3',
    );
    return CronetClient.fromCronetEngine(engine, closeEngine: true);
  } catch (_) {
    return null;
  }
}
