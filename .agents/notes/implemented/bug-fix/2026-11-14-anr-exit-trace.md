# Agent Note: An ANR or native crash keeps the dead process's stack

Status: implemented

## Problem

A device report from build `0.4.1-alpha.1639` carried five ANR process exits in
27 minutes and one native crash (`status` 6, SIGABRT). Each ANR was recorded
as `Previous process exit: anr — Input dispatching timed out (... Waited
5000ms for MotionEvent(action=DOWN))`, and each record held only the platform's
reason, description, importance and status. The stack that would name the
blocked thread never reached the Dart error hooks — an ANR kills the process
before they run — so the report explained that the app froze but not where.

Android 11+ keeps that evidence: `ApplicationExitInfo.getTraceInputStream()`
returns the trace the system took before the death. The earlier diagnostics
decision deliberately skipped it ([diagnostics log](../feature/2026-11-12-diagnostics-log.md));
this note supersedes that one point.

## Decision

- **Trace on the worker, never the platform main thread.**
  [DiagnosticsBridge.kt](../../../../flutter/app/android/app/src/main/kotlin/com/deepseek/harness/app/DiagnosticsBridge.kt)
  runs the history query and every trace read on one daemon single-thread
  executor and answers the channel from it. The launch-time binder call and a
  decompression therefore cannot block input dispatch.
- **Choose first, read once.** Each history map adds `pid`, `hasTrace` and
  `isOwnProcess`. A new `exitTrace {timestamp, pid}` method re-finds that
  record and reads its stream inside `use {}`. Dart asks only for the exit it
  is about to record (`recordProcessExitReasons`), so a launch reads at most
  one trace. Selection is limited to the app's own process: a package's
  history also holds WebView sandboxed-renderer exits, whose routine teardown
  is cleanup, not this app's death, and a foreign record's trace is never
  probed or read.
- **Bounded and attributed.** The read detects gzip by magic, decodes UTF-8
  leniently, caps the decompressed bytes at 64 KiB, and parses the
  `----- pid <n> at … -----` / `----- end <n> -----` blocks, keeping only the
  record's pid or a block whose `Cmd line:` names this package (a dump without
  block headers keeps its bounded head instead). A binary (protobuf tombstone)
  answer or an unreadable stream is null, not megabytes of noise; a cut answer
  ends with the truncation marker. Every path catches `Throwable`; below API 30
  the answer is null.
- **The entry owns the trace.**
  [error_log_entry.dart](../../../../flutter/app/lib/logging/error_log_entry.dart)
  gains a nullable `trace` that persists in JSON and renders as a fenced
  `System Trace` block, capped idempotently at 64 KiB characters.
  [exit_reasons.dart](../../../../flutter/app/lib/logging/exit_reasons.dart)
  decodes `pid`/`hasTrace` tolerantly, exposes `readExitTrace`, and records
  `traceChars`/`traceTruncated` beside the platform facts. The read has a 3 s
  deadline: a stalled platform worker records the exit without a trace instead
  of withholding the record. A null trace leaves the record exactly as a build
  without this capability writes it.

## Alternatives considered

- **Keep reason and description only.** That is the status quo this note
  changes: it proves the app froze and cannot say which thread held the
  window, so every report stays undiagnosable without a PC.
- **Read every history record's trace at launch.** Ten large streams per
  launch, nine discarded, and a record may describe another process's data;
  the selected-record read keeps the same evidence for one stream.
- **Store the raw stream, base64 tombstone included.** The log is a bounded
  on-device ring a user copies by hand; an opaque binary blob makes it larger
  and no more readable. The bounded text blocks are the useful part.
- **Adopt a crash reporter.** A dependency and a remote pipeline for evidence
  the collector already stores on the device, against the decision that the
  report travels with the phone ([diagnostics log](../feature/2026-11-12-diagnostics-log.md)).

## Consequences

- The next ANR or native-crash report carries the per-thread stacks of the
  dying process, so the blocked thread can be identified from the device.
- On API 31+ a native tombstone is protobuf: the note records that the record
  had a trace but stores no trace, because decoding that schema is a separate
  commitment. API below 30 is unchanged.
- The log can grow by up to 64 KiB per recorded abnormal exit, at most one per
  launch; an absent channel, a refused query or a malformed answer records the
  exit without a trace.
- [exit_trace_test.dart](../../../../flutter/app/test/logging/exit_trace_test.dart)
  drives the real collector and channel seam: trace on the entry and in the
  exported report, no read for a deliberate or traceless exit, a platform
  error still records the exit, and the cap/marker round-trip.
