# Agent Note: Timeline loading indicator

Status: implemented

## Problem

Selecting a conversation reset the chat timeline to an empty window and
fetched the session's history asynchronously. Until the first page
arrived, the chat body read the empty state as an empty session and
rendered the EmptyHero (fish headline + "choose workspace" chip) — a
misleading "create a new session" invite while an existing conversation
was still loading, or a silent blank wait. The window carried
`isLoadingOlder` (pagination) but no signal for the initial full load.

## Decision

- **`TimelineWindow.isLoading`** (domain): a fact on the window meaning
  "the session's first full load (or a reconnect resync) is in flight".
  `hasMoreOlder`/`isLoadingOlder` keep their pagination meaning; the new
  flag distinguishes "nothing loaded yet" from "nothing to show".
- **Adapter** (harness_repository_impl.dart `_SessionState`): the
  `_SessionState` publishes `isLoading: true` at the start of
  `ensureLoaded` (before the history RPC) and clears it in `finally`, so
  both success and failure paths drop the flag. `prepareResync` resets it
  too. Frames arriving during the wait still queue behind the mutex and
  fold into the loaded snapshot.
- **Controller** (chat_controller.dart): threads `_timelineWindow.isLoading`
  into `ChatUiState.isTimelineLoading`.
- **UI** (chat_screen.dart `_timelineBody`): when the timeline is empty
  and `isTimelineLoading` is true, render a centered `CircularProgressIndicator`
  (the same pattern the subagent pane uses for its empty-and-loading
  state) instead of the EmptyHero. Once the window settles with no items,
  the EmptyHero returns for genuinely blank sessions.

## Alternatives considered

- **Reusing `isLoadingOlder`** for the initial load: rejected — the two
  waits are different states; conflating them would either flash the
  spinner on every pagination fetch or fail to cover the first load.
- **A separate `isLoading` boolean outside the window** (controller-side
  timer/heuristic): rejected — the load lifecycle is owned by the
  adapter's session state; a client-side timer would guess at wire
  latency and race the real completion.
- **A skeleton/shimmer placeholder** matching `aliasBgSkeleton`: rejected
  as a larger surface for this change — the centered loader satisfies the
  "show a wait" requirement with the app's existing pattern, and a
  skeleton can layer on later without changing the state contract.
- **A localized label under the spinner**: rejected — the app's other
  empty-and-loading panes (subagent catalog) use a bare centered loader;
  adding a string would touch the hand-managed l10n files for no parity
  gain.

## Consequences

The initial conversation load now reads as a wait instead of an empty
session: no more EmptyHero flash (or silent blank) while history fetches.
On reconnect, a resyncing non-empty session keeps its rendered rows
because the spinner only replaces the EmptyHero when the timeline is
empty — stale content never blinks out. Adapter tests assert the window
emits `[false, true, false]` across the load (and after a failed load),
the controller test threads the flag, and the widget tests pin both the
spinner and the settled EmptyHero rendering.
