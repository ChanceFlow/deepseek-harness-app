# Agent Note: HTTP/3 transport — embedded Cronet engine by default on Android

Status: implemented

## Problem

The RPC leg rode dart:io `HttpClient` (`IOClient`), which speaks HTTP/1.1
only — the gateway's Caddy edge has HTTP/3 (QUIC, UDP 443) enabled, so
browsers benefit immediately while this client cannot. dart:io will not
gain h2/h3 ([dart-lang/sdk#38595](https://github.com/dart-lang/sdk/issues/38595)
closed; the Dart team's sanctioned path is `package:http` with platform
engines), and the engine swap must not resurrect the WebSocket seam's
old problems ([transport hardening](2026-08-21-transport-hardening-connect-timeout-compression.md)):
the WS leg stays pure dart:io, untouched.

## Decision

Android RPC rides embedded Cronet via `cronet_http`; everything else keeps
today's path.

- `app/lib/di/http_engine.dart` owns the choice: `dshHttp3Engine()` builds
  `CronetEngine.build(userAgent: 'dsh-android/$kDshAppVersion http3')` +
  `CronetClient.fromCronetEngine(engine, closeEngine: true)` on Android,
  returns null elsewhere and on any construction failure. The factory is
  deliberately in `app/lib/di/`, not `packages/network`: `cronet_http` is
  an Android Flutter plugin, and the import gate keeps network
  flutter-free. `dshRpcClientProvider` injects it; `ref.onDispose` closes
  the engine when the backend configuration goes away, so engine lifetime
  equals backend lifetime.
- **Default on, no build flag.** The app has no remote config, so a
  `--dart-define` kill switch only re-labels "rebuild to roll back" — the
  rollback for default-on is a dependency bump or revert. Fallback is
  structural: construction failure → null → the unchanged `IOClient`
  default; QUIC is opportunistic (Alt-Svc upgrade, silent h2/h1 fallback
  when UDP is blocked), so no client-side protocol fallback exists.
- **Embedded, never GMS.** Release builds pass
  `--dart-define=cronetHttpNoPlay=true` (`cronet-embedded`, no
  `play-services-cronet` artifact) — the F-Droid channel stays clean and
  GMS-less devices still get Cronet; the price is MB-level APK growth per
  ABI, accepted on the fat APK.
- **Observability by UA.** The engine UA (`dsh-android/<version> http3`)
  differs from dart:io's `Dart/x.y`, so the Caddy access log reads
  h1/h2/h3 share per UA group — the protocol-hit metric the issue asked
  for, with no client telemetry.
- Timeout semantics: Cronet has no dart:io `connectionTimeout` equivalent,
  so connection establishment is bounded best-effort only on this path;
  the standing no-request-deadline rule (compaction runs unconstrained)
  is unchanged.

## Alternatives considered

- **`--dart-define` grayscale flag (the issue's original proposal)**:
  rejected — with no remote config the switch's only power is choosing
  at build time what a rebuild changes anyway; it would fork the tested
  surface into two shapes. Structural fallback covers the safety need.
- **GMS Cronet mode** (default of `cronet_http`, no APK cost): rejected —
  capabilities float with Play services, GMS-less devices fall back to
  dart:io, and the GMS artifact taints the F-Droid channel.
- **Factory inside `packages/network`** (the issue's snippet): rejected —
  `cronet_http` is a Flutter plugin; the import gate forbids network →
  flutter, and `lib/di/` is the sanctioned home for network-type wiring.
  The issue's `CronetClient()` constructor also no longer exists in
  cronet_http 1.9.0 — `fromCronetEngine` is the current shape.
- **`cupertino_http` for iOS/macOS**: deferred — this repository has no
  `ios/` runner; the dependency would be dead weight until one exists.
- **Per-request fallback from Cronet to dart:io on transport errors**:
  rejected — per-request failures already surface as
  `DshTransportException` and ride the connection manager's backoff;
  layering engine fallback into request paths would multiply the failure
  modes the 2026-08-21 note removed.

## Consequences

- Known risk (upstream, unfixed in cronet_http 1.9.0):
  [dart-lang/http#1217](https://github.com/dart-lang/http/issues/1217) —
  with QUIC enabled, Cronet's built-in DNS resolver fails
  `ERROR_HOSTNAME_NOT_RESOLVED` on some cellular networks and in
  background isolates; 1.9.0 has no `useBuiltInDnsResolver` switch. This
  is a request-level failure, not a protocol fallback: affected devices
  cannot reach the backend on those networks until the bump to 1.10.0
  (which carries the fix and the DNS knobs) ships. Watch the changelog
  and bump early.
- Certificate validation is strict with no bypass: self-signed test
  gateways fail opaque (indistinguishable from "h3 unreachable"). Real
  certificates or an installed CA are prerequisites for grayscale
  verification; cleartext dev paths are unaffected
  (`android:usesCleartextTraffic="true"`).
- The shipped APK carries the embedded Cronet library: `libcronet.143.0.7445.0.so`
  measured at 6.5 MB (arm64) / 4.2 MB (armeabi-v7a) / 7.2 MB (x86_64)
  uncompressed — the fat APK grows by roughly that payload. Accepted; the
  GMS alternative is not viable at all under this toolchain (next bullet).
- **GMS mode cannot build here, which settles embedded-only by force:**
  with `cronet_http` in the graph, the default GMS chain
  (`play-services-cronet` → `cronet-api:141` → `cronet-shared:141`) puts
  two libraries in the same `org.chromium.net` namespace, which AGP 9's
  manifest merger rejects as a hard error — every Android build (dev and
  release) must pass `--dart-define=cronetHttpNoPlay=true`. The embedded
  chain ships unique namespaces (`cronet_embedded`/`cronet_shared`/…)
  and builds clean; verified by the debug build smoke.
- Engine disposal rides the provider's autoDispose: an in-flight RPC at
  dispose time fails with a transport exception, the same settlement
  shape as the WS teardown.
