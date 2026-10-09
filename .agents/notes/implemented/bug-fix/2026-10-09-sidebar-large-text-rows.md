# Agent Note: Sidebar rows yield to the platform's text scale

Status: implemented

## Problem

Two rows in the sidebar paint outside their clip at large platform text steps,
so a reader on the largest setting sees striped rows in debug and cut text in
release:

- **The brand wordmark** (`flutter/app/lib/ui/chat/brand_wordmark.dart`): a row
  of intrinsic-width parts — the fish, the word, the HARNESS plate — that the
  sidebar's slot cannot hold once the two text runs scale. Measured at the
  sidebar's mounted width: 13px over in the drawer at 1.3×, 26px in the embedded
  pane, and 318px at 3.0×.
- **The workspace group header** (`flutter/app/lib/ui/chat/session_panel.dart`,
  `_GroupSection`'s `ExpansionTile.title`): the label and the session-count
  caption share the row, and the caption's intrinsic width grows with the step.
  15px over at 2.0×, 125px at 3.0×.

A third error at 3.0× is the **second group's header** — the same widget on the
same line, which is why finding it needed the error sink rather than the deduped
console dump. Neither row is a fixed height or a scaled drawing; both are
`Row`s whose children cannot yield.

## Decision

**A row yields room; it never shrinks or drops its text.**

- The wordmark's two text runs are `Flexible` and ellipsize inside their share.
  The fish and the plate keep their size, so the mark stays a mark.
- The brand row's tap target is `kMinInteractiveDimension` tall
  (`Center(widthFactor: 1)` keeps the mark hugging its ink and at the x it had).
- The group header decides between one line and two by measuring the caption
  with the same style and text scaler it paints with (`_intrinsicWidth`). While
  the caption fits beside the label the shipped row is used unchanged — label
  `Expanded` and ellipsizing, caption at the far edge. Only when the caption
  alone cannot fit does the title become a two-line `Column`: the label, then the
  caption with `maxLines: 2`.
- The condition is **the caption cannot fit**, not *the label must ellipsize*.
  The pin's header ellipsizes a long label and holds its meta at the far edge
  (`ui-workspace/src/client/rows/Rows.module.css` `.searchResultTitle`:
  `flex: 0 1 auto; min-width: 0; text-overflow: ellipsis`, against
  `.searchResultWorkspace`/`.searchResultMeta`: `flex: none`), so a two-line
  header for every long workspace title would be a new design, not a fix.

`flutter/app/test/ui/chat/sidebar_large_text_test.dart` pumps the real panel in
its drawer and embedded forms, and the wordmark alone in the slot the sidebar
gives it, at 1.0/1.3/1.5/2.0/2.5/3.0, and asserts that no error reaches the
framework's sink; it also pins the 48dp brand target and the one-line header at
the default step. The design harness renders a shot at a step of its own
(`DesignShot.scale`, `DSH_DESIGN_TEXT_SCALE`), which is how
`shots/sidebar-scale-20_*.png` sits beside its default twin.

## Alternatives considered

- **`FittedBox`, or a fixed row height.** The complaint class is text that gets
  cut; shrinking it to fit is the same defect wearing a hat, and a fixed height
  clips the second line.
- **Making the caption `Flexible` under the `Expanded` label.** Flutter gives
  every flexible child a share of the free space regardless of what it needs
  (measured: 105px of 210 to each), so the caption ellipsized at the *default*
  step while the label's half sat empty — worse than the defect it fixes.
- **`Wrap` or one `Text.rich` for the label and caption.** Neither can overflow,
  but both move the caption beside the label at every scale, against the pin's
  far-edge meta and the shipped header.
- **Stacking whenever the label needs to ellipsize.** The first cut of this fix:
  it removes the stripe too, at the cost of turning every long workspace title's
  header into two lines at the default step.

## Consequences

The default-step sidebar is pixel-identical to what shipped (the `drawer` shot
compares equal, both twins). The brand row's target is 48dp tall where it was
28; the group header keeps its dense 40 (the pin's own sidebar row is 34), and
at the steps where a caption cannot share the line the tile grows a line instead
of striping. The wordmark ellipsizes (`DeepSe…`) at 2.0×, which is the yield: the
mark stays and the reader keeps a word. The design sweep at 3.0× stripes other
surfaces too — `card_detail.dart`, `voice_hold_bar.dart`, three chat-screen rows,
`empty_hero.dart` and four settings rows — none of them owned here.
