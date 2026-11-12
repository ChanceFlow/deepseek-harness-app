# Agent Note: A pending approval or plan review owns a cancellable row

Status: implemented

## Problem

The shade kept "Needs your input" rows after the request was answered
elsewhere. Approvals and plan reviews were posted with an in-process counter
id and no tag. The session snapshot carries the raw waiting fact
(`SessionSummary.pendingInteraction`), so the center saw the request clear
when it was answered in the app, on the web, or on another client, but a
counter id names no row to cancel. The ongoing work row and turn completions
were already state-reconciled through a deterministic `(id, tag)`; approvals
and plan reviews were the only family that outlived its fact.

## Decision

- **Deterministic pending identity.** `pendingNotificationTag(backendId,
  sessionId)` is `'$backendId/$sessionId/pending'`; `pendingNotificationId`
  is the shared FNV-1a hash of that tag, masked int32-positive. The suffix
  gives the pending row an identity distinct from the ongoing/done row, so
  both coexist and a cancel hits exactly one. The work row's identity is
  byte-identical to before (pinned 449815053 for `b1/s1`).
- **The notifier posts and cancels that row.** `SystemNotifier.show` posts
  approvals and plan reviews with the pending `(id, tag)` and
  `onlyAlertOnce: true`: a re-show while the same interaction still waits
  does not alert, while a post after `cancelPending` is a fresh row and does
  alert. The post records the pending row in the ledger. `cancelPending`
  cancels exactly the session's pending row, leaving the work row untouched.
  `clearUnconfirmedRows` cancels both rows for every recorded session.
- **The ledger records row families.** One entry per session carries `work`
  (default true) and `pending` (default false) flags; the entry is evicted
  when neither row is recorded. The stored JSON keeps the original
  `backendId`/`sessionId` fields and writes a flag only when it differs from
  the pre-pending defaults: a build predating this change reads every entry
  it wrote, and a missing flag decodes as its default.
- **The center cancels from session state.** `AppNotificationCenter` records
  the interaction a dispatched system row names, then each reconcile
  derives the desired pending row from each root session's raw
  `pendingInteraction`. A tracked row is cancelled when the session no
  longer waits on that interaction or waits on a different one. The diff runs
  before the detector routes the snapshot's new event, so an
  approval→plan-review change cancels the old row and posts the new one.
  `dispose` and the notifications-off path cancel tracked pending rows too.
- **The alert follows the raw waiting fact, not display suppression.** While
  the app is foregrounded, the work-session fold suppresses the watched
  session's silent work row. The pending row is the shade's alert that a
  person still owes an answer, so it follows the raw interaction: deriving
  it from the fold's suppressed state would cancel it for a watched session,
  and backgrounding later would leave only the silent work row. A watched
  foreground session therefore keeps its pending row while it waits, and
  the row is cancelled when the interaction resolves regardless of watch
  state.

## Alternatives considered

- **Cancel all notifications on resume or startup.** It has no per-row
  semantics: a resume would cancel a request still waiting, and rows posted
  later in the same snapshot would be collateral. The ledger's per-session
  sweep narrows the restart guarantee to posted rows.
- **Rely on tap or `autoCancel`.** `autoCancel` fires only when the user taps
  the row on this device. Resolution on another client never taps here —
  the reported case.
- **Use `setTimeoutAfter` expiry.** Expiry is not resolution: a long approval
  dies while still needed, and an answered one lingers until the timer.
- **Post the alert from the fold's waiting state.** The fold suppresses the
  watched session, so a foreground watch would cancel the very shade row
  that is the alert; backgrounding later would then leave only the silent
  work row. The raw fact keeps the alert independent of the display
  suppression.

## Consequences

- Each session has at most one pending row. A repeated approval updates it;
  an approval→plan-review transition cancels it and posts the new row.
  Counter ids are gone.
- A pending row is cancelled within one session snapshot of resolution — in
  the app, on the web, or on another client — watched or not.
- A restart cancels both row families for every recorded session, and the
  first snapshot re-arms what is live; no dependency or ARB key is added.
- The ledger JSON is readable both ways: a pre-pending build reads the new
  entries, and this build reads the old two-field entries.
- This note owns the pending-interaction row; it supersedes the counter-id
  claim in [the notification center note](../feature/2026-08-20-notification-center.md)
  and [the ongoing working notifications note](../feature/2026-08-29-ongoing-working-notifications.md).
  Their other decisions stand.
- Tests pin the pending key values, the ledger's per-family persistence and
  two-way JSON compatibility, the notifier's pending ids, tags and cancel,
  and the center's cleared, changed, unchanged, session-gone, dispose,
  notifications-off and watched-foreground transitions.
