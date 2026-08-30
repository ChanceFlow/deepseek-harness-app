# Agent Note: Queue dock redesign and tab-persistent composer draft

Status: implemented

## Problem

The queued-message dock rendered a debug-grade form: one text line per
item ("Queued: …") with three text buttons, every placement mixed in, a
dialog for edits, and steering always armed (idle sessions dispatched a
guaranteed `steer-unavailable`). Switching bottom tabs unmounted the chat
route and dropped the composer draft.

## Decision

The dock ports the web `QueueDock.tsx` + `QueueDock.module.css`
(`reference/deepseek-harness/packages/client/ui-conversation/src/client/queue/`):
only `queued`-placement rows ride the dock (steering renders at the
conversation tail as a pending row, context only durably as injection
rows; that split shipped later, see
[the 2026-08-29 note](../bug-fix/2026-08-29-steering-rows-send-draft-safety.md));
one message renders directly with
the queue glyph on the row, several collapse behind a 36px count header
("N queued messages", chevron flips with expansion, 180px scroll cap);
rows are 36px with a single 13px dimmed preview line and 1px inset
hairlines between; actions are 28px circles — edit swaps the preview for
an inline editor (r6 border, Enter saves / cancel closes, check/close
confirmations), steer stays armed only while the turn runs (the dock
receives the running flag), remove dispatches directly. The subagent
child view's read-only dock aligns to the same row form.

The app root keeps every destination mounted through an `IndexedStack` —
a tab switch no longer unmounts the chat route, so the composer draft,
scroll positions, and expansion states survive.

## Alternatives considered

- **AutomaticKeepAlive per destination**: rejected — each screen would
  opt in individually; IndexedStack preserves the whole subtree with one
  root-level change.
- **Persist the draft into controller state**: rejected — the web's
  per-session draft machine is a separate seam; the bug was unmounting,
  not missing persistence.
- **Keep the edit dialog**: rejected — the web edits inline in the row;
  a dialog adds a navigation hop for a one-line edit.

## Consequences

Steering can no longer be dispatched from an idle session (the button
disables instead of erroring). Queued rows ride only the dock; steering
rows render at the transcript tail and the dock stays mounted beside an
approval card — both per
[the 2026-08-29 note](../bug-fix/2026-08-29-steering-rows-send-draft-safety.md).
All three tabs stay built
offstage; their controllers already lived at root scope, so stream
lifetimes are unchanged.
