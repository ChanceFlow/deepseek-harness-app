# Agent Note: Anchored popovers, and the page a card's row used to pop

Status: implemented

## Problem

This client's menus were modal routes: `showModalBottomSheet` with a
transparent barrier. Removing the barrier's colour fixed the reader-visible
defect (the app dimmed whenever a menu opened) but not the shape. The
reference portals its menus from the trigger's rectangle, so a menu sits
against the control that opened it; ours sat at the dock seam regardless of
where the reader pressed, and the route underneath meant a menu owned a
navigation entry it never needed.

Moving the seats onto an overlay card introduced a second, quieter defect. A
row inside a card still called `Navigator.of(context).pop()`, which is correct
inside a sheet route — the sheet is the route. Inside an overlay card it pops
the **page** underneath instead. The probe that found it: tapping a verb in a
migrated card took the tree from two tiles and eleven texts to zero and zero,
with `Navigator` still present and `Overlay` still present — an emptied
navigator, not a hidden subtree. An outside-tap dismissal left the tree intact,
which isolated the cause to the row's own pop.

The suite had passed throughout: the existing tests asserted the action a row
dispatched and never looked at the page afterwards. That is the general shape
worth remembering — a migrated seat keeps its assertions and loses its
container.

## Decision

Menus open a shared anchored card (`ui/shared/anchored_menu.dart`) rather than
a route.

* **Placement is the reference's own hook**, not a Flutter analogue:
  `left = align == end ? rect.right - width : rect.left`,
  `top = side == top ? rect.top - gap - height : rect.bottom + gap`, clamped to
  a margin against both viewport edges. `side` and `align` are explicit; the
  card **clamps and never flips**, because that is what the reference does.
* **The anchor is re-measured every frame while open.** Measuring during build
  is not enough: a viewport change leaves a stale rectangle, and the probe saw
  the delegate holding `y=1214` while the real trigger sat at `y=538`, seating
  the card on the bottom clamp. The failing placement test is what surfaced it.
* **Colour, radius, hairline and elevation come from the menu material**
  (`MenuMaterial`), so a migrated seat's look does not move.
* **Dismissals: outside tap, Escape, window blur, and the system back press.**
  The first three are the reference's; the back press is a phone addition,
  because a route used to provide it and an overlay card has none. The card
  consumes it while it stands and returns it to the platform once closed.
* **A card contributes content, never navigation.** A row closes through the
  card's own verb. `Navigator.pop` inside a card subtree is the defect above,
  and two guards now assert the page survives a row tap.
* **Per-surface caps are measured per surface**, as the reference caps per
  surface, rather than one number for the family.
* **A submenu stays a route.** The open-workspace card is invoked from inside
  another menu; the reference renders that as a child list in the parent card,
  not as a second anchored card hung off a closing one. It remains on
  `showMenuSheet` until a parent card owns the row.

## Alternatives considered

**Keep the modal route and only drop the barrier's colour** — which is what the
dimming fix did. The reader-visible defect goes away, but the card still sits at
the dock seam rather than against its trigger, and it still owns a navigation
entry it does not need; the shape was the remaining difference from the
reference, so this leaves the work half-done.

**A Flutter `MenuAnchor`** — it mirrors Material's menu semantics, not the
reference's placement hook, so the pin's `side`/`align` enums, its per-surface
caps and its clamp-without-flip rule would all be re-expressed through a widget
that does not take those inputs. Fidelity rejected it, not capability.

**A `PopupRoute` per menu** — still a route, so the back press and the anchor's
lifecycle become route work again. `OverlayPortal` with an explicit dismissal set
keeps the card and the route separate.

**Flipping the card when neither side has room** — the reference clamps and never
flips, so a flip is our invention. A seat that has no room on either side is
named rather than given a behaviour the pin does not have.

## Consequences

`showMenuSheet` remains the opener for surfaces that are genuinely routes; the
family's seats open the anchored card. The remaining `Navigator.pop` call sites
in the app are inside dialogs and sheets, where popping the route is correct —
the card subtrees carry none.

A seat that needs a flip rather than a clamp has no reference behaviour to copy;
name it instead of inventing one.
