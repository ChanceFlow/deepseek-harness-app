# Agent Note: Timeline jump-to-bottom floating button

Status: implemented

## Problem

A long conversation leaves the reader stranded mid-history: after scrolling
back to re-read old turns there is no one-click way back to the newest
content. The user asked for a floating button on the timeline that glides to
the bottom in one tap, built with native components, and that stays hidden
while the view already sits at (or near) the bottom.

## Decision

The chat timeline gains a native Material small `FloatingActionButton`
(`chat_screen.dart`) that appears at the timeline's bottom-right corner only
while the reader is away from the bottom, and glides the view back to the
newest content on tap.

- **Visibility contract mirrors the follow pin.** The existing follow
  contract pins the view while the reader sits within
  `kFollowThreshold` (24px) of the bottom. The FAB shows exactly when that
  pin does not hold and the timeline is scrollable at all
  (`maxScrollExtent > 0`); it folds away inside the threshold, on a
  non-scrollable timeline, and over the outline skim surface (which owns no
  scroll controller client).
- **`_showJumpToBottom` is a real state field.** `_onTimelineScroll`
  re-derives it on every reader-driven scroll (setState only on change), and
  driven paths sync it explicitly after they settle: `_scrollToBottom`'s
  finally block folds/raises it after a follow or restore lands, the
  session-switch branch resets it to hidden, and an outline toggle re-derives
  it in a post-frame callback (the remounted list starts at the top, where a
  jump affordance belongs). The scroll listener is `_followDepth`-guarded, so
  driven glides never re-evaluate it mid-glide.
- **The tap glide is a driven scroll.** `_jumpToBottom` pins (`_pinned =
  true`) under the follow-depth guard, glides over
  `Duration(milliseconds: 300)` easeOutCubic, and rescinds the guard +
  re-syncs in `finally` — the glide neither unpins the view nor records a
  mid-glide reading position.
- **Native styling rides the repo's native-component contract.** The FAB is
  `FloatingActionButton.small` with `heroTag: null` (sibling send/stop FABs
  must not fight over the shared hero), the neutral `surfaceContainerLow`
  fill with an `onSurfaceVariant` arrow-down glyph so it never competes with
  the brand-filled composer seat, elevation 2, and the
  `jumpToBottomTooltip` l10n key (en "Jump to bottom" / zh "跳到底部").
  Appear/disappear transitions use the M3 page motion duration
  (`Duration(milliseconds: 200)`) through `AnimatedSwitcher` fade+scale.

## Alternatives considered

- **Always-visible FAB** (no visibility gating): rejected — the user
  explicitly asked for the control to disappear at (or near) the bottom; an
  always-visible seat would duplicate the composer's send affordance visually
  and add noise to a pinned view that needs no jump.
- **Brand-fill FAB (theme default)**: rejected — the composer's primary seat
  is brand-filled when actionable; a second identical-looking circle would
  compete with it. The neutral selector fill signals "navigation tool", the
  same convention as the composer's idle circle.
- **Reuse `_pinned` directly as visibility**: rejected — `_pinned` is a
  follow-contract flag mutated without setState; button visibility needs a
  rebuild boundary, so it is a separate field synced from the same geometry.
- **Support the outline skim surface with its own FAB**: rejected — the
  outline owns no scroll controller client by design (its `didUpdateWidget`
  path returns early), it starts at the top by intent, and threading a
  controller into it would change outline scroll semantics
  (read-offset writes, follow). The FAB is a main-timeline affordance; the
  outline keeps its skim behavior untouched.
- **Hand-rolled `InkWell` + `Container` circle**: rejected — the repo's
  native-component contract (timeline rows, sidebar) calls for real Material
  component semantics (ripple, focus, tooltip); `FloatingActionButton.small`
  is the native floating button.

## Consequences

- Long conversations gain a one-tap way back to the newest content; the FAB
  folds away exactly when the view is pinned, offering no dead control at the
  bottom.
- The jump glide reuses the follow-depth guard, so it never corrupts `_pinned`
  or the persisted reading offset; the finally-sync keeps button visibility
  consistent after every driven landing (restore, follow, tap).
- Deliberate scope deltas: the outline skim mode shows no jump button (its
  own scroll surface); reading-position persistence and follow behavior are
  unchanged.
- Three new widget tests pin the behavior through real entry paths: FAB
  folded at the bottom, raised on scroll-away, tap glides back and folds it,
  hidden inside the 24px threshold, absent on a short timeline, and absent
  over the outline (reappearing when the list remounts at the top).