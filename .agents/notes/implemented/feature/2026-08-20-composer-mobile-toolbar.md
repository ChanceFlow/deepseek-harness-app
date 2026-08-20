# Agent Note: Composer mobile toolbar — no newline button, two-level controls

Status: implemented

## Problem

The composer carried a dedicated 28px ⏎ (newline) button beside the ➕
that duplicated the soft keyboard's return action, and the single packed
control row — ➕, ⏎, access chip, plan pill, model seat, context ring,
primary send — overflowed or felt cramped on narrow phones. Controls were
small (28–34px visuals), below the comfortable touch-target floor for
thumbs, and the web-input-row layout did not read as two distinct
affordance levels on a touch surface.

## Decision

**Newline rides the keyboard only.** The ⏎ circle button and its
`_insertNewline` caret-insertion method are gone; `TextInputAction.newline`
on the draft field already inserts the newline, so multi-line drafts are
unchanged. The send (↑) button is the only submit gesture; while a turn
runs, Stop keeps the web primary seat and a second send control appears
whenever a draft is ready, its delivery mode following the persisted
`chat.busyEnterBehavior` preference — all pre-existing behavior, unchanged.

**Two-level control layout.** A hairline rule (`ds.divider`) now separates
the draft surface (field, image chips, slash candidates) from the control
row. The row regroups the web InputBar seats for touch:
- **Left cluster** — input tools and contextual seats: ➕ (commands +
  attach images), the model seat, the permission chip, the plan pill
  (each chip renders only while its state is non-null/active, as before).
- **Right cluster** — occupancy ring + primary send/stop, plus the extra
  send control beside Stop while running.

The row is a `Wrap` with `alignment: spaceBetween` and `runAlignment: end`,
so a narrow phone drops the primary cluster to its own right-aligned run
instead of overflowing. All functional surfaces (command sheet, model
sheet, permission dialog, plan pill behavior, context panel, image attach,
slash candidates, draft persistence) are untouched — parity with the web
composer is preserved.

**Touch targets.** `DsCircleButton` keeps its 28px visual circle inside a
40px hit area (Material + CircleBorder clips the ripple; hover swaps the
inner circle fill). `_PrimarySendButton` keeps its 34px visual inside a
40px hit area. Both stay on the selector fill with tertiary glyph until
actionable, then take the info fill — no idle blue.

## Alternatives considered

- **Keep the ⏎ button, move it into an overflow (⋯) sheet**: rejected —
  the keyboard return is the same gesture, and hiding it behind an extra
  tap only raised friction without adding capability.
- **Two always-visible rows (tools row + send row)**: rejected — the
  `Wrap` with a right-aligned primary run delivers the same regrouping and
  stays one row tall when the phone fits it.
- **Keyboard return becomes send, newline via long-press**: rejected —
  soft keyboards have no reliable Shift+Enter chord; keeping newline on
  the return key preserves multi-line drafts with zero gesture discovery
  cost.

## Consequences

`l10n.newLine` is removed from both ARB templates and the committed
gen-l10n output; `_insertNewline` is deleted. The composer's control row
height grows slightly (40px hit areas), which is the intended touch-target
floor. Partially supersedes the newline-button decision in
[2026-08-20-composer-mobile-parity.md](2026-08-20-composer-mobile-parity.md);
its access/preset/persistence decisions still stand.
