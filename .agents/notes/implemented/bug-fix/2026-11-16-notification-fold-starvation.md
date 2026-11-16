# Agent Note: A notification-fold burst no longer starves the UI isolate

Status: implemented

## Problem

Build `1661` (source `f68f71f`) reported an ANR: input dispatch waited 5000 ms
on a MotionEvent DOWN while the Android main thread was runnable, holding 31
frames in `libapp.so`. The release snapshot strips Dart symbols, so the report
could not name them. The stack was still recoverable: rebuild the same commit
without `--split-debug-info` and read the unstripped AOT intermediate at
`.dart_tool/flutter_build/<hash>/arm64-v8a/app.so`. Its VM stubs land exactly on
the trace's addresses (`InvokeDartCode` `0x76dc6c`, `AllocateObjectParameterized`
`0x76e874`), so the rebuilt code layout is the shipped one; the ELF build IDs
differ between builds, the stub addresses do not.

The 31 frames were one chain:

```text
#00 AllocateObjectParameterized
#01 SessionSummary.workspaceLabel      session.dart:101
#02 SessionSummary.displayTitle        session.dart:112
#03 SessionSummary.workspaceContext    session.dart:121
#04 _decisionFor                       working_sessions_fold.dart:132
#05 foldWorkingSessions                working_sessions_fold.dart:106
#06 AppNotificationCenter._reconcileWorking  app_notification_center.dart:286
#07 AppNotificationCenter._onSessions        app_notification_center.dart:184
... stream delivery, #27 _microtaskLoop
```

`ChatRepository.observeSessions()` materialised the whole roster on every
underlying update: `combineLatest3` converted per event, and the conversion
copied every `SessionSummary` twice (archived fact, pending fact) — O(roster)
objects per update. The center then folded every row on every delivery,
formatting each title and workspace label (a `RegExp` split plus a reversed
iterable) even for idle rows that could only fold to `gone`. A reconnect storm
replays many session updates; stream delivery is a microtask chain, so each
update became another full fold before input could run.

## Decision

- **The roster is a latest-state stream.** `coalesceLatest` in
  [state_stream.dart](../../../../flutter/packages/harness_adapter/lib/src/state_stream.dart)
  publishes at most the newest value per event-loop turn. It flushes from a
  timer, not a microtask: the source's own delivery is a microtask chain, so a
  microtask flush runs between two source events and coalesces nothing. The
  timer runs after that chain drains and leaves the event loop a turn to
  dispatch input. `observeSessions()` combines the three source streams into a
  cheap tuple first, coalesces it, and maps the roster only then, so the
  O(roster) materialisation happens once per turn instead of once per update.
- **The fold skips rows that cannot own a notification.** `_reconcileWorking`
  folds the union of applied rows and rows with `running`,
  `pendingInteraction`, `completed`, or `blank`; an idle, unapplied row can only
  fold to `gone`, and no longer pays for title and workspace formatting. The
  full id set still drives the cancel pass, so deleted or archived rows are
  cancelled exactly as before.
- **Equal rosters are not folded again.** A fresh archived set or a re-published
  pending map produces the same roster; the center returns before the folds. The
  first snapshot is always folded because it is the transient detector's
  baseline, even when it is the empty roster.
- **The sampled label path allocates less.** `workspaceLabel` shares one
  separator `RegExp` and scans by index instead of materialising
  `segments.reversed`; the getter's semantics are unchanged.

## Alternatives considered

- **Move the fold or the adapter decode to an isolate.** The adapter's streams,
  the notifier's platform callbacks and the detector's state cross the isolate
  boundary; that is a large re-architecture for work bounded by the two changes
  above.
- **Debounce in the center only.** The center is downstream of the O(roster)
  materialisation; the adapter would still copy the roster twice per source
  event and queue one mapped list per event.
- **Keep every intermediate snapshot.** Unbounded per-update folding is the
  defect; a state roster's intermediate values have no consumer. The one edge
  notifications need is the level `completed` bit the adapter already folds; a
  completion superseded by a new turn within one turn is deliberately not
  announced.
- **Lengthen the input timeout or disable notifications.** Neither removes the
  UI-isolate work; the freeze stays and the report gets quieter.

## Consequences

- A reconnect or resync burst costs one O(roster) fold per event-loop turn, with
  per-row work proportional to rows that actually hold a notification. A normal
  single update is unchanged: one roster per turn, one fold.
- The center sees the latest roster per turn, so a session that starts and
  settles inside one turn collapses to its final state. The level facts
  (`running`, `pendingInteraction`, `completed`) drive the rows; a rapid
  complete-then-restart may not raise a completion toast (the working fold also
  shows no done row for it).
- The earlier log-write hypothesis did not cause this ANR
  ([the write-off-caller note](2026-11-14-diagnostic-write-off-caller.md)); the
  symbolised stack is the notification fold. That change remains correct for
  its own captures.
- The symbolisation recipe is reproducible: rebuild the reported commit without
  `--split-debug-info`, then symbolise against the intermediate `app.so`
  symtab. The operations ring remains the on-device path for a report whose
  build cannot be rebuilt ([the operations-ring note](../feature/2026-11-16-previous-run-operations.md)).
- Tests pin coalescing of a burst, per-turn delivery and error pass-through
  ([state_stream_test.dart](../../../../flutter/packages/harness_adapter/test/state_stream_test.dart)),
  a synchronous status burst through the real repository
  ([session_status_event_test.dart](../../../../flutter/packages/harness_adapter/test/session_status_event_test.dart)),
  a 500-row idle roster beside an active row
  ([app_notification_center_test.dart](../../../../flutter/app/test/notifications/app_notification_center_test.dart)),
  and blank-segment label fallback
  ([session_summary_test.dart](../../../../flutter/packages/domain/test/model/session_summary_test.dart)).
