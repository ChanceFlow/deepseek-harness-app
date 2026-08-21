# Agent Note: Chat timeline restyle — proposal A (refined flat layout)

Status: implemented

## Problem

The chat timeline rendered every item at the same visual weight: an 8px
separator rhythm, a full-width divider per turn boundary, neutral leading
glyphs on tool rows regardless of run state, and a plain expanded-details
container. Long sessions were hard to scan: state, turn structure, and
payload carried no perceptual hierarchy.

## Decision

Timeline-only restyle (composer, app bar, and dock widgets are untouched)
shipped as proposal A of a three-skin prototype:

- Flow rhythm is one 16px gap between timeline items (web ChatView column
  gap), replacing the 8px separator.
- `TurnBoundaryRow` is a ledger-style micro label: 14px hairline tick +
  letterspaced caption text, left-aligned, instead of a centered
  full-width divider.
- `ToolCallRow` leading slot carries state-colored glyphs — success check
  (`--dsw-alias-state-success-primary`), business-blue spinner (running),
  error cross — and the title sets the monospace stack.
- Expanded tool details render as the web IN/OUT card: bordered
  `--dsw-alias-markdown-code-block` surface, r12, gutter labels `IN`/`OUT`
  with a hairline divider; failed output keeps the error ink.
- A streaming assistant message with text ends in a blinking 2×18
  business-blue caret (`_StreamingCaret`); empty-text streaming keeps the
  small circular loader.

Tool IN/OUT cards ride the `surfaceContainerLow` surface with r12 corners,
`IN`/`OUT` gutter labels and a hairline `outlineVariant` divider; failed
output keeps the `error` ink (post-2026-08-21 native-M3 removal — all
colors come from stock ColorScheme roles, no custom tokens).

## Alternatives considered

- Proposal B (layered cards): assistant turns in bg-layer-2 cards, inset
  reasoning quote, collapsible tool cards. Rejected: strongest separation
  but the heaviest visual chrome per turn; the user chose A.
- Proposal C (activity rail): left rail with turn stations and event
  ticks. Rejected: best long-session scanning, but requires a new left
  gutter layout in `ChatPanel` rows; the user chose A.
- Retyping the markdown body to the web 16/28: deferred — outside A's
  promised surface (rhythm/state/boundary/card/caret) and touches every
  markdown test layout.

## Consequences

- Timeline hierarchy reads from spacing, state color, and boundary labels
  without new surfaces; the mockup file stays as the decision artifact for
  B/C if they are revisited.
- Widget tests assert the IN/OUT gutter labels and the streaming caret key
  through the real screen entry path.
- Outline mode (`OutlineTimeline`, `TurnGroupHeader`) keeps its own
  boundary presentation; only the flow-mode `TurnBoundaryRow` restyled.
