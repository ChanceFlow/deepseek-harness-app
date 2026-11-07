# Agent Note: Notification copy reports what the user gained, not what the system finished

Status: implemented

## Problem

The notification copy was written from the system's side of the fold: "Reply
ready", "Turn completion", "New reply in another session", "Working…". Those
strings are accurate about the mechanism and silent about the user's question
— *did anything arrive for me, and is it worth opening now?* The two rendering
surfaces (the in-app banner and the system notifier) each composed their own
title/body pair, the body never named the host, and the Android channels were
named after internal mechanics ("Turn completion", "Working sessions",
"Approvals", "Plan reviews") even though the user reads them in system
settings. A notification is the one place where the client speaks without the
host's page, so the wording is the product.

## Decision

**Result first, subject second, and one copy module for both surfaces.**

- **Titles name what the user gained.** A finished turn is `New reply` /
  `有新回复`; a pending approval is `Approval needed` / `需要你批准`; a plan is
  `Plan ready` / `计划待确认`. The two completion kinds
  (`selectedTurnComplete`, `otherTurnComplete`) keep their distinct routing —
  only one is silent while watched — but share one wording, because the
  selected/other split is our bookkeeping, not the user's fact.
- **The body names the subject.** `notification_copy.dart` composes the quoted
  session title, then the workspace when the host supplied one, then the host
  label, joined with ` · ` and skipping empty segments:
  `“Login refactor” · proj-a · Build box` / `「重构登录页」· 构建机`. The quote
  pair is an ARB key (`notificationSubject`) so English and Chinese keep their
  own punctuation instead of inheriting one language's.
- **The banner and the system notification share that module.** The banner's
  local resolver and the notifier's `_copyFor` are gone; both call
  `notificationCopy`, so the two channels cannot drift.
- **The host label is a seam, not a coupling.** `AppNotificationEvent` and
  `WorkingSessionDecision` carry an optional `hostLabel`; the center reads it
  from `backendLabelsProvider`, which is empty by default and overridden in
  `main.dart` with the registry-derived map. A headless test never builds the
  registry store, and a rename is picked up on the next notification without
  rebuilding the center.
- **Channels are named in the user's vocabulary.** `New replies` / `新回复`
  (completion, default importance), `Needs your input` / `需要你处理` (approval,
  plan review and question merged into one high-importance channel),
  `In progress` / `进行中` (silent ongoing), `Background connection` /
  `后台连接` (min importance keep-alive). The ongoing row's body says
  `Replying` / `正在回复`; the promoted done row wears the new-reply title and
  the subject body, so one finished turn reads the same whichever row lands
  first.

Deferred, with the reason recorded: a reply preview line (the first line of
the answer) needs a repository seam that observes the last assistant message
per session; the event currently carries only summary facts, and inventing a
second socket for copy is not worth it before the wording settles.

## Alternatives considered

- **Keep "completed" wording and add the session name.** "Session finished ·
  Login refactor" is still a system fact; it reads like CI, not like a reply.
- **Put the host in the title.** Two hosts would produce two nearly identical
  titles and hide the event; the title has one job.
- **Keep separate approval and plan-review channels.** They are the same user
  decision at the same urgency; two channels fragment the settings screen and
  halve the chance the user keeps one enabled.
- **Add the preview now by re-fetching the timeline on completion.** It makes
  every notification a network round trip and can arrive after the post; the
  copy fix does not depend on it.

## Consequences

- Merging the two pending channels creates a new Android channel id (`pending`)
  and leaves any user-tuned old channels behind; a one-time settings reset is
  preferable to a permanently split decision channel.
- The host label is whatever the registry resolved when the fold ran; a rename
  that has not propagated shows the old name on that post. The body is still
  correct — the session is the identity, the host is attribution.
- `notificationSubject` is the only string composed inside another message; a
  locale that prefers no quoting must still return a wrapper, because the
  body's joining rule assumes the subject is already delimited.
- The copy module is now the single place a future "failed" or "stopped" event
  must be written; the detector still emits only completion and pending
  interactions, so those kinds wait for a fact, not for wording.
