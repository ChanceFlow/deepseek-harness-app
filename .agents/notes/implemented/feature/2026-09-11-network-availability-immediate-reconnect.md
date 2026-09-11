# Agent Note: Immediate reconnect on default-network availability

Status: implemented

## Problem

A mux generation that dies while the app is not visible is redialed by the
exponential backoff (base 500 ms, factor 2, cap 10 s) or by a lifecycle
resume. Both are guesses about reachability: the timer was scheduled from an
earlier failure and knows nothing about the network, and a resume fires only
when the app returns to the foreground — never for a Wi-Fi/cellular switch
while the app is visible. A device that regains its network after a long
background therefore waits out the cap before the first dial, and that dial
can still land on a transport that is not back.

The keep-alive foreground service keeps the socket open while work is in
flight
([background keep-alive](2026-09-11-background-keep-alive-foreground-service.md)),
so the remaining window is the idle one: no turn running, screen locked,
network gone. Android knows the moment the default network returns; the
client should not have to guess it.

## Decision

[DshConnectionManager.reconnectNow()](../../../../flutter/packages/harness_adapter/lib/src/dsh_connection_manager.dart)
is a public, immediate reconnect request wired into the existing generation
machinery rather than a second connect loop:

- Completing `_generationAbort` ends the live generation, and the connect
  loop re-dials on its next turn. A deliberate teardown is not reported as a
  handshake failure.
- Completing `_reconnectSignal` cuts a pending backoff wait short. The
  signal is consumed by that wait, so a request that arrives while a
  generation is live still skips the backoff that follows the teardown.
- The attempt sequence restarts at 0; only a backoff wait that ran to
  completion advances it.
- Before `start()` and after `stop()` the call is a no-op that changes
  nothing.

[NetworkStatusBridge.kt](../../../../flutter/app/android/app/src/main/kotlin/com/deepseek/harness/app/NetworkStatusBridge.kt)
registers `ConnectivityManager.registerDefaultNetworkCallback` and delivers
one event per default network that becomes available on the
`dsh/network_status` EventChannel. Registration runs in `onListen`,
unregistration in `onCancel`, and every sink call is posted to the platform
thread because connectivity callbacks arrive on a binder thread. Registration
reports the network that is already the default as its first `onAvailable`;
that current-state report is marked before registering, so only a network the
device gains afterwards produces a hint. Availability is the trigger, not
`NET_CAPABILITY_VALIDATED`: a dsh host on a local network without internet
access is reachable while Android still reports that network unvalidated. A
refused registration surfaces as an event error instead of a crash, and the
bridge needs `ACCESS_NETWORK_STATE`
([AndroidManifest.xml](../../../../flutter/app/android/app/src/main/AndroidManifest.xml)).
`MainActivity` calls `NetworkStatusBridge.register(this, flutterEngine)`.

[NetworkStatus](../../../../flutter/app/lib/platform/network_status.dart) is
the Dart seam: a broadcast `Stream<void>` that asks the host to register on
the first listener and to unregister when the last one cancels. Its control
leg rides `OptionalMethodChannel` and a host error envelope is swallowed, so
a widget test or desktop host with no channel sees an inert stream.

The DI layer holds one subscription and calls `reconnectNow()` on every
enabled backend's manager, so one network change moves every connection.

## Alternatives considered

- **Lifecycle resume only.** It fires when the app returns to the foreground,
  which misses a Wi-Fi/cellular switch while the app is visible and lags the
  network return by however long the screen stayed locked.
- **Periodic host reachability probes.** They spend a request per interval to
  learn what the OS already broadcasts, and their failures are
  indistinguishable from a slow host.
- **A `BroadcastReceiver` for `CONNECTIVITY_ACTION`.** The broadcast is
  deprecated, background delivery is restricted, and a receiver needs its own
  register/unregister lifecycle — the same lifecycle the network callback
  already owns while reporting a typed current fact.
- **Gating on `NET_CAPABILITY_VALIDATED`.** It drops the local-host case the
  app is built for, where the LAN has no internet but the dsh host answers.
- **A second reconnect loop outside the connect loop.** Two owners of the
  generation would race the existing one; `reconnectNow()` signals the
  existing loop instead.
- **`EventChannel.receiveBroadcastStream`.** A missing host routes
  `MissingPluginException` through `FlutterError.reportError`, which a widget
  test that only builds the dependency graph never drains.

## Consequences

- Evidence: `dsh_connection_manager_test.dart` asserts the skipped backoff
  and the restarted attempt sequence, a live generation torn down and
  redialed without consulting the retry policy, and the no-ops before
  `start()` and after `stop()`; `network_status_test.dart` asserts event
  delivery, one host registration for many listeners, unregistration on the
  last cancel, and a subscriber with no host that delivers nothing and
  reports nothing through `FlutterError`.
- The bridge holds one system callback while a listener exists and forgets a
  network on `onLost`, so a flapping capability report cannot tear down a
  fresh generation twice.
- `ACCESS_NETWORK_STATE` is a normal permission: no runtime request and no
  user prompt.
- A screen unlock that keeps the same default network still reconnects
  through the lifecycle resume path; the network callback covers the
  transitions the OS reports.
