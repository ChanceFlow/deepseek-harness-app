# Agent Note: The answer sheet ends with the row that opened it

Status: implemented

## Problem

The question card is a composer-seat takeover and its answer surface is a modal
sheet — a route above the transcript, pushed by the row
(`_QuestionRowState._openSheet`). The row and the route have independent
lifetimes: when the request left the seat the row was disposed, and the sheet
stayed up holding every callback of the defunct `State`. The reader's next
press on that orphaned surface ran the row's own `setState` (and, on the
report's path, read the localization through `State.context`) on a `State`
whose element is null — a release build crashed with `Null check operator used
on a null value` at `State.context`, from the pager's Next chevron
(`_continue` → the unanswered-question banner).

The seat is where this happens. `_pendingQuestion` reads the timeline while
`_continuedQuestion` reads the `userQuestions` projection, so one host event
moves a request between two differently keyed `QuestionRow`s; a host that
settles the request, and a session switch, drop it entirely.

## Decision

The sheet's lifetime is the row's, and the row's seats are inert once it is
gone.

- `_QuestionRowState` keeps the `ModalRoute` it pushed and removes it from
  `dispose` when it is still active, so a request that leaves the seat cannot
  leave a live decision surface behind. A route is removed rather than popped:
  the row targets its own surface, not whatever is on top of the navigator.
- Every seat the sheet hands back to the row (`onChoose`, `onDraftChange`,
  `onBack`, `onNext`, `onSkip`, `onDismiss`) checks `mounted` before it runs.
  The route's removal does not hide the surface in the same frame — pointer
  events are dispatched before the overlay rebuilds — so this guard is what a
  press landing in that frame meets.
- The `_settled` pop stays as it was: a dispatched answer still closes the
  surface.

## Alternatives considered

**Guards alone** — reject the press and let the sheet stay until the reader
touches it: rejected, it leaves a decision surface for a request the session no
longer has, which is the state the row's own `_settled` comment exists to
prevent, and a reader who never touches it keeps answering nothing.
**A `Listenable` the sheet listens to** so it closes itself when the row goes:
rejected — the row would hand the sheet a notifier it has to dispose in
`dispose`, and notifying a disposed `ChangeNotifier` is the same hazard with
more machinery. **Removing the route on `deactivate`**: rejected, a deactivated
element can be reinserted, and the surface would close under a live row.
**Holding the drafts in the controller**, so the sheet could outlive the row
safely: rejected — drafts are per-card UI state, and this change does not need
them to survive their card.

## Consequences

- The sheet closes with its row: a settled, re-baselined or switched-away
  request leaves the reader the composer, not a stale answer form. A reconnect
  that re-creates the row under the same request key closes the surface and
  the drafts in it; the same press reached a defunct `State` before.
- A press that lands in the removal frame is dropped, and no
  `DismissQuestionAction` or `AnswerQuestionAction` is dispatched for a request
  the session has dropped.
- The regression is pinned in
  [chat_screen_test.dart](../../../../flutter/app/test/ui/chat/chat_screen_test.dart)
  ("the answer surface ends with the row whose request left the seat"): the
  request leaves the timeline under an open sheet, the Next chevron is pressed
  in the frame the row dies in, and the test asserts no exception, no
  dispatched action, and no surface left behind.
- Related decisions stay as they are: the continued-question seat
  ([timed user questions](../feature/2026-10-07-timed-user-questions.md)) and
  the card's end on a host `cancel`
  ([forwarded-event waterfalls](2026-09-10-remote-event-waterfall-decisions.md)).
