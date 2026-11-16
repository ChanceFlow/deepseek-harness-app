# Agent Note: The previous run's last operations ride on its exit record

Status: implemented

## Problem

Build `1661`'s captured ANR trace named the hardware truth: at the moment input
dispatch timed out, the Android main thread held 29 frames of `libapp.so` — and
since Flutter 3.32 the platform and UI threads are merged on Android, so the
main thread *is* the Dart UI isolate. The five-second freeze is Dart work, not
binder, WebView, or memory pressure. The trace could not name the function
because a release build strips Dart symbols, and `libapp.so` exports only
`_kDartSnapshotText/Data/BuildId`; symbolization additionally needs a
`--split-debug-info` artifact the release pipeline does not publish.

So the report said "the UI thread ran Dart for five seconds" and nothing about
which phase. The bounded breadcrumb ring is no substitute: it records
diagnostics (connection churn), not operations (what was decoding on the UI
thread).

## Decision

- **A persisted operation ring.** [error_log_collector.dart](../../../../flutter/app/lib/logging/error_log_collector.dart)
  keeps `maxOperations` (32) chronological `HH:MM:SS.mmm [OP] <message>` lines
  and writes them to `last_operations.json` beside the error log, through the
  same async, coalesced, atomic (temp file plus rename) discipline as the entry
  ring: [addOperation] never blocks its caller. `flushPersistence()` awaits
  both writes.
- **One-shot handover.** [initialize](../../../../flutter/app/lib/logging/error_log_collector.dart)
  reads that file into `previousOperations` and deletes it, so a later
  `process-exit:` entry carries the operations of the run that actually died,
  and a run that ends deliberately leaks nothing into a later report.
  `recordProcessExitReasons` passes the list onto the entry (markdown section
  `Previous Run Operations`, plus `previousOperationsCount`); a run with no
  operations produces exactly the previous output.
- **Phase boundaries, not traffic.** The adapter records decode and resync
  phases — `resync begin/end`, `decode session/list begin … end N sessions`,
  `decode control baseline begin/end`, per-session history decode — at debug
  level on the existing diagnostic sink with `context: 'operation'`
  ([harness_repository_impl.dart](../../../../flutter/packages/harness_adapter/lib/src/harness_repository_impl.dart)).
  [ConnectionDiagnosticLog](../../../../flutter/app/lib/di/connection_diagnostics.dart)
  routes that context to `addOperation` and nothing else: no error entry, no
  breadcrumb, so the trail cannot evict the record it exists to explain.
- **Cost-gated wire evidence.** [HttpDshRpcClient](../../../../flutter/packages/network/lib/http_dsh_rpc_client.dart)
  gained an optional `onExchange` listener measured around the whole request.
  The app records `rpc <path> resp=<bytes>B <ms>ms` only when a response is at
  least 256 KiB or the exchange took at least 250 ms, and
  [WebSocketDshEventSocket](../../../../flutter/packages/network/lib/web_socket_dsh_event_socket.dart)
  reports a frame of at least 128 KiB (`mux <path> frame=<chars>B`). Both
  listeners are diagnostic only: a throwing listener is swallowed and cannot
  change a request, a stream, or a result. Lifecycle transitions record
  `app lifecycle <state>` too, so a frozen background/foreground edge is
  visible.

## Alternatives considered

- **Publish `--split-debug-info` symbols and symbolize the ANR trace.** That
  names the blocked function exactly, but it is a release-pipeline change, the
  symbols are only valid for the build that produced them, and the report a
  user copies stays readable only after an offline step. The operation ring
  answers "which phase" directly on the device with no build plumbing; the two
  are complementary, and a later pipeline change can add symbols.
- **Rely on the breadcrumb ring.** Breadcrumbs are diagnostic events; the
  freeze happens inside a decode with no diagnostic to emit. Reusing the ring
  would also let 30 connection lines evict the phases.
- **Record every RPC and every mux frame.** That inverts the cost: 32 slots
  would hold less than a second of normal traffic, and the trail would evict
  the one slow phase that matters. Cost gates keep only the expensive work.
- **Write the ring on every operation synchronously.** That reintroduces the
  UI-thread fsync this capability exists to observe.

## Consequences

- The next abnormal exit names the operations in flight: a report showing
  `decode session/list begin` then the exit, with no matching `end`, localizes
  the stall to that decode.
- The trail is bounded (32 lines), so it holds the latest phases only; a long
  quiet period before the freeze leaves earlier phases out.
- An operation is a line of text with a clock, not structured data: it is
  readable in the exported report without a decoder, which is the point.
- [previous_operations_test.dart](../../../../flutter/app/test/logging/previous_operations_test.dart)
  pins the ring cap/order, the one-shot restore and delete, the entry carrying
  the operations end to end, the JSON/Markdown round trip, and the clear race;
  the network listeners are pinned by their package suites.
