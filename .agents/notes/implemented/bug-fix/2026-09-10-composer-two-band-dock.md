# Agent Note: The composer dock is two bands, not one row

Status: implemented

## Problem

The [single-row composer](../feature/2026-09-11-single-row-composer-and-command-draft-parity.md)
put the draft field and every seat on one `Row`. That row only fits while
the host's access chip is absent — which it never is on a live session.
Measured at a 360dp phone, the dock is 334dp wide and the seats alone want
393dp: `+` 40, mic 48, access chip 135, model seat 48, meter 36, primary 48.
Flutter lays a squeezed `Expanded` out at zero width instead of overflowing
the child, so the `TextField` became **0×112dp** — the reader had nowhere to
tap or type — while the dock still spent 120dp of height on it. The one
overflow error it raised was the row's, not the field's.

Two nets missed it. Every composer widget test pumped without `permissions`,
and every design fixture mounted none either, so the crowded row only existed
on a real phone.

## Decision

Rebuild the dock as the reference web card: **the draft owns the top band and
the controls ride one action row under it**
(`InputBar.module.css` `.card` — "textarea on top, action row below, primary
action controls bottom-right").

- **Band 1 is the field alone**, full dock width, 1–4 lines. No seat count can
  squeeze it again, at any width.
- **Band 2 is the action row** (web `.row`): attach, mic and the access chip on
  the left; the model seat, the context meter and the primary action on the
  right, so the send thumb keeps the bottom-right corner. The plan pill, the
  pending-image chips and the slash candidates stay as trays above the card,
  at zero idle height.
- **The access chip drops its label below a 460dp dock**, keeping the mode
  glyph and the chevron — web `PermissionSelect.module.css`
  `@container (max-width: 460px)`. Its tooltip and its sheet still name the
  mode.
- **The action row splits into two lines below 280dp** (330dp while the
  queue-send seat waits beside a running turn) rather than shrinking a seat
  below its M3 footprint — web `.row { flex-wrap: wrap }`: "the trailing group
  moves to its own line instead of the left group shrinking". The cuts carry
  8dp of slack over the measured 272dp/322dp sums and the dock's tests hold
  them against the seats themselves.

Measured after the rebuild: at 360dp the idle dock is 102dp tall with a 306dp
draft band; 320dp, 360dp and 393dp render without overflow in every seat
combination, with or without a waiting draft.

## Alternatives considered

- **Shrink the seats** (40dp visuals, `shrinkWrap` tap targets): rejected —
  48dp targets are the M3 minimum, and a band of its own removes the need to
  trade accessibility for width.
- **Move the model seat into the `+` sheet**: rejected for now — the note
  above keeps direct seats on purpose. The row splits instead, which costs a
  second line only while a draft waits on a running turn (150dp at 360dp).
- **Keep one row and let it wrap**: rejected — a wrapped draft line is the
  defect itself; the field needs its own band whatever the width.
- **Scroll the toolbar horizontally**: rejected — hides seats behind a
  gesture with no affordance, and a dock that scrolls cannot be read at a
  glance.

## Consequences

- The draft band is structurally independent of the action row, so the
  zero-width failure cannot return through a new seat.
- The 360dp "running turn with a waiting draft" state spends a second control
  line (150dp). Making it one line needs a seat moved behind the `+` sheet —
  that trade belongs to the reader, not to this change.
- Widget tests now pump the composer **with the access chip** at 320/360/393dp
  and assert the draft band stays wider than 200dp, that entered text reaches
  `SendPrompt`, that a running turn keeps both stop and queue-send, and that
  the chip's label appears only above the cut.
- The design catalog gained `composer-crowded` — access chip, running turn,
  waiting draft — because the defect was invisible in every fixture that
  omitted the chip.
- The command-claim, slash-candidate and flexible-chip decisions of the
  single-row note stand; only its layout decision is superseded here.
