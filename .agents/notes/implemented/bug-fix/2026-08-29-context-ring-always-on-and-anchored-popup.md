# Agent Note: Context ring stays on; its panel opens as an anchored popup

Status: implemented

## Problem

Users reported the composer ring "disappears all the time" and that its
tap-open panel is a bottom dialog where the web shows a popover anchored
to the meter. The reference confirms both readings' premises with a twist:
the web `ContextMeter` (`reference/deepseek-harness/packages/client/
ui-conversation/src/client/skeleton/ContextMeter.tsx`) does hide entirely
without data (line 72 `if (context === null) return null`), so the mobile
`SizedBox.shrink` was faithful port — but the mobile composer is the
always-visible surface users stare at, and the ring sits in the same dock
`Row` as the send control: every cold-bound session, every switch to a
session whose history has not loaded (the per-session `StateStream` seeds
`null` until the fold republishes after replay), and every new session
before its first usage sample collapsed the 14px seat and reflowed the
send button beside it. On the web the same hide is invisible because the
meter owns a fixed right-side slot and session views remount whole. The
panel deviation was real: web opens an anchored popover
(`ContextMeter.module.css` `.panel`: menu background, r12, inverted
hairline, `shadow-lv3`, 264px, closes on outside click and Escape); the
port shipped a `showDialog` with a bottom-aligned `Dialog`.

## Decision

The ring is a permanent composer seat. Without a usable reading
(`projectedTokens ?? pressureTokens` and `contextWindow`, the same
occupancy gate as web `contextOccupancy` in `StatsLine.tsx:191-201`) it
paints a static `outlineVariant` circle — the indicator's own track drawn
as a placeholder (`DecoratedBox`, not a 0-value
`CircularProgressIndicator`: that animates its track-in, reads as a
spinner to the app-wide type finders that assert activity spinners
absent, and the composer must never lie about activity). It is inert:
plain `contextLabel` semantics, no button role, no popup — the panel's
figures need a reading. With data the native determinate ring returns and
tap opens the composition panel through `MenuAnchor`, the stock Material
anchored popup: `menuChildren` is the unchanged panel content, and the
menu surface reuses the house chrome constants (`surfaceContainer`,
elevation 3, `kShapeMenuSheet` 12, `outlineVariant` hairline) declared as
`MenuStyle` — the same family `showMenuSheet` and the session-verb sheet
carry, imported from `theme.dart`, not copied. `consumeOutsideTap` keeps
a dismiss from double-firing the trigger; a mid-open loss of capacity
closes the stale panel in `didUpdateWidget`, the web meter's availability
effect (`ContextMeter.tsx:50-52`). The earlier "deviation §8.1" comment
cited a section that exists in no doc; the deviations live here.

## Alternatives considered

- **Keep web's hide-when-null exactly**: rejected — on this surface the
  rule is the defect; the reflow beside the thumb's primary target is the
  perceived flicker.
- **0-value `CircularProgressIndicator` as the empty state**: rejected —
  a determinate-0 indicator is still that type, and the timeline's
  no-spinner assertions and the composer's silence rule break on it.
- **`showModalBottomSheet`/`showDialog` kept**: rejected — the reference
  is an anchored popover; `MenuAnchor` is the framework's popup with
  outside-tap and Escape dismissal, no custom chrome.
- **Fixing the null window in the adapter/controller**: out of scope —
  the per-session reset on rebind is deliberate (the leaving session's
  reading must not flash under the entering one's header).

## Consequences

The ring never leaves the composer; occupancy reads appear on arrival.
Partially supersedes
[the sidebar/context-ring note](../feature/2026-08-19-sidebar-visibility-context-ring.md):
its occupancy formula and fold port stand; its "renders once a provider
reports" visibility sentence and the dialog panel are this note's facts
now. New ARB key `contextLabel` in both locales. The web's segmented
breakdown bar stays unported (panel content unchanged); a permanently
visible meter now shows an empty circle even in sessions that never bill.
