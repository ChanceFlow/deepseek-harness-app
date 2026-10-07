# Agent Note: Background jobs observe their output and can be stopped

Status: implemented

## Problem

The phone could see that a background job existed and how it was doing, and
nothing more. `job/list` fed the header pill and the sheet, but the sheet was a
snapshot taken when it opened — a job that settled while the sheet was up kept
its old row — and two capabilities the pinned host serves had no client at all:

- `job/follow` (`packages/api/job-controller/src/index.ts`,
  `@Remote({ mode: 'stream' }) follow`), the per-job retained-output
  observation. Without it, a failed build reported `exit code: 1` and no way to
  read why.
- `job/kill`, the human stop. The web client's two-press stop is the only
  affordance that lets a person end a job the model started; a phone user had
  to wait it out.

`JobView` also carried `owner`, `progress`, and the retained-output window
(`total`, `earliest`), none of which the decoder read — so a live row could not
show the producer's progress line and nothing could tell an expandable job from
a finished one with nothing retained.

## Decision

Take both methods from the pinned contract and mirror the reference client's
list semantics.

- `DshRpcEndpoints.jobKill` joins the registry and the invoker's
  `request`-wrapped set, so the call site passes `{sessionId, jobId}` and the
  wire record is `{'request': {...}}`. `job/follow` stays a literal, like
  `job/list`: the wire-pin gate compares unary registrations, so a stream
  constant would read as a client-only name (docs/spec.md §4.6).
- `domain/model/jobs.dart` gains `JobOutputWindow`, `JobOutputChunk`, and the
  sealed `JobOutputFrame` (`opened` / `output` / `status`); `JobView` gains
  `owner`, `progress`, and `output`. `decodeJobFollowFrame` and `decodeJobView`
  live in `dsh_wire_types.dart`, and the reducer's `session/jobs` row fold now
  delegates to the one `decodeJobView` mapping — a malformed row is reported and
  dropped, never silently defaulted.
- One observation per `(session, job)`, reference-counted by its subscribers:
  the sheet opens it on expand and cancels on collapse, so a phone stops
  draining the host stream when a row folds. `output.next` advances a resume
  cursor, and a re-expansion passes it as `from` instead of replaying the
  retained head. The rendered tail is bounded at 128 KiB of UTF-16 code units
  and trimmed at a surrogate boundary; a trim, a `lossy` frame, a chunk's
  `gapBefore`, or an anchor past `earliest` all raise the retention notice.
- The sheet follows a roster stream injected by the route
  (`ChatRoute` → `ChatScreen` → `ChatHeaderActions` → `JobListAction`), with the
  header's own snapshot as the first-frame seed. The reference's sections come
  with it: live rows first in start order, the settled tail folded behind its
  count while live work exists, and only a live row or one with retained output
  expanding.
- The stop is two-press with a three-second arm window. An admitted kill stays
  pending until the roster stream moves the row off `running`: the unary reply
  and the roster frames have no cross-carrier ordering, so re-enabling early
  would offer a duplicate kill. A refusal shows a four-second hint and leaves
  the row to the roster.
- The copy control copies the job's label (the command), never its output —
  the reference's `copyText={job.label}`.

## Alternatives considered

Keep the sheet's snapshot list and refresh only on reopen: rejected, because the
reference's stop contract depends on watching the roster settle, and a job that
finishes while the sheet is open is exactly when a person is looking at it.
Watch `chatUiStateProvider` from inside the sheet instead of injecting the
roster stream: rejected, because the sheet outlives the header's rebuilds but not
the screen's data source, and a bare `ChatScreen` pump (which owns a literal
state, not the provider) would render an empty sheet.
Poll `job/follow` from a timer: rejected — the host pushes on append, and a poll
interval would either waste the radio or add latency the reference does not have.
Buffer the whole retained ring and render it: rejected as unbounded on a phone;
the reference bounds its render tail for the same reason.
Render a failed `job/follow` as a failed turn: rejected, because the job is
running and the observation is transient — the panel shows the interruption
above whatever output arrived.

## Consequences

`declared 54 / upstream 125 / identical 52 / missing 73`. The sheet now reflects
lifecycle changes that arrive while it is open, a running job can be stopped
from the phone, and an expandable row streams real output with its retention
gaps named. The two-press stop and the folded settled section are deliberate
behavior changes from the one-tap flat list that preceded them — the
`chat_screen_test` jobs case asserts the folded section now. `job/follow` joins
the documented literal-opened streams the wire-pin gate cannot compare.
