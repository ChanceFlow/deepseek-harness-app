# Agent Note: Host reachability probe — name why a dsh address does not answer

Status: implemented

## Problem

Adding or editing a host validates URL syntax only. A wrong address, a
stopped gateway, a gateway whose upstream is down, an `https://` host whose
certificate Android cannot verify, and a deployment that demands
authentication all end the same way: silence, then an empty session list.
`describeBackendError` classifies store errors (malformed URL, duplicate id)
and has nothing to say about reachability, so the host sheet cannot tell the
user which failure they have.

## Decision

`flutter/app/lib/di/dsh_reachability.dart` owns one bounded probe and its
classification; the UI owns only the sentence.

- **Probe call: `settings/describe`.** One real public-plane RPC through the
  existing `DshRpcClient` seam, with an 8s request deadline
  (`kDshReachabilityProbeTimeout`). Against the live host
  (`http://127.0.0.1:8102`) `settings/describe` with the empty
  `{"args":{}}` wrapper answers `200` and `result.ok: true`; `session/list`
  answers the same wrapper only as a `gateway/arguments-invalid` business
  error, so it proves liveness through a rejection. `settings/describe`
  needs no arguments and is the call the Settings surface itself makes.
  `/healthz` is on the loopback-only admin plane and unreachable from a
  phone, so it is not a probe.
- **Seven-class outcome.** `DshProbeOutcome`: `reachable` (a well-formed
  envelope, including a business error), `unreachable` (refused / DNS /
  deadline), `certificateNotTrusted`, `authenticationRequired` (HTTP 401),
  `notDshSurface` (HTTP 404 — something answered, not a dsh),
  `unexpectedResponse` (other non-2xx, or a body that is not an envelope),
  and `unknown`. `DshProbeAmbiguity` records residual doubt instead of
  guessing: a TLS handshake that names no certificate, and an unrecognized
  exception.
- **Transport reuse.** `buildProbeTransport` mirrors `dshRpcClientProvider`:
  `https` plus the per-host opt-in rides `trustedHostRpcClient` (the dart:io
  certificate override for that exact host); else the shared Cronet engine;
  else an owned `IOClient`. The trust flag is an argument, not a registry
  lookup, because the sheet probes URLs the registry does not contain yet.
  Unlike the family seam the probe always owns a closeable client.
- **UI.** `BackendReachabilityCheck` (`lib/ui/settings/backend_reachability.dart`)
  sits after the certificate-trust toggle in `_BackendSheet`. It runs only
  on an explicit **Test connection** tap, shows a bounded in-progress row,
  then the classified sentence; `certificateNotTrusted` points at the
  toggle above. A failed probe never gates the Save button and the sheet
  says so.
- **401 is honest about both fences.** The pinned `dsh web` host answers
  `401 unauthorized` with `dsh web authentication required; reopen the URL
  printed by dsh web` (verified on `:3080`), and the separately deployed
  `dsh-go-gateway` can demand `DSH_GW_AUTH`; both classify as
  `authenticationRequired`, never as unreachable.

## Alternatives considered

- **Probe on save:** rejected — persistence would depend on a network call
  the user cannot bypass, and a host must be configurable while offline.
  The explicit tap also tests an address before it is committed.
- **`session/list` as the probe:** rejected — it answers the empty wrapper
  only with `gateway/arguments-invalid`, a weaker signal than a real result.
- **Reporting HTTP 404 as unreachable:** rejected — a 404 proves a server
  answered; it is its own class so the UI can say "not a dsh".
- **Folding TLS failures into unreachable:** rejected — the per-host trust
  toggle is the remedy and can only be pointed at if the class is separate.
- **Declaring the result in `packages/domain`:** the purist home, but this
  change's scope excludes `flutter/packages/**`. The model in `lib/di/`
  carries no wire vocabulary, so the UI stays inside the import gate.
- **A typed HTTP status on the transport seam:** deferred — adding
  `statusCode` to `DshTransportException` is a `network` change outside
  this scope. The classifier reads the status the seam stamps into the
  exception message.

## Consequences

- The classifier couples to `HttpDshRpcClient`'s message format
  (`HTTP <status> for <path>`); a typed status field is the cleaner seam
  and the follow-up if that format moves.
- `providers.dart` re-exports `package:network/dsh_exceptions.dart` so
  tests build transport failures without importing `network` directly.
- Unit tests stub `DshRpcClient` for every class; widget tests drive the
  sheet's in-progress → classified flow and prove a failed probe still
  saves. No unit test opens a socket.
- New ARB keys land in both locales.
