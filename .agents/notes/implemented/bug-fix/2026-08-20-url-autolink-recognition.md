# Agent Note: Bare-URL autolinks follow the web reference's GFM rules

Status: implemented

## Problem

The markdown parser recognized a bare URL only when a space, newline, tab,
or one of `` '([{<"' `` preceded it. A URL glued to CJK text — the default
in Chinese prose (`详见https://example.com`) — stayed plain text unless
the model emitted explicit markdown link syntax. `www.` links opened
`https://…` where the web reference opens `http://…`; trailing `"`/`*`/`]`/
`_`/`~` runs were not trimmed; and a `[` without its own `](` swallowed a
later bracket pair's link — and any bare URL in between — through a greedy
`](` search.

## Decision

`MarkdownParser.parseInlines` scans bare URLs with the rules the dsh web
reference renders (micromark's GFM autolink-literal tokenizer united with
mdast-util-gfm-autolink-literal's text transform — the stack under
`reference/deepseek-harness/packages/client/ui-primitives`):

- `http(s)://` links unless an ASCII letter immediately precedes; `www.`
  links after start of text, whitespace, or a punctuation/symbol
  character, and opens `http://` + the raw span. Both schemes match
  case-insensitively.
- The span runs to Unicode whitespace, keeping balanced parentheses; a
  trailing run of `!"'&*),.:;<=>?_]~` (with `&word;` groups and `]`
  lookahead rules) that reaches the end is trimmed. Full-width
  punctuation is span material: `https://example.com，ok` links whole,
  matching the reference.
- A domain whose last two non-empty dot segments carry `_` is rejected;
  an `http(s)://` body must open with a non-punctuation character.
- Link labels close at the first depth-zero `]`, and `](…)` must follow
  immediately — never a `](` from a later bracket pair.

Punctuation/symbol membership lives in `unicode_punct.dart`: a committed
BMP range table of Unicode 15.0 categories `P*`/`S*` — what
micromark-util-character's `\p{P}|\p{S}` tests — because Dart's RegExp has
no Unicode property escapes. Surrogate halves classify as
non-punctuation.

Deliberate divergence: a bare `www.` with nothing behind it stays text
where the reference links `http://www` — a `www` host is not a meaningful
target.

## Alternatives considered

- Relaxing only the predecessor set: leaves the `https://` www prefix,
  trim set, domain gates, and greedy `](` untested against the reference.
- A linkify package (flutter_linkify): adds a dependency and its own link
  vocabulary instead of the pinned reference contract.
- Porting micromark's tokenizer wholesale: the transform's extra coverage
  reduces to the www predecessor gate above; a full state machine is
  disproportionate for the MVP vocabulary.
- Generating the range table with a `--check` gate (the design-token
  pattern): the generator would depend on the host Python's Unicode
  version and drift across machines; the table changes only with a
  Unicode major release, so committed data with classification tests is
  the stable form.

## Consequences

Assistant and user prose in mixed Chinese/English auto-links bare URLs
without waiting for markdown link syntax; behavior is pinned by parser
unit tests plus a 27-case differential probe run against the reference
stack. Email autolinks and the reference's clickable inline-code URLs
(`` `https://…` ``) remain outside the MVP vocabulary. Astral-plane
punctuation scans as surrogate halves and misclassifies as span material
— the path swallows it identically, so only underscore segmentation of
exotic domains can differ.
