# Design standard: the phone client from first principles

Taste does not survive a handoff. This document derives the client's surface
from facts about the product, so the next component has an answer before it
is drawn and a reviewer can name which fact a change violates. The resulting
numbers — the `ColorScheme` role map, the four radii, the three gaps — live
in [flutter/app/AGENTS.md](../flutter/app/AGENTS.md); here is where they come
from and how to derive the next one.

## The facts

Five observations about this product, not preferences about interfaces.

1. **The content is the agent's.** Everything worth reading is host output:
   prose, code, paths, tool payloads. The client is its container.
2. **Space is the budget.** An unbounded log renders inside roughly
   360×740dp, held in one hand with the thumb near the bottom. Every
   element spends from the same scarce column of pixels.
3. **The host owns the truth.** State arrives as session events the client
   renders and cannot re-derive ([docs/spec.md](spec.md)).
4. **The reader supervises.** They scan for what it is doing, whether it
   worked, and where to step in; they type rarely.
5. **Agents read this code cold.** A decision carried by taste drifts on the
   next change; one carried by a constant or a gate holds.

## What follows

Each rule ends with the facts above it answers to; disagree with a rule by
disagreeing with its facts.

- **Tone carries hierarchy.** Content takes one surface and every frame
  around it another, so the transcript separates from its chrome with no
  border, rule, or shadow drawn (1, 5). A rule is the last resort, after
  tone and space have failed — and a framework component that draws one by
  default is overridden, not accepted.
- **One filled seat per surface.** Saturation is how a screen says *here*;
  spend it on the single next action so the eye lands there instead of on
  the reader's own words (1, 4).
- **A row is as tall as its line.** Chrome takes the height of its content:
  an icon that outgrows its text is shrunk, never accommodated, and a
  container's own padding is removed rather than budgeted around (2).
- **Space encodes structure.** Gaps say what a divider would: steps inside
  one action sit tight, a reply is a block, a turn change is a break (2, 4).
- **Type separates prose from data.** Prose gets reading size and leading;
  payloads — paths, patterns, counters — get monospace at caption size; the
  verb that names a step gets weight, not a second family (1, 4).
- **Disclosure defaults closed.** A step shows one line and opens on demand;
  the transcript is the only surface that scrolls, and the docks around it
  stay bounded no matter what the session contains (2, 4).
- **The client states only what it was told.** Running, failed, queued, and
  empty each render a host fact. Nothing is shown optimistically, and a
  missing referent surfaces instead of defaulting to a plausible value (3).
- **The thumb owns the bottom edge.** The composer and the primary action
  stay in reach; a secondary verb rides a long-press on the thing it acts
  on rather than a permanent seat that costs every turn a row (2, 4).
- **Stock components, and a constant for every number.** Material 3
  defaults are the cheapest correct answer and the one an agent cannot get
  subtly wrong. A repeated value becomes a named constant in `theme.dart`
  on its second use (5).

## Deciding a new surface

Answer in order; a blocked question sends the change back, not forward.

1. **Which fact does this show, and who owns it?** A host fact belongs in
   the transcript's flow. Local state belongs to the control that holds it.
2. **Can an existing row carry it?** A line inside the transcript costs
   nothing at rest; a new bar costs its height in every session forever.
3. **What does it cost in vertical pixels while idle?** Name the number and
   say what the reader gains for it.
4. **Which existing step does it take?** A tone from the role map, a radius
   from the four, a gap from the three. A new step is a decision note.
5. **What proves it?** A widget test that pumps the real tree and asserts
   the rendered role or behavior ([docs/testing.md](testing.md)).

## Enforcement

`verify_theme_native` rejects a raw color or a theme extension anywhere
under `flutter/app/lib/` outside `theme.dart`, so the role map is the only
way through. Widget tests assert colors by role under both brightnesses, so
a hard-coded value fails one of them. The rest — whether a change earns its
pixels — is review holding a diff against the five facts above.

## Looking at it

Rules 1 and 4 are claims about a rendered screen, so a change to one is
settled by rendering it. `python3 scripts/render_design.py --publish`
pumps the real screens at phone size and puts this pass beside the last
one on a page a human can open. The shots prove nothing on their own —
they are how the eye gets its turn, after the tests hold the rules.
Procedure and traps:
[scripts/render_design.py](../scripts/render_design.py).
