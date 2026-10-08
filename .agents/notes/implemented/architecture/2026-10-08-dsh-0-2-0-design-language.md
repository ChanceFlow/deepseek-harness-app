# Agent Note: The transcript's message chrome follows the dsh 0.2.0 design language

Status: implemented

## Problem

The wire contract moved to `dsh-v0.2.0-rc.2` in
[the re-pin note](2026-10-07-dsh-0-2-0-rc-2-repin.md), but the message chrome
still rendered the 0.1.7 design language. Three defects were visible on a
running turn: the label appeared twice, once ticking inside the turn control
and once in the transcript's tail row; a settled turn read `Took 2m 03s` with
zero-padded units; and the tail row's animation — a per-letter sine hop plus a
clock that waited fifteen seconds — matches nothing in any pinned tag. The
running line upstream is a brand mark beside a shimmering label, its clock
starts at one second, and 0.2.0 moved that line out of the turn control, which
is now settled-only and reads `Completed in …` from one unpadded unit-piece
duration.

## Decision

Port the pin's facts. The running state leaves the turn control for its own
row: a 14px whale tail, a stepped text shimmer, `Deep diving for 9s ···` from
the first second, and `Deep diving` only while the turn's start is unknown; the
row is 12px on a 22px line — the reference's own values at its 14px base —
digits in `tabular-nums`, and a 0.5px divider with 8/10px margins that appears
only when the visible row above carries output. The control keeps its fold toggle, loses
its ticker, and renders `Stopped`, `Failed`, `Completed`, or `Completed in `
followed by duration parts whose numerals take the code family
(`flutter/app/lib/ui/chat/run_duration.dart`).

One duration format replaces two: hours when hours exist, minutes from a
minute, seconds always, never padded. The two durations that read
`--dsw-alias-label-deep-diving` and its shimmer variant become `labelDeepDiving`
and `labelDeepDivingShimmer` in `DshSchemeColors`, mixed from the pin's static
palette the way `color-mix(in srgb, …)` defines them.

The tail is drawn, not shipped. The reference animates a 21KB APNG as an alpha
mask; Flutter has no mask-mode equivalent and the repository carries no asset
pipeline. The path is the reference's `REST_PATH` verbatim, and the motion
follows the asset: 28×28, sixty frames of 50ms, whose ink deforms rather than
translating — its alpha centroid wanders 0.94px across the frame, 0.47px at a
14px seat, with no single beat — so the tail sways 0.05 radians about its
baseline over a second, which carries that excursion. Reduced motion draws the
still path, exactly as the reference's own media query does.

The shared text-activity primitive follows the 0.2.0 `TextShimmer` contract: a
stepped sweep rather than a smooth one, one activity shared by nested
fragments, and the highlight composited over the row's single text node — the
composition the reference reaches with an inert decorative copy — so nothing is
announced, found or focused twice. A running turn announces its state once.

## Alternatives considered

Keep the per-letter hop and the fifteen-second clock: rejected — neither exists
in `dsh-v0.1.7-rc.2`, `dsh-v0.2.0-rc.2`, or `dsh-v0.2.1-alpha.1`, so they are
this client's invention and the pass exists to remove exactly that. Ship the
APNG and animate it: rejected — no asset pipeline exists, and the mask deforms
per frame, so no rigid transform would be faithful. Align only the copy and
leave the structure: rejected — the duplicated label is the defect a reader
sees, and the copy follows the split. Hold the pixel values in
[the design standard](../../../../docs/design-standard.md): rejected — it sits
at 896 of 900 words and its rules already carry this change (type separates
prose from data, motion carries feedback, tone carries hierarchy); a value used
twice becomes a constant in `theme.dart`, which is where these live.

## Consequences

A running turn shows one label, a settled one shows `Completed in 2m 3s`, and
both are localized from the pin's own strings. The reader's reduced-motion
setting stills the mark and the shimmer. The turn control no longer re-renders
once a second, because the clock moved to the row that owns it.

The same pass carries the rest of the 0.2.0 chrome: the reasoning row and the
command, compaction and group-header rows wear one disclosure tone (tertiary at
rest, secondary on hover) with the highlight over the label alone, and the
schedule reminder uses the plain clock glyph. That ladder is this app's own two
text roles, `onSurfaceVariant` then `onSurface`
([flutter/app/AGENTS.md](../../../../flutter/app/AGENTS.md)): the direction
matches the reference's step, the absolute tones stay stronger. The retired
0.1.7 turn-status
gradient role leaves `DshSchemeColors` with the line that used it. The
reference's model-retry row has no analogue here — this client carries no retry
timeline item — so its shimmer deletion, its wrapping rule and its marker have
nothing to land on. One cosmetic follow-up stands: `subagent_screen.dart` still
builds its sweep clock at 2600ms, which the primitive ignores in favour of the
pinned cycle. Upstream's `StatsPills` rewrite is a 0.2.1 change and stays out.
