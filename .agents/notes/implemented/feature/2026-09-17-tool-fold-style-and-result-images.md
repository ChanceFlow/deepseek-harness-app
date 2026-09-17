# Agent Note: Tool-call folding reads as the reference fold, and result images render

Status: implemented

## Problem

Two surfaces diverged from the reference web client's look:

1. **Folded tool batches were a foreign surface.** A consecutive run of tool
   calls collapsed into a rounded, filled, bordered chip with a bold title —
   a card the reference has nowhere. The reference folds a *turn's* process
   behind a bare header row (`TurnProcessNodeView.module.css`): a full-width
   24px line, 8px bottom padding, a `0.5px` `border-l2` rule, a 14px
   non-bold label, and a 16px chevron that rotates −90° → 0° over 100ms. Its
   member rows are the shared tool-row atom
   (`[16 leading] gap6 [title 13] gap8 [2×2 dot] gap8 [summary, ellipsized]`),
   nested with `ToolCallTree`'s 22px indent + hairline guide; the summary is
   set in the body font, never monospace.
2. **A `read_image` result showed no picture.** The reference renders those
   results as their own toolview: the tool-result block's
   `{type: 'image', attachment}` blocks become a gallery — one image at a
   240px long edge with its aspect ratio clamped to `[0.25, 4]`, or 64px
   tiles for several — under the model-facing envelope text, each frame
   opening a full-viewport lightbox. Our `tool/result` fold read only the
   text blocks and dropped every image.

## Decision

**The batch header is the reference fold header.** `ActivityGroupRow` drops
its card (fill, radius, border, side padding). The header is a full-width
line over an 8px gap and a `0.5px` `outlineVariant` rule, its label in
`onSurfaceVariant` at body weight, and a single 16px chevron that
`AnimatedRotation`s between the closed and open seats over
`DshMotion.durationMicro`. A closed fold keeps 8px below the rule. The state
seat (activity dot / check / error cross) and the trailing failed count stay:
they are this client's own state vocabulary, and a running batch has no
reference header to borrow from because the reference never folds a live
turn.

**Members borrow the nesting recipe.** The expanded members take
`ToolCallTree`'s geometry — 22px left margin, 8px padding-left, a `0.5px`
hairline guide, 4px between rows — instead of the padded inner box.

**The tool row atom loses its invented emphasis.** Title and summary are both
body weight in `onSurfaceVariant` (the reference's two-grey pair collapses to
the one secondary text role this theme maps), separated by the reference's
2×2 dot. The summary drops `monospace`; the IN/OUT payload keeps it.

**Result images render through the durable seam.** `TimelineToolCall` gains
`images`, folded by `timeline_reducer` from the ToolResultBlock's content
blocks (`{type: 'image', attachment: {attachmentId, mediaType, bytes, width,
height, name?}}`) for both `tool/result` and nested `tool/ptc-dispatch`. A
block that does not narrow (no id, a non-image media type) is dropped, the
position the reference's `imageReferences` takes; the row still renders its
text. `ToolImageGallery` frames each reference and fetches bytes on demand
through the same session-authorized `readAttachment` loader user-attached
images use — bytes are never inline on the wire. For a row carrying images
the card replaces the generic IN/OUT body, exactly as the reference toolview
replaces it: gallery, then the envelope text as the meta line.

**The design harness works in the container toolchain.** Two defects made
`scripts/render_design.py` a no-op here: the runner hands the test isolate a
curated environment, so `DSH_DESIGN_SHOTS` never arrived, and the Han face
was cached under `$HOME`, which the toolchain container does not mount. The
gate now travels as `--dart-define`, the face path travels beside it, and
`--fetch-fonts` caches into `flutter/app/test/design/fonts/` (gitignored) —
inside the tree the container mounts.

## Alternatives considered

- **Replacing the batch group with the reference's turn-level fold.**
  Declined: the ask was the style, and the batch grouping is this client's
  own behavior with its own tests.
- **Dropping the header's state seat to match the fold header exactly.**
  Kept deliberately: a batch can be collapsed while it runs, where the
  reference has no header at all, so the seat is the only running cue
  besides the sweep.
- **Inlining image bytes on the result event.** The wire carries references
  only; inlining would diverge from the host contract.
- **A module-level image cache.** Declined for now (per-frame state mirrors
  the existing user-image row); the reference's evicting session-scoped cache
  is the upgrade path if re-fetching shows up in practice.

## Consequences

- Folded batches and tool rows read as the reference's flat, underlined
  transcript chrome; single rows and group members share one atom.
- A `read_image` result shows its picture, with a lightbox on tap.
- New design shots `tool-image` (light/dark) plus the restyled
  `timeline-folding*`; new reducer tests for image narrowing and a widget
  test for the image card.
