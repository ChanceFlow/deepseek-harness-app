# Agent Note: A blank session's hero behind the live queue and job mirrors

Status: implemented

## Problem

Two defects met on one gesture — long-pressing a project header in the
session list, the sidebar's "create a session in this workspace" verb.

1. **The hero hid behind two chrome mirrors.** The chat body read an empty
   `ChatUiState.timeline` as "this conversation is blank" and rendered the
   empty hero (fish headline, workspace chip, agent-preset seat). The host
   republishes two live mirrors into that same list for every followed
   session: the `session/queue` snapshot and the `session/jobs` roster, and
   `job/list` yields one whole-set `rows` frame on open even when the roster
   is empty (`packages/api/job-controller/src/rows.ts`). A conversation
   nothing has happened in therefore still carries a non-empty window, and
   the body rendered a transcript with no rows in it instead of the hero.
   The long-press verb reuses its workspace's existing blank session
   (`ChatController._reusableBlankSessionId`), whose window is already warm
   from an earlier follow, so that path hit the state on its first frame —
   while a surface that minted a brand-new session painted the hero first
   and lost it as soon as the roster answered.
2. **The drawer stayed open.** On the compact form both create verbs — the
   New session bar's dialog and the project-header long-press — dispatched
   their session but left the drawer covering the page, so the reader stayed
   in the session list instead of landing on the session just minted.
   Tapping a session row already closed it.

## Decision

- `chat_screen.dart` gates the transcript on the window's *conversation*
  content: `_hasConversationContent` counts every item except the two
  mirrors, and the mirrors count only for what they show — the job roster
  never (pure chrome), the queue snapshot as soon as it holds a row, since a
  queued or steered message is the reader's own words and renders on this
  surface. The hero renders whenever the window carries nothing else and the
  first load has settled; `isTimelineLoading` keeps precedence, so a warm
  session mid-reload still reads as a wait. Pending approvals and questions
  stay conversation content, so a decision that took over the composer still
  suppresses the hero.
- The drawer's two create verbs route through
  `_createSessionFromDrawer` / `_createSessionInWorkspaceFromDrawer`, which
  dispatch exactly as before — the backend-aware verb when the surface was
  given one, the active controller's verb otherwise — and then close the
  drawer through the drawer's own `ScaffoldState`. The two-pane form hosts
  no drawer and stays unchanged.
- Evidence: `harness_repository_integration_test.dart` pins that a followed
  job-free session's window still carries its roster mirror (the fact the
  UI rule rests on); `empty_hero_test.dart` pins the mirror-only hero, a
  queued row beside a mirror, a message beside a mirror, and the loading
  precedence; `chat_controller_test.dart` drives the long-press reuse
  journey through the real controller and asserts the rendered hero;
  `chat_screen_test.dart` pins both drawer create verbs closing the drawer.
  [The timeline-loading note](../feature/2026-08-20-timeline-loading-indicator.md)
  restates the corrected gate.

## Alternatives considered

- **Dropping an empty queue or job mirror in `timeline_reducer.dart`.**
  Rejected: the mirror is one live slot per session — the queue dock, the
  job roster, and the `session/subscribed` clear all read it — and whether a
  conversation has content is a question about the transcript, not about
  which frames the fold keeps.
- **Gating the hero on `SessionSummary.blank`.** Rejected: the summary is
  the host's list fact, absent for a session the list has not caught up
  with, and it does not express the reference's "open, no messages" hero.
- **Closing the drawer with `Navigator.pop()` inside the create verbs.**
  Rejected: from the New session dialog the top route is the dialog, so the
  callback's pop would close the wrong surface and leave the drawer to the
  dialog's own pop. `closeDrawer()` names the surface it closes.
- **Keeping the drawer open because the reference sidebar is persistent.**
  Rejected: on the compact form the drawer covers the page, and every other
  verb in the list (row tap, backend switch) already closes it.

## Consequences

A message-free session shows its hero whichever path reaches it and whenever
the host's mirrors land; the long-press create lands the reader on the new
session with the drawer dismissed. The queue and job mirrors keep riding the
timeline for the dock and the roster, and a load in flight still reads as a
wait rather than as an empty conversation.
