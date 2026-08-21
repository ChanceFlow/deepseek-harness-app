# Agent Note: A visual system for the transcript

Status: implemented
Surface: `flutter/app/lib/ui/theme/theme.dart`, `flutter/app/lib/ui/chat/*`

## Problem

The app looked like a Flutter demo, and the reason was mechanical: the
theme was `ColorScheme.fromSeed(seedColor: Colors.blue)` — the value
`flutter create` writes — plus a FAB size override, and nothing else. Every
other decision a product theme owns was left at its factory setting, so the
screen accumulated defaults:

- One flat tone under everything. The bar, the transcript, and the input
  dock shared `surface`, so nothing marked where the page stopped and the
  chrome began.
- Four filled shapes competing. The user bubble sat in `primaryContainer`,
  the model seat and the `+` in their own fills, and the send button in a
  fourth — the loudest thing on screen was the reader's own text.
- Three nested cards at the input edge. The plan strip, the composer, and
  the queue each drew a border and a radius of their own; the stats line
  floated between two of them with no surface at all.
- One 16px gap everywhere. A run of tool steps, a reply, and a turn change
  were spaced identically, so the transcript read as a list of unrelated
  lines rather than a conversation.
- Type carrying no meaning. Tool rows set the verb in monospace and the
  path in body text — backwards — and the body ran at the default 14/1.4
  regardless of whether it was prose or a counter.

## Decision

`theme.dart` becomes the home of the product's visual decisions, and the
chat surfaces spend their tones and gaps on hierarchy:

- **Seed.** `kDshBrandSeed` (`#4D6BFE`, DeepSeek's violet) replaces
  `Colors.blue`. Every role still derives from one seed — the M3 contract
  is intact, the starting point is a decision.
- **Two tones.** Content keeps `surface`; every frame around it — app bar,
  input dock — sits on `surfaceContainer`. The bar drops its scroll tint,
  because the tone already separates it at rest.
- **One fill.** Send is the only filled seat in the control row. The model
  seat and `+` become plain icon buttons on the dock, and the user bubble
  moves to `secondaryContainer` — present, not shouting.
- **One dock.** `_InputDock` owns the surface, radius, and border for the
  plan strip, goal strip, queue, and composer together; the strips divide
  with hairlines. The stats line moves above it as a transcript caption.
- **Four radii.** `kShapeSheet` 28, `kShapeDock` 20, `kShapeCard` 14,
  `kShapeChip` 8. The bubble's tail corner takes the chip step so it points
  at its author.
- **A type scale.** Body 15/1.55 for prose, 12.5 for step rows, weighted
  600 labels. Tool and reasoning rows share one grid: glyph, weighted verb,
  monospace payload.
- **Three gaps.** `_gapAfter` spaces a run of steps at 6, messages at 16,
  and a turn change at 24.
- **No chrome under the reader's own words.** The user bubble drops its
  action row; long-press copies with a snack-bar receipt. The reply keeps
  one compact copy-and-clock footer, so a turn spends one row on chrome
  instead of two.
- **A blank session names nothing twice.** The bar carries the app name
  while the hero owns the workspace, and the hero sits low, near the
  composer it is asking the reader to use.

## Alternatives considered

- **Palette-only pass.** Three seed/variant candidates (`tonalSpot`,
  `fidelity`, `neutral`) rendered against the real screen all looked like
  the same screen. Layout, not hue, was the defect.
- **Keep the per-message action rows and enlarge their targets.** It
  doubles the chrome rows per turn to solve a problem a long-press does
  not have.
- **A left rail or avatar anchoring assistant replies.** The 15px prose
  against 12.5px step rows already separates them.
- **Drop timestamps entirely.** Deferred: absolute time still answers
  "when did this run start".
- **A `ThemeExtension` for the shape scale.** `verify_theme_native` rejects
  extensions by design.

## Consequences

- `flutter/app/AGENTS.md` gains the shape scale and the two-tone rule; the
  colour-role table stands.
- Three tests changed with the contract: the user row no longer carries
  actions (it copies on long-press), the subagent bubble asserts
  `secondaryContainer`, and the jump-to-bottom fixture grew to 16 turns
  because a shorter dock and tighter step gaps stopped overflowing the
  viewport.
- `verify_theme_native` stays green: every new colour is a role, and the
  seed and shape constants live in the exempt `theme.dart`.
- The empty state's void is still a void. Its first-step affordances —
  grounded in the session's skill roster rather than invented prompts —
  are the next change.
