# Agent Note: Timeline in-flight signal is sweep and status line, not spinners

Status: implemented

## Problem

The chat timeline ran four independent `CircularProgressIndicator`
spinners as its in-flight language — under a streaming user bubble,
before the assistant's first token, in the running tool row's leading
slot, and in the running command row. Each violated the row contract the
port exists to keep: the web `ToolRow` states "running keeps the icon —
the row sweep carries the in-flight signal," and the web turn carries one
`turnStatus` line (shimmer label, elapsed clock past 15s) instead of
per-row loaders. Concretely:

1. A running tool row swept and spun at once — two infinite animations
   per row, out of phase across parallel calls.
2. The four call sites repeated the same inline `SizedBox(12)` recipe in
   three colors (`primary`, `onSurfaceVariant`, theme default), with no
   recorded reason for the split.
3. The leading slot jumped geometry at settle: 12px spinner while
   running, 14px check or cross after.
4. 12px at 2px stroke sits under the M3 small-progress spec; the arc
   reads as mud at phone density.
5. Reduce-motion stopped the sweeps but not the spinners.
6. A round trip could show the user-bubble spinner and the assistant
   loader simultaneously: two tail signals for one wait.

## Decision

One activity language: rows sweep, the turn speaks, settled rows carry
state glyphs.

- `activity_dot.dart` — `ActivityDot`: a static 8px `onSurfaceVariant`
  dot in the shared 14px leading slot, so running → ok → error never
  shifts the row's left edge. Hand-built chrome: M3 has no state-dot
  component and the slot must wear the same geometry as `Icon(size: 14)`
  (same idiom as the rows' 2px dots). The sweep glare passes over it
  because the slot sits inside the row's `SweepHighlight`.
- `ToolCallRow` and `CommandRow` running leads render `ActivityDot`;
  the sweep is their only motion. `CommandRow` gained the same 2600ms
  sweep controller as `ToolCallRow` (web `dsh-command-row-sweep`).
- `turn_status_row.dart` — `TurnStatusRow`: the web `turnStatus` port.
  One line at the timeline tail — `l10n.turnStatusWorking` hopping letter
  by letter (a rectified sine on a 1200ms wave; this note is its
  bespoke-motion reason) under the shared `SweepHighlight` glare
  (1800ms, web's shimmer period), joining an elapsed clock
  (`formatJobDuration`) once the wait passes 15s, anchored at mount (the
  web fallback when the turn boundary sits outside the loaded window).
  It shows while the selected session runs or a message streams, and
  yields to the louder tail: hidden once assistant text flows, while an
  approval seats the wait on the user, and when no rows are visible
  below it (a queue-only window). It rides both
  transcript modes: an extra tail item in the flow list, an extra sliver
  in the outline — visible even when every turn is collapsed. The
  letter-split sits behind `Semantics(excludeSemantics: true)` on the
  run-state label: assistive tech hears one fact.
- `MessageRow` renders no loader. The user bubble carries no streaming
  spinner; the assistant shows the caret only once text flows.
- Kept: the centered `CircularProgressIndicator` for the conversation's
  first page (a screen-level load, per
  [the loading-indicator note](../feature/2026-08-20-timeline-loading-indicator.md))
  and `ContextRing` (a determinate meter, not an activity spinner).
- Partially supersedes
  [proposal A](../feature/2026-08-20-chat-timeline-restyle-proposal-a.md),
  which introduced "business spinner" leads and the pre-token loader;
  its bullets now point here.

## Alternatives considered

- **One shared polished spinner** (fixed size, one color, reduce-motion
  aware): rejected — still stacks rotation onto the sweep's glare, one
  row with two infinite animations, and keeps the transcript's cheap
  look; the reference has no in-row spinner to port.
- **Keeping the 2×18 caret from the empty-text state** (caret blinks
  while waiting): rejected — a blinking caret with nothing to append to
  reads as a rendering bug, and the transcript tail would carry no word
  about how long the wait has run.
- **Determinate per-tool progress**: rejected — the wire publishes no
  tool progress fraction; a fake determinate ring would lie.
- **Shimmer-only status label** (the web port verbatim): rejected — a
  glare band across one short line reads as flicker at phone scale
  without the letters' beat.

## Consequences

- Reduce-motion is one rule: sweep callers pass a null controller and
  the status line renders whole and still under
  `MediaQuery.disableAnimationsOf`; the dot never moves, and the clock
  keeps ticking because it is information, not decoration.
- A running turn costs one sweep per active row plus one status line
  (hop and glare tickers), replacing two tickers per row plus four
  ad-hoc spinners.
- Widget tests assert the language through the real screen: running
  tool and command rows carry `ActivityDot` and exactly one live
  `SweepHighlight`, the status line appears once per running turn (flow
  and outline), the caret and the status line never share the tail, and
  `CircularProgressIndicator` stays out of the timeline body.
- The status line changes `maxScrollExtent` as it mounts and releases;
  the bottom-follow glide absorbs tail growth.
