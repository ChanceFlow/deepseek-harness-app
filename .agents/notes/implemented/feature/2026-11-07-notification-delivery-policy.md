# Agent Note: The shade always keeps the event; the banner is an addition

Status: implemented

## Problem

The center routed each transient event to exactly one surface: backgrounded
went to the system notification, foregrounded went to a four-second in-app
banner. An event that arrived while the user was looking elsewhere on the
same screen left no row in the shade once the banner faded, and nothing
replayed it. Two peer clients had already shipped and fixed the same class of
bug: one suppressed foreground events and dropped them permanently (their
default is now "deliver anyway", with a bounded deferred queue for the
suppression case); the other is a native center whose tap payload had no
reader at all. The lesson is the same: a notification that is only announced
is not delivered.

The same pass had no user controls and no failure wording. A failed or
stopped turn read as "New reply"; there was no reply preview; and Android's
per-channel silencing was invisible in the app.

## Decision

- **Every event leaves a shade row**, foreground or not. `announcementFor`
  returns `system: true` always; the banner is added only when the app is
  foregrounded and the event is not the watched session's own completion.
  The watched session keeps its row and stays off the banner — silence on
  the banner must never mean a lost event.
- **Preferences gate delivery, not storage.** A device-local master switch
  plus three seats (replies; failures and stops; needs your input) drive
  `allows(kind)`. The center reads the gate at emit time; switching the
  master off also cancels the ongoing rows this center owns, so a silent row
  does not outlive the choice.
- **A completed turn is read once, then announced.** The center probes the
  session's timeline for the latest turn boundary and the newest
  text-bearing assistant message: `aborted` becomes `Reply stopped`, any
  other non-completed end becomes `Reply failed`, and a finished turn carries
  the reply's first line (≤80 characters) under the subject. A probe that
  times out, throws, or reads nothing leaves the plain completion standing —
  the notice is never dropped for lack of facts.
- **Android's own answer is shown.** The settings page reads
  `areNotificationsEnabled` and the replies/pending channels' importance; a
  silenced channel renders a block with a link to the system's channel
  settings, because the app cannot raise importance itself.
- **Channels keep their designed importance.** `New replies` (default),
  `Needs your input` (high), `In progress` (low, silent), `Background
  connection` (min). Importance is immutable once created, so the pending
  channel was introduced already-high; the old approval/review ids remain
  behind for devices that had them.

## Alternatives considered

- **Keep foreground suppression and add a deferred queue** (the peer's
  design): a queue adds TTL, coalescing and bounds to solve a problem the
  WebView shell does not have — nothing here suppresses in the first place.
  Posting always is simpler and strictly safer; a user who is looking at the
  page can still swipe the row away.
- **Infer failure from `SessionSummary.agentError`.** The summary carries an
  error after the fact but not the turn-end reason, and cannot tell a user
  stop from a hook abort; the timeline boundary is the host's own terminal
  fact and is already decoded.
- **Read the whole transcript for the preview.** One snapshot of
  `observeTimeline` bounded by a three-second timeout gives the same line;
  more history would only add latency to a notification.
- **A settings toggle per channel instead of per event kind.** Users think in
  events ("tell me when it needs me"), not in Android channel ids.

## Consequences

- Foreground users now see both a banner and a shade row. The row uses
  `onlyAlertOnce` for a session's own lifecycle, so it does not buzz twice.
- Each completion costs one timeline subscription (bounded, cancelled after
  the first snapshot). A disconnected host makes the probe time out and the
  notice still posts.
- The domain drops `aborted.reason.kind`, so a parent/hook/disposed abort is
  worded as "stopped" like a user stop; `interrupted` and `forked` are
  worded as failures. Tightening this needs the reason kind on the domain
  boundary.
- The preview is one line of answer text on the lock screen's private
  notification: it is only rendered after unlock (the row is
  `VISIBILITY_PRIVATE`), never in the public version.
