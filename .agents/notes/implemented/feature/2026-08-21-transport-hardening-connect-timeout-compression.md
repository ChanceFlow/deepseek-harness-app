# Agent Note: Transport hardening — explicit compression, bounded connect and close

Status: implemented

## Problem

The downlink WebSocket seam in `flutter/packages/network` sat on
`package:web_socket_channel` with no control over its transport profile:
compression was negotiated only through dart:io defaults (implicit, untested),
and the seam's async*-generator `connect()` could hang forever on two paths —
a subscription cancel never unwinds an `await for` over a live dart:io
`WebSocket` stream, so teardown blocked until the peer answered the close
frame; and the HTTP RPC client used a bare `http.Client()` whose TCP connect
has no bound, so a black-holed network froze RPC futures indefinitely.

## Decision

The network package owns its transport profile explicitly:

- `WebSocketDshEventSocket` is rewritten over raw dart:io `WebSocket` with
  `compression: CompressionOptions.compressionDefault` passed explicitly
  (the same default dart:io uses, now pinned by a test asserting the
  `Sec-WebSocket-Extensions: permessage-deflate` offer). The
  `web_socket_channel` dependency is removed.
- `connect()` returns a `StreamController`-backed stream, not an async*
  generator: `onListen` performs the connect and fires `onOpen`, `onCancel`
  cancels the socket subscription and closes with a 2 s bound
  (`_closeQuietly`). Subscription cancel therefore settles even when the
  peer never answers the close frame.
- `HttpDshRpcClient` builds `IOClient(HttpClient()..connectionTimeout = 10 s)`
  when no client is injected — a connection-establishment bound only, never
  a request deadline (`kDshRpcConnectTimeout`).
- No request deadline is added anywhere: a full compaction can legitimately
  run over a minute
  ([command-dispatch-failure](../bug-fix/2026-08-20-command-dispatch-failure-prompt-fallback.md)
  records that axis and the web remote path applies none either). A
  phone-path drop mid-compaction is compensated client-side by a
  one-shot retry on a fresh connection for detached bare commands
  ([compact-detached-command-lifecycle](../bug-fix/2026-08-22-compact-detached-command-lifecycle.md)).
- No keep-alive pings: dart:io 3.13's `WebSocket.pingInterval` is
  unreliable in this environment — probes with identical semantics flip
  between healthy and `goingAway`-closed based on unrelated code (a
  race between the ping deadline timer and pong handling), and a realistic
  1 s interval over a 4 s idle closes with 1001. The planned heartbeat
  feature is deferred (spec §4.2 states the current contract).

Wire contract unchanged: the same ServerRequest framing, the same
downlink-only sockets (client messages still get 1008), the same `api/*`
paths. The connection lifecycle in [spec §5](../../../../docs/spec.md) is
untouched.

## Alternatives considered

- **Keep `web_socket_channel` and use `IOWebSocketChannel.connect`**: the
  factory used by the old seam does not expose `pingInterval`, and
  compression stays implicit via dart:io defaults — exactly the untested
  state this change removes. Rejected.
- **`WebSocket.connect(customClient: HttpClient()..connectionTimeout)`**:
  any injected `customClient` breaks pong processing in dart:io 3.13 (the
  ping deadline never resets and the socket closes with goingAway), so a
  connect bound cannot ride the WS handshake. The connection manager's
  existing stream-open timeout continues to bound the WS handshake. Rejected.
- **Whole-request timeout on RPC calls**: rejected — it would kill
  legitimate long operations (full-session compaction ~69 s) and contradict
  the recorded no-deadline decision above.
- **dart:io `pingInterval` heartbeat (30 s)**: implemented in a probe
  branch, then dropped — the SDK races the deadline against pong
  processing; probes that differ only in prints flip between stable and
  goingAway-closed, and 200 ms/1 s intervals all fail deterministically in
  the failing shape. Not shippable as a production heartbeat. Deferred.

## Consequences

- Compression is explicit and regression-pinned: the offer test fails if a
  future SDK or dependency change stops sending `permessage-deflate`.
- RPC futures and subscription cancels have bounded worst cases (10 s
  connect, 2 s close) instead of hanging on dead peers or black-holed
  networks; the generation loop's existing 3 s stream-open timeout still
  guards the WS handshake.
- One dependency less (`web_socket_channel`); the seam is now pure dart:io.
- Dead-connection detection stays as it was (stream end/error → generation
  loss → reconnect); the heartbeat that would surface silent NAT kills
  sooner is recorded as deferred with the SDK evidence in spec §4.2.
- Behavioral change: an abandoned in-flight `WebSocket.connect` can
  complete after cancel; the socket closes immediately in that case
  (`cancelled` flag), so no frame is delivered after teardown.