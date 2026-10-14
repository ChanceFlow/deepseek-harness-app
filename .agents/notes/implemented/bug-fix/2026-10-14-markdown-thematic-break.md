# Agent Note: A markdown rule is a block, and what it beats

Status: implemented

## Problem

Assistant bodies and previewed `.md` files render through `MarkdownParser`, and
its vocabulary had no thematic break: three or more `-`, `*`, or `_` drew as a
paragraph of markers. The reference renders `thematicBreak` as an `<hr>`
(`reference/deepseek-harness/packages/client/ui-primitives/src/markdown/render.tsx:290`)
styled at a half-pixel `border-l2`
(`.../markdown/MarkdownText.module.css:143-149`), and drops it from a summary
(`.../markdown/plain-text.ts:71`). The same gap held the reference's
`listItem > thematicBreak` and `blockquote > thematicBreak` shapes — `- ***`,
`1. ***`, `> ---` — and it hid a precedence trap: the port had no setext
heading, so a rule read before the reference's own precedence would turn
`text` + `---` into a paragraph plus a rule where the reference sets an h2.

## Decision

- `ThematicBreakBlock` joins the block vocabulary: three or more of one marker,
  spaces or tabs allowed between them, up to three leading spaces and trailing
  whitespace. The line is read before a bullet or an ordered marker — which is
  what makes `- ---` and `* ***` the break itself — and after an open
  paragraph's setext underline.
- A `-` or `=` underline under open paragraph text emits a heading (h2, h1);
  this is the reference's precedence and the reason `text` + `---` stays a
  heading.
- A break closes an open paragraph, list, or quote. A line under a list item or
  a quote is not paragraph text, so `- a` + `---` closes the list and rules,
  as the reference reads it.
- A container holds a rule when the rule is its whole content:
  `BulletEntry.block`, `OrderedEntry.block`, `BlockQuoteBlock.block`, null
  being the item's text lane — the reference's `listItem`/`blockquote >
  thematicBreak`.
- The renderer draws `Divider` at 0.5px in `borderL2` with no ink of its own,
  taking twice the sibling gap (the reference's 32px against a paragraph's
  16px); a list row whose content is a rule centers its marker on the rule.
- The plain-text projection drops a rule, and a container reads the block it
  holds, exactly as `plain-text.ts` does.
- Boundary held: the port still has no indented-code lane, so a four-space
  `---` stays text (the reference reads code).

## Alternatives considered

A rule with no setext heading was rejected: `text` + `---` is an h2 in the
reference, and break-first would render a paragraph and a rule there — trading
one divergence for another. Counting any dash run under a paragraph as a rule
fails the same way. Implementing only the top-level break and leaving
containers inline was rejected: `- ***`, `1. ***` and `> ---` are the
reference's own rule inside a container, and an item that holds only a rule
loses no text. A general block-body model for containers — recursive item and
quote parsing — is deferred rather than rejected: this port flattens nested
lists onto two rendered levels by its own documented simplification, and that
model change is larger than the break. A `CustomPainter` for the rule was
rejected under the framework-component rule; `Divider` is the component for a
rule, and the markdown exception does not reach it.

## Consequences

`---`, `***`, `___`, `****`, `- - -`, `- ---` and `* ***` now draw a rule
wherever a body renders: the transcript, reasoning and compaction bodies, and a
previewed markdown file, whose body the preview sheet hands to `MarkdownText`
as markdown rather than as a fenced source block. `text` + `---` and
`text` + `===` set headings instead of folding into a paragraph, and `- ***`
loses its literal asterisks for a marker and a rule; a summary of a body that
is only a rule is empty.

Still unported, and each visible: indented code (`    ---` stays text), HTML
blocks, a block body beyond a lone rule inside an item or a quote (a fence or a
second paragraph there keeps folding into the item's text lane), and the inline
`***bold italic***` shape, whose asterisks the inline parser splits.
