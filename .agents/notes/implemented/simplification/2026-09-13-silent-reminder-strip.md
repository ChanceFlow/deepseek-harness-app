# Agent Note: The reminder strip leaves when it has nothing to show

Status: implemented

## Problem

The input dock mounted the session's reminder strip for every selected session.
The strip answered an unreported reminder set with a standing line — "提醒 ·
该主机未上报" on the phone — and the pinned `dsh web` deployment composes no
`schedule` projection at all, so that line was permanent in every session. A
row of the dock's scarce height was spent restating a fact with nothing behind
it, and the reader had no way to learn what the row was for.

## Decision

**The strip exists exactly while a reminder does.** `ChatScreen` mounts it only
when `schedules` is a non-empty list, and `ScheduleReminderStrip` returns a
zero box for a null or empty set on its own. An unreported set and a known
empty set are then equally absent: neither is actionable, and the difference
between them is a distinction only the client's own diagnostic interest draws.
The strip that does appear is the one with a count, a next target and rows to
open — the same "no data of its own, hidden while empty" rule the plan strip
already follows.

## Alternatives considered

- **Keep the honest standing line.** Its honesty was never the problem; its
  cost was. `scheduleUnknown` and the paragraph that defended it are removed
  rather than reworded, because no wording makes an always-present row
  actionable.
- **Show the line only when the host reports a schedule projection exists.**
  There is no such signal at the pin: a deployment that composes no projection
  and one with no reminders pending are indistinguishable from here, so the
  condition cannot be evaluated.
- **Move the strip behind a session-header action.** The reference does this,
  and
  [the session-facts note](../feature/2026-09-11-session-facts-surfaces.md)
  already rejected it for a 360dp bar.

## Consequences

`scheduleUnknown` and `scheduleEmpty` leave both ARB locales, and the
`session-facts-surface` note's reminder paragraph now states the dock rule
instead. `session_facts_surface_test.dart` holds both silent cases and the
populated one.
