# Agent Note: A reply reads like a document

Status: implemented
Surface: `flutter/app/lib/ui/chat/markdown/markdown_parser.dart`,
`flutter/app/lib/ui/chat/markdown/markdown_text.dart`, `docs/spec.md`

## Problem

The transcript's own chrome had two passes; the thing it exists to carry had
none. Rendering a reply that used the whole markdown vocabulary showed six
defects, and the first two are the readable-versus-not ones:

- **Source wrapping reached the screen.** A single newline inside a
  paragraph rendered as a line break. Agents wrap their output near 80
  columns, so a paragraph arrived on a 360dp phone as ragged half-lines
  breaking mid-clause — the text was re-wrapped twice, once for a width
  that is not this one.
- **Blocks had no space between them.** The renderer emitted a `Column` of
  blocks and nothing else, so a paragraph, a table, a heading, and a quote
  ran together in one undifferentiated stack.
- **Numbered lists were not lists.** The parser knew bullets only, so `1.`
  fell through to paragraph text: no marker column, no hanging indent, and
  a wrapped item aligned under its own number.
- **A quote's rule was 20px tall** regardless of the quote, because the bar
  was a fixed-height `Container` beside the text.
- **A heading could be smaller than its own paragraph** — `h2` mapped to
  `titleSmall` at 14 against a 15px body.
- **Nothing was selectable and code blocks had no copy**, so lifting one
  path out of a reply meant copying the whole message.

## Decision

- **A newline inside a block is a soft wrap.** `foldLines` joins the source
  lines of paragraphs, quotes, and list items: a space between Latin
  characters, nothing where either side is wide, and a kept break after two
  trailing spaces or a backslash. One wide side is enough to drop the space
  — CJK prose routinely runs half-width punctuation, so `封顶,` ending a
  line must still join tight.
- **Space states the relationship between blocks.** 16 before a heading, 6
  after it, 10 between siblings — the transcript's three-gap rule applied
  one level down.
- **Ordered lists are a block type.** `OrderedListBlock` carries the
  source's own numbers, so a list that starts at 3 renders from 3. Both
  list kinds put the marker in a fixed column, which is what makes a
  wrapped item hang under its text.
- **An indented line continues the item above it.** Source wrapping must
  not split one list into a list plus a paragraph.
- **Headings stay inside the reading scale:** 17/700, body/700, then
  body/600 in the variant ink. A reply is not a web page, and no heading
  drops below the size of the prose under it.
- **Payload reads as data through the face alone.** Inline code steps down
  to 0.92 of the body size and drops the tint: a span background paints a
  full-height band with no padding, which on a wrapped path reads as a
  highlighter stroke through the paragraph.
- **A code block is a card that hands over its contents:**
  `surfaceContainerHigh`, hairline, `kShapeCard`, a language label when the
  fence names one, and its own copy button. The body is a `SelectionArea`,
  so a path can be taken without the message around it.

## Alternatives considered

- **`WidgetSpan` chips for inline code.** Padding and a radius at the cost
  of an unbreakable box: a long path in backticks would overflow the column
  instead of wrapping.
- **Full CommonMark lazy continuation.** A non-indented line after a list
  item joining that item surprises more often than it helps; requiring the
  indent keeps the rule predictable.
- **Dropping the space at every wide boundary only when both sides are
  wide.** Leaves a visible space inside Chinese prose written with ASCII
  punctuation, which is most of it here.
- **One `SelectionArea` around the whole transcript.** Selection would span
  messages, and a drag near the edge fights the scroller.

## Consequences

- Two parser tests changed with the contract (the quote fold and the
  non-table pipe paragraph now join with a space); six cover the new folds,
  ordered lists, and continuation, and a widget test file covers the
  rendered marker column, block gaps, code-block copy, and selectability.
- `docs/spec.md`'s markdown line states the folding rules and drops its
  stale Kotlin/Compose wording.
- Tables still render equal-weight columns that a phone can crowd; a wide
  table wants horizontal scroll, which this pass did not add.
