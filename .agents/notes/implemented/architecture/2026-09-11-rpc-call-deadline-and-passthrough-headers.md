# Agent Note: Passthrough request headers and a per-call RPC deadline

Status: implemented

## Problem

Two gaps in the transport layer, discovered together because both are
per-request facts the network package had no seam for:

1. **No request-header seam.** `HttpDshRpcClient` hardcoded a single
   `Content-Type` header and `WebSocketDshEventSocket` called
   `WebSocket.connect` with none. A caller with a header to send (an
   authenticated reverse proxy in front of a `dsh web` host, a tracing
   header) had no way to supply it short of forking the client.
2. **No request deadline.** `kDshRpcConnectTimeout` bounded TCP/TLS
   establishment only; the request itself was deliberately unbounded so
   long-running RPCs (compaction) survive. A host that accepted the
   connection and then stopped answering left every short RPC — session
   list, settings, credentials — hanging, with a spinner turning forever
   and no error surface.

## Decision

- **`headers`, passed through and never interpreted.** Both clients take
  an optional `Map<String, String> headers = const <String, String>{}`:
  `HttpDshRpcClient.headers` (constructor), `WebSocketDshEventSocket.headers`
  (constructor, forwarded to `WebSocket.connect`'s own `headers:`). The
  default is empty, so every existing call site is byte-identical. The
  network package only copies what it is handed; which header means what is
  the caller's vocabulary, and the import gate keeps it out of this package.
- **Header precedence: caller wins, `Content-Type` cannot be dropped.**
  `_mergeHeaders` starts from the JSON content type and overlays the caller
  map, matching `Content-Type` case-insensitively: a caller entry replaces
  the default (so a caller can override it) but a differently-cased key can
  no longer append a second, invalid content type. The merged map is
  computed once at construction and copied, so later mutation of the
  caller's map cannot leak into a live client.
- **Per-call deadline on the RPC seam.** `DshRpcClient.call` gained
  `{Duration? timeout}`; `null` means deliberately unbounded.
  `HttpDshRpcClient` wraps the whole exchange (request through response
  body) in `.timeout(timeout)` and converts `TimeoutException` into
  `DshTransportException('request deadline <n>ms exceeded for <path>', cause)`,
  so upper layers keep their existing error handling.
- **The adapter states every call's policy.** `DshRemoteInvoker.call` and
  `HarnessRepositoryImpl._call` take the deadline as a *required* argument,
  forcing each of the ~40 call sites to name one: `_shortCallTimeout`
  (30 s) for short/unary RPCs, or the explicit `_noCallDeadline` for
  `session/prompt`, `session/updateQueue`, `commands/execute`, and
  `subagents/prompt`. A required argument is the fail-loud choice: adding a
  call site cannot silently inherit a deadline (which would kill an exempt
  call) or silently lose one. `DshConnectionManager` also bounds its `$events`
  ready-frame handshake (30 s) so a silent host fails the generation into the
  existing backoff instead of stalling readiness
  ([the handshake](../bug-fix/2026-09-11-drops-routes-the-pinned-host-does-not-register.md)).
- **30 s, justified by the seam.** These RPCs answer in well under a second
  against a healthy local host; 30 s absorbs a slow network or a VPN
  without waiting on a host that is never going to reply, and sits far
  below the multi-minute work the four exemptions cover.

## Alternatives considered

- **A per-request header callback on the transport** (the transport asks a
  closure for headers on every call): rejected — it makes authenticated
  requests a transport concept, the vocabulary this package must not learn.
- **Wiring the header map from `app/lib/di` now**: rejected for this change —
  the seam is the deliverable; supplying a value and the auth vocabulary
  that goes with it is a separate decision, and the empty default keeps
  today's behavior exact.
- **A constructor-level timeout on the RPC client**: rejected — one client
  serves both a 2 s list call and a compaction turn, so the deadline has to
  be per call.
- **An adapter-side `Future.timeout` wrapper without touching the
  interface**: rejected — the transport would keep running the abandoned
  request and cannot cancel it, so the deadline would look enforced while
  the socket stayed occupied, and the exception could not name the
  transport deadline in the package's own error type.
- **A default deadline inside `DshRemoteInvoker`**: rejected — a new call
  site could then inherit a deadline it must not have. Requiring the
  argument makes the exemption a compile-time decision.

## Consequences

- Every short RPC now fails fast with a `DshTransportException` a wedged
  host would previously have hung on; the long-running four still run
  unbounded, and a future long-running verb must pass `_noCallDeadline`
  when it is added.
- The transport remains protocol-ignorant: it forwards opaque headers and
  an opaque duration, and the dsh vocabulary stays in `harness_adapter`.
- `network` takes `fake_async` as a test-only dependency so deadline tests
  advance a fake clock instead of sleeping.
- `DshRpcClient` is a cross-package contract; every fake implementing it
  declares the new named parameter.
