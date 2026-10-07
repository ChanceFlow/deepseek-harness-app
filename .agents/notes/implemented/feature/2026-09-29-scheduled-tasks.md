# Agent Note: Scheduled tasks

Status: implemented

## Problem

A reminder the host had scheduled was invisible to the phone. The catalog, one
task's delivery history, and the two mutations a person can make — a
compare-and-update and a delete — were all unwired, so the only way to see or
change a scheduled task was a desktop.

Reading the pin turned up three facts that decided the shape of the work.

- **`schedule/create` is not a Remote.** The service has a `create` method, but
  no `@Remote` decorator: a reminder is created by the model's own
  `schedule_create` tool. The reference Web page has no creation form either —
  its New action starts a session and asks the model.
- **The service ships disabled.** `packages/bundle/web-app/cordis.patch.yml`
  carries `disabled: true` for both the `schedule` host row and the
  `ui-schedule` client row, and no shipped profile enables them. On a stock
  host every method answers `gateway/invocation-unavailable`; a surface that
  assumed presence would ship five broken controls.
- **The vocabulary on the wire is newer than what this client knew.** The
  `schedule/change` session event (three kinds, optional title) that the
  reminder strip folds is historical: nothing in production appends it in
  0.1.7, and the host's real records have six kinds with a required title.

## Decision

Wire all five methods and build a read-and-edit surface, without pretending to
the two capabilities the host does not offer.

- `DshRpcEndpoints` gains `schedule/{list,catalog,history,update,delete}`; the
  four request-shaped methods join the invoker's request-wrapped set, and
  `catalog` — which takes no arguments — stays out of it.
- The domain gains the host's record union (`ScheduleRecord` with its six
  kinds), `ScheduleCatalogEntry`, the delivery receipt/record pair,
  `ScheduleRetentionBounds`, and sealed results for history, update, and
  delete. The decoder enforces each kind's own required fields, so a `weekly`
  row without weekdays fails loud instead of rendering as some other rule.
- The business failures that ride *inside* the value are modelled as values:
  `ScheduleUpdateMiss` carries `schedule_conflict` / `schedule_ended` /
  `schedule_not_found` with predicates, and the surface reports the conflict
  instead of overwriting. `ScheduleHistoryMiss` does the same for a task or
  cursor the host no longer has.
- Edits are a draft against the observed record. An untouched draft sends **no
  `change`** and no unchanged text, so the host keeps the committed target and
  the stored zone spelling; only a name or instruction edit never resets when
  the task runs. The `expected` snapshot carries exactly the persisted rule
  fields — never the catalog's session binding, status, or last delivery.
- **Probe, then render.** The page calls `schedule/catalog` first and treats
  `gateway/invocation-unavailable` as "this host composes no scheduler", which
  it states. Every other failure is a retryable failure, and the two are
  distinct states rather than one error banner.
- **No create control.** The surface reviews, edits, and deletes. A reminder is
  asked for, and the page says so.
- History pages by exclusive message-id cursor, deduplicated by message id on
  append (an occurrence can be re-read when a delivery lands mid-page), and
  the three record-level facts the host reports separately —
  `earlierRecordsUnavailable`, `earlierRecordsPruned`, and a legacy receipt
  with no prompt — stay separate on screen too. A legacy receipt never shows
  the task's current instruction in place of the prompt it did not retain.

## Alternatives considered

Offer a create form and reject it host-side: rejected — the endpoint does not
exist, so the form could only fail, and the reference page's own answer is to
start a session and ask the model.
Gate the page on the Web bundle's `disabled` flag: rejected, because the flag
lives in the deployment's patch file and not on the wire; the probe is the same
fact observed where it actually applies.
Poll or cache the delivery feed: rejected; the page is a read-on-open surface
and `schedule/changed` is not forwarded to this client, so a stale cache would
be indistinguishable from the truth.
Edit the record wholesale rather than sending `expected`: rejected — that
turns a concurrent edit into a silent overwrite, which is the exact failure the
compare-and-update exists to prevent.
Fold a refused update into the chat error banner: rejected; these are expected
business outcomes of a form the user just submitted, and they belong next to
the form.

## Consequences

`declared 72 / upstream 125 / identical 70 / missing 55`. A phone can now
review every scheduled reminder, read its history, edit its name, instruction,
and repeat, and delete it — with conflict, ended, missing, pruned, and legacy
cases each stated as themselves. Creation stays model-mediated and the
disabled-by-default service is reported rather than assumed; both are recorded
in docs/spec.md §10. The historical `schedule/change` fold and its reminder
strip stay as they are: they describe a session-log vocabulary this host no
longer writes, and removing them needs its own evidence about older logs.
