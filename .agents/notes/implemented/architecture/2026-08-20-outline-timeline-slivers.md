# Agent Note: Outline timeline renders as sliver composition

Status: implemented

## Problem

`OutlineTimeline` built one `List<Widget>` holding every turn header and
every row, then fed it to a `ListView.separated` adapter. The rows were all
constructed on every build even when off-screen, so a long outline paid
widget construction for the whole session and shipped no structural
scrolling benefit beyond a plain list. Flow mode has the same shape
(`ListView.separated` of flat rows) and stays untouched by this change.

## Decision

`OutlineTimeline` composes `CustomScrollView` slivers instead of adapter
items:

- Each turn header is a `SliverToBoxAdapter` keyed
  `ValueKey('group-<turn|index>')` (the key moves from the header widget to
  the sliver so scroll-state continuity keys the scroll element).
- Each expanded turn's rows are one `SliverList.separated` slice: rows
  build only when the viewport reaches them, and a collapsed turn
  contributes no row sliver at all.
- The ledger rhythm stays one 8px gap between elements — `SliverPadding`
  bottoms every element except the last, which sits flush, exactly the old
  separator layout.
- Behavior parity is load-bearing and covered by the existing tests:
  turn-group filtering (`TimelineQueue`/`TimelineApprovalRequest` excluded),
  collapse/expand toggling, `Expand all`, persistence restore, and
  `ValueKey(timelineKey(item))` identity on rows all behave as before. The
  outline keeps its own scroll surface (no auto-follow, no read-offset
  persistence), unchanged. Flow mode (`_timelineBody`) is not touched.

## Alternatives considered

`SliverPersistentHeader(pinned: true)` for sticky turn headers was
considered and set aside: the header's height varies with its label, prompt
preview, and tool summary, and a pinned delegate needs a stable extent —
pinning is a visual enhancement, not parity, and belongs to a later change
with a fixed-height header design. A single `CustomPaint` canvas for the
whole timeline was rejected outright: it forfeits text selection, semantics,
lazy layout, and per-row repaint boundaries for no measured win. Wrapping
rows in per-row `SliverToBoxAdapter`+`SliverPadding` (instead of
`SliverList.separated`) was rejected: it rebuilds every row widget eagerly,
defeating the lazy-build point.

## Consequences

Long outlines no longer materialize off-screen rows; collapsed turns are
truly free. The `CustomScrollView` keeps the default primary scroll
controller, so the outline's scroll surface behaves as before.
`turnBoundaryRow` and row widgets are untouched, so visual output is
identical. The flow-mode list keeps its own later optimization path.

## Testing

`chat_screen_test.dart` adds "outline scrolls lazily to later turns":
through the real ChatScreen entry, a five-turn outline under a short
viewport scrolls its own scroll surface to reach the last turn's message.
The pre-existing outline tests (grouping, collapse/expand all, persistence
restore in `composer_bar_test.dart`) pass unchanged.