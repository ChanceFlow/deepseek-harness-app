# Agent Note: The error log never writes on its caller, and connection noise folds

Status: implemented

## Problem

The device report's 100-entry ring was dominated by near-duplicate connection
entries — `Generation handshake failed: TimeoutException …` and
`DshTransportException: event stream /api/remote.mux failed …` once per
reconnect attempt — while older renderer-death and crash records had been
evicted. Each capture also encoded the whole ring and called
`writeAsStringSync(..., flush: true)` on the Flutter UI isolate, so a
connection storm wrote and fsynced from the capture caller's stack every few
hundred milliseconds. That is unnecessary jank at best and one plausible
contributor to the report's 5 s input-dispatch ANRs.

## Decision

- **Capture is memory-only; persistence is async and coalesced.**
  [error_log_collector.dart](../../../../flutter/app/lib/logging/error_log_collector.dart)
  updates memory and the stream synchronously, then marks the log dirty and
  starts one write loop. The loop yields once so a burst in the same turn
  collapses into one encode, snapshots the newest entries, and writes a temp
  file in the same directory with `flush: true` before renaming it over
  `error_logs.json`. A capture during a write only dirties the state; there is
  no timer, so the durability window is one event-loop turn. `clear()` bumps a
  persist generation so an in-flight write cannot resurrect the file, and
  `flushPersistence()` awaits the tracked write for tests.
- **Repeated connection diagnostics fold at the app sink.**
  [connection_diagnostics.dart](../../../../flutter/app/lib/di/connection_diagnostics.dart)
  is the seam both sinks in [providers.dart](../../../../flutter/app/lib/di/providers.dart)
  share. Every diagnostic still appends its breadcrumb and telemetry line;
  only the persisted entry is gated: the first occurrence in a 60 s window is
  stored unchanged, repeats are counted, and the first occurrence after the
  window stores one recap naming ` (N repeats suppressed)` and
  `suppressedRepeats`. The key is backend + context + whitespace-normalized
  message + captured error type, so two distinct failures never share a count.
  It reuses the adapter's `DiagnosticGate`, now exported from the barrel.
- **No reconnect or adapter behavior moves.** The gate observes diagnostics;
  it never suppresses a retry, a rejection, or a level.

## Alternatives considered

- **Keep the synchronous write.** It guaranteed the newest entry survived a
  kill; it also blocked the UI isolate on every capture, which is the defect.
  One event-loop turn of exposure is the cheaper trade.
- **Debounce with a timer.** A longer window would lose more on a kill and add
  a timer to cancel and flush, for no benefit over the dirty-flag loop.
- **Drop connection warnings from the log entirely.** The breadcrumbs alone
  lose the first occurrence's entry context (backend, URI, message), which is
  what makes a storm readable.
- **Gate inside `DshConnectionManager`.** That would make reconnect policy
  depend on a logging policy; the app's log sink is where the log decides what
  it stores.

## Consequences

- No disk I/O runs on a capture caller's stack; a storm costs one encode and
  one fsync per event-loop turn instead of one blocking write per entry.
- A capture killed within one event-loop turn may lose its newest entry; the
  previous synchronous write did not.
- The ring keeps the first failure of each window plus a counted recap, so
  renderer-death, ANR and crash records survive a storm; the breadcrumb ring
  keeps every attempt.
- [error_log_collector_test.dart](../../../../flutter/app/test/logging/error_log_collector_test.dart)
  pins deferred writes, coalescing, the clear race, write failure and restore;
  [connection_diagnostics_test.dart](../../../../flutter/app/test/di/connection_diagnostics_test.dart)
  pins first-emit, suppression, one counted recap, key separation and
  unconditional breadcrumbs/telemetry.
