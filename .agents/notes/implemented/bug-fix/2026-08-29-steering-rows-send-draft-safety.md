# Agent Note: Pending steering renders at the transcript tail; a send consumes the draft only on acceptance

Status: implemented

## Problem

Three composer-adjacent defects on the chat surface.

1. **Steering rows render nowhere.** The transient inbox
   (`session/queue`) carries three placements — queued, steering, context
   (`reference/deepseek-harness/packages/host/apiproxy/src/api-proxy.ts`
   `queueItems`: nextTurn→queued, nextStep user→steering, nextStep
   non-user→context). The dock filtered to `queued`; the `TimelineQueue`
   body rendered `SizedBox.shrink()` and was excluded from the flow list,
   so a steered message vanished from the UI the moment its placement
   flipped — until the running turn claimed it as a durable user message,
   minutes into a long turn. The web renders pending steering at the
   conversation tail (`packages/host/apiproxy/src/api/events.ts:81-82`;
   `packages/client/ui-conversation/src/client/chat/ChatView.tsx:454-460`,
   `PendingSteeringBubble` at `MessageItem.tsx:257-278`).
2. **A failed send deleted the draft.** `_send` cleared the controller and
   wrote the cleared marker synchronously; the RPC settled (and could
   fail) later, surfacing only the error banner. The reader lost their
   words on every failed send.
3. **An approval hid the whole dock.** Queue dock and `ApprovalPanel`
   shared one else-if; the web keeps the dock alive beside the panel (the
   dock registers into its own `conversation.input.dock` slot).

## Decision

**Tail row, not a dock section.** The steering rows come out of
`TimelineQueue` in the panel state and render at the transcript tail —
flow rows, turn-status line, then one `PendingSteeringRow` per steering
item — in both render modes. A QueueDock section was rejected: the dock
is a bounded chrome strip whose contract (the 2026-08-19 redesign) is
`queued`-only, and the web fact is that pending steering rides the
conversation flow, right where the claim will surface it. The row reuses
the pending-row language — the activity dot and sweep glare of a running
step around the existing user bubble — because an undecorated bubble
(web's form, where "my message" and "my pending message" share one
column) cannot be told from a delivered message at phone scale. Caption
text is the web's steer verb (`插话发送`; English "Steering", the gerund
of `settings.enter.steer`). Rows whose id already appears as a durable
user message drop out (the claim can land in the same frame), and context
placements render nowhere while transient, as on the web. The follow
contract treats a new steering row as own words: it joins the tail
signature and force-scrolls like a trailing user message.

**Settle-gated draft.** `SendPrompt` carries a one-shot settle notice;
the controller calls it with the host verdict on every route (prompt,
command, command-error result, unmatched-command fallback, dropped
dispatch), and the composer clears the field and writes the cleared
marker only on acceptance — and only while the field still holds the
submitted text (a detached command runs without disabling the composer;
newer typing wins). This makes the client stricter than the web (which
clears optimistically and restores the draft while untouched,
`input/hub.ts:160-172`): with no reliable way to disable the field for a
detached dispatch's whole lifetime, holding is the shape that cannot
lose text. A failed send is re-dispatched by the reader's next tap —
one submit per tap, no client-side replay; the RPC has no idempotency
key and the host commits the inbox insert inside the request, so
neither an automatic transport-drop retry (the `executeCommand` pattern,
safe there only because the host aborts a command whose request dies)
nor an echo-dedup is safe here, and the kept draft is what makes the
manual retry honest.

**Strip, not seat.** The dock mounts whenever `queued` rows exist, above
the approval card; the composer seat still belongs to the approval —
one filled seat per surface holds. Draft-restore races: a late
`readDraft` lands only if the session is still the same and no keystroke
interrupted it.

## Alternatives considered

- **Local echo at `_send`** (render the steered text immediately from the
  composer side): rejected — the queue snapshot is the sole authority
  (the host is the source of truth), and an echo needs a dedup seam
  against the snapshot and the claim it races.
- **Clear-on-dispatch + restore-on-failure** (the web's optimistic
  shape): rejected for the detached-command window, where the field
  stays live and a restore would clobber newer typing.
- **Hide the steering row once its dock row disappears** (keep the dock
  the only home): rejected — that is the shipped defect.
- **Automatic transport-drop retry for prompts**: rejected as above;
  double-enqueue is worse than a draft the reader can resend.

## Consequences

A steered message is visible from tap to claim; the 08-19 note's
steering-timeline sentence now describes the implementation.
Command submissions join prompts in keeping their draft on failure —
the web does the same for command errors. `SendPrompt`'s value identity
stays text+mode; the notice is plumbing. The tail rows join the
transcript's scroll-follow contract; a queue-only window now has a
visible tail. The stale dock-vs-approval exclusion and the steering
invisibility are corrected in
[the queue dock note](../feature/2026-08-19-queue-dock-tab-persistent-draft.md).
