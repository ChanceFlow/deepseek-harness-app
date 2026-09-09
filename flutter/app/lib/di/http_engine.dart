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
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../config.dart';

CronetEngine? _sharedCronetEngine;

CronetEngine? _getCronetEngine() {
  if (!Platform.isAndroid) return null;
  if (_sharedCronetEngine != null) return _sharedCronetEngine;
  try {
    return _sharedCronetEngine ??= CronetEngine.build(
      userAgent: 'dsh-android/$kDshAppVersion http3',
    );
  } catch (_) {
    return null;
  }
}

/// Resets the shared CronetEngine instance (used in tests).
@visibleForTesting
void resetCronetEngineForTesting() {
  _sharedCronetEngine = null;
}

/// Allows mocking or stubbing the HTTP engine builder in tests.
@visibleForTesting
http.Client Function()? customHttpEngineBuilder;

/// Returns the HTTP/3-capable engine, or null when the platform default
/// should be used (non-Android hosts, or engine construction failure —
/// e.g. a GMS-mode build on a device without Google Play Services).
///
/// The engine carries a distinctive `User-Agent` (for example
/// `dsh-android/1.2.3 http3`) while the dart:io default is `Dart/x.y`, so
/// the gateway's Caddy access log attributes this client's traffic per UA
/// group and reads the h1/h2/h3 protocol share from its protocol field.
///
/// The underlying [CronetEngine] lives for the app's process lifetime and is
/// shared across clients; [closeEngine] is set to false so closing a client
/// wrapper marks it closed without invoking [CronetEngine.close], which
/// Chromium rejects with `IllegalStateException: Cannot shutdown with running requests`
/// if any request is currently in-flight.
///
/// Cronet request configuration has no dart:io `connectionTimeout`
/// equivalent, so the flag-on path bounds connection establishment on a
/// best-effort basis only; the standing "no request deadline" rule
/// (long-running RPCs like compaction stay unconstrained) is unchanged.
http.Client? dshHttp3Engine() {
  final override = customHttpEngineBuilder;
  if (override != null) return override();
  final engine = _getCronetEngine();
  if (engine == null) return null;
  try {
    return CronetClient.fromCronetEngine(engine, closeEngine: false);
  } catch (_) {
    return null;
  }
}
