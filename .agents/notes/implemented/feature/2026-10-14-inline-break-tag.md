# Agent Note: A `<br>` in a body breaks the line

Status: implemented

## Problem

GFM has no line break inside a table cell: the cell ends at the row's `|`, so a
body that needs two lines in one cell writes `<br>`, the spelling a reader
already knows. The reference renders raw HTML literally — no HTML parser enters
its pipeline, and its `html` case returns the source text
(`reference/deepseek-harness/packages/client/ui-primitives/src/markdown/render.tsx:333-335`)
— so a cell shows `a<br>b`. This client was faithful to that and showed the
same, which is the cost the reader pays: the reference's `<br>` element comes
only from a mdast `break` (two trailing spaces or a backslash), a shape a table
cell cannot express at all.

## Decision

- The inline tokenizer reads `<br>`, `<br/>` and `<br />` — any case, with
  whitespace before the slash or the close — as a line break, written as the
  `\n` this vocabulary already carries for hard breaks
  ([markdown_parser.dart](../../../../flutter/app/lib/ui/chat/markdown/markdown_parser.dart)).
  No renderer, table layout, or frozen-block path changes: `Text.rich` already
  breaks on the newline and a row grows to its tallest cell.
- The tag is read wherever an inline run renders: a table cell, a paragraph, a
  list item, a quote, and inside bold or italic. A code span keeps it literal,
  because the span is consumed as a unit, and a link label keeps its raw text.
- Every other tag stays literal, as the reference has it: `<b>`, `<div>`, and
  an attributed `<br class="x">` are text.
- The plain-text projection folds the break to a space, where the reference
  projects the literal tag. The summary lane follows this client's own rule
  ([the rule note](../bug-fix/2026-10-14-markdown-thematic-break.md)).
- This is a deliberate divergence from the reference, recorded as one. The
  reference's literal raw HTML stays its contract; the phone client answers
  the in-cell break and nothing wider.

## Alternatives considered

A general raw-HTML lane was rejected: the reference's own pipeline carries no
HTML parser, a port would need a parser plus a sanitizer and a policy for every
tag, and no request reaches past `<br>`. Splitting a cell into extra table rows
— what some clients do — was rejected: it changes the table's shape rather than
the run inside it, and it breaks the reference's column grid. A dedicated
`BreakInline` inline type was rejected because the vocabulary already represents
a hard break as `\n` inside a text run, and two representations of one fact
drift apart. Recognizing only the exact `<br>` spelling was rejected as too
narrow: `<br/>` and `<br />` are what a body writes. Rendering the tag as a
space was rejected: the second line is the entire point. Changing the reference
client instead (a `html` case that maps `br`) was rejected: the pin is the
contract this repository reads, not a fork it edits.

## Consequences

A table cell can carry several lines and its row grows to fit them; the same
tag breaks a paragraph, a list item and a quote. A body that meant `<br>` as
visible text loses it, which is the divergence being taken. `docs/spec.md`
states the tag as the one raw HTML this client reads, and a later parity pass
over the pin's markdown vocabulary must not "restore" the literal tag.
