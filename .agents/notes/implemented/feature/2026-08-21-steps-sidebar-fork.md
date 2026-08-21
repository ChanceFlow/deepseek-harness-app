# Agent Note: Step density, the sidebar, and a per-message fork

Status: implemented
Surface: `flutter/app/lib/ui/chat/*`, `flutter/app/lib/ui/shared/session_tree.dart`,
`flutter/packages/domain/lib/model/chat_message.dart`,
`flutter/packages/harness_adapter/lib/src/timeline_reducer.dart`

## Problem

The visual system landed on the transcript and stopped there. Four defects
survived it:

- A tool step is one line of text in a 48px row. `ExpansionTile`'s stock
  trailing chevron is a 24px glyph, and the tile sizes itself to its tallest
  child, so an 18px line rode 30px of chrome. A run of steps read as a list
  of far-apart headings.
- A blank band sat between the app bar and the transcript — the panel's 12px
  top inset plus a 4px spacer — and the scrolled list clipped its first row
  inside it, which reads as a rendering fault rather than a gap.
- Two full-width rules crossed the sidebar. Nothing drew them on purpose:
  an expanded `ExpansionTile` rules itself off top and bottom by default.
- The sidebar never got a pass. Its primary action was a hand-drawn slab
  (`OutlinedButton` overridden to a filled background with a border), its
  section label was set as a heading, and its rows carried the transcript's
  prose leading, so the list ran 56px per row.

Separately, the reply footer omitted fork with a comment saying the wire had
no per-message anchor. It does: `session.fork` takes `atSeq`, and the host
contract says a message's fork button passes the message seq.

## Decision

- **A row is as tall as its line.** Both step tiles shrink the ambient icon
  size to 18 through an `IconTheme`, drop their inner vertical padding, and
  set `minTileHeight: 30`. The chevron keeps its rotation. Tool and reasoning
  rows land at 34px, and a step-to-step pitch of 40px.
- **The transcript meets the bar.** The panel's top inset and spacer go, so
  content slides under the bar the way M3 expects.
- **Space divides, lines do not.** Every `ExpansionTile` in the app sets
  `shape` and `collapsedShape` to `Border()`.
- **The sidebar joins the system.** The drawer takes `surfaceContainer` —
  the chrome tone the bar and dock already use. New session becomes a stock
  `FilledButton.icon`, the panel's one filled seat, in the framework's own
  height and shape; its glyph is `add_comment_outlined`, because the
  composer's `+` owns the plus on the same screen. The section label drops
  to `labelMedium`, the group header to 40px, and one-line rows take
  `height: 1.2` on the body scale that transcript prose set loose.
- **Fork is a message verb.** `ChatMessage` carries `seq`, the reducer fills
  it from the event being folded, and `ForkSession` carries `atSeq`. The
  reply footer gains a fork seat beside copy; the reader's own bubble opens
  copy and fork on long-press, at the press point. A message with no logged
  position offers no fork instead of forking somewhere else.
- **Menus lift on a soft shadow.** `PopupMenuThemeData` takes a 28%-alpha
  shadow and `surfaceContainerHigh`; the stock opaque black reads as a hard
  outline on a two-item panel.

## Alternatives considered

- **A fixed row height on the step tiles.** Sets the same trap for the next
  line-height change; the chevron was the actual cause.
- **A custom `trailing` chevron.** `ExpansionTile` only rotates the one it
  builds itself, so a custom widget trades the animation for the size.
- **Keeping the immediate long-press copy on the bubble.** With two verbs a
  menu is the honest affordance, and it names them.
- **Fork on the sidebar row only.** That is session-level fork, already
  present; the reference anchors the cut at a message.
- **Passing the message id instead of the seq.** The host resolves a turn
  boundary from a seq; an id would need a lookup the client cannot do.

## Consequences

- `session_panel_test` asserts the filled seat's rendered contrast pair
  rather than a style override, and `message_icon_actions_test` covers the
  menu, the missing-seq case, and the dispatched `ForkSession(atSeq:)`.
- `timeline_reducer_test` pins the fork anchor: messages carry the seq of
  the event they folded from.
- `flutter/app/AGENTS.md` gains the chrome-tone rule for the drawer and the
  one-line-row leading exception.
- The brand lockup in the drawer header is still an imported asset with its
  own black badge; it did not get a pass.
