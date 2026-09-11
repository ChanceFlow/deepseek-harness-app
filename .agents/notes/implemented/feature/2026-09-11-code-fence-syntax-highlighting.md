# Agent Note: Syntax highlighting and a line-number gutter for fenced blocks

Status: implemented

## Problem

Fenced code rendered as one monochrome `Text` run: every keyword, string,
number and comment in the agent's primary output took the same ink. `Fact 1`
of [design-standard.md](../../../../docs/design-standard.md) says the content
is the agent's — code and tool payloads are what the reader came for — and
`Fact 4` says they scan it. A reader cannot scan an undifferentiated block,
and a long block had no way to name a line: nothing on screen carried the
number a host error message refers to.

## Decision

- [code_highlight.dart](../../../../flutter/app/lib/ui/chat/markdown/code_highlight.dart)
  is a small, pure-Dart scanner that splits a body into five token classes:
  `plain`, `comment`, `string`, `number`, `keyword`. It covers the families a
  dsh transcript actually prints — Dart, the JS/TS pair, JSON, YAML, Python,
  shell and SQL — and every fence name it does not know returns one `plain`
  run, so an unrecognised language degrades to the previous rendering rather
  than to a guessed colour. It is a reading affordance, not a parser: no
  grammar, no scope, no nested-language support.
- Three token colours join `DshSchemeColors` in
  [theme.dart](../../../../flutter/app/lib/ui/theme/theme.dart) —
  `syntaxKeyword`, `syntaxString`, `syntaxNumber` — and the role table in
  [flutter/app/AGENTS.md](../../../../flutter/app/AGENTS.md) gains their row.
  Comments take `onSurfaceVariant` in italic, and `plain` overrides nothing,
  so the body's own `onSurface` ink still carries identifiers and punctuation.
  Every value is measured against `surfaceContainerHigh` — the surface a code
  card actually sits on — at >= 4.5:1, the same bar the light `warning` and
  `success` values were fixed to hold.
- A `plain` span carries no `TextStyle`, which is what keeps the unclassified
  majority of a body on one ink instead of on three competing ones.
- Highlighting runs only on a *closed* fence in a known language. A streaming
  fence renders plain: its tail is exactly the text still moving, and
  re-lexing it on every chunk would spend the frame budget the incremental
  parser already protects ([incremental.dart](../../../../flutter/app/lib/ui/chat/markdown/incremental.dart)).
- A block of `_kLineNumberFloor` lines or more grows a fixed line-number
  gutter to the left of a horizontally scrolling body, on `outline` ink with
  tabular figures. Shorter blocks spend no column on numbers.
- Tokens are painted, never copied: the copy button still hands over
  `block.code` verbatim, and the tokenizer is covered by a round-trip test
  holding that tokenizing loses, duplicates and reorders nothing.

## Alternatives considered

- **A syntax-highlighting package** (`flutter_highlight`, `highlight`,
  `re_highlight`): rejected. Each pulls a grammar bundle and a theme table
  sized for an IDE, none of whose palettes is the app's `ColorScheme`, and the
  repo's no-heavy-dependency and hand-written-decoder posture
  ([ADR-0001](../../../../docs/adr-0001-flutter-rewrite.md)) points the same
  way. The five classes a phone reader scans for do not need a grammar.
- **A `ThemeExtension` for the syntax palette**: rejected. It reopens the
  settled "no theme extensions" decision that `dsh_theme_test` holds, for
  three colours the existing `DshSchemeColors` extension already has a home
  for.
- **Reusing `success` for strings**: rejected. A state colour that doubles as
  a token colour stops meaning one thing; `syntaxString` holds the same green
  without the overload.
- **Numbering every block from its first line**: rejected. Two- and three-line
  snippets are the common case and the gutter costs a column on all of them.
- **Highlighting the streaming tail**: rejected. It re-lexes on every chunk to
  colour text that is about to change, and the tail is where a mid-token
  fragment would be misclassified most often.

## Consequences

- `CodeBlock` renders through `_codeBody`, which owns the gutter, the scroll
  axis and the token-to-style map; `_tokenStyle` is the only place a token
  class becomes ink.
- A code card's line count and the gutter's line count are the same by
  construction: the body never wraps (`softWrap: false`) and scrolls
  horizontally, so no line occupies two rows.
- A fence language this client does not know renders exactly as it did before
  this change; the set of known languages is `_aliases` and is cheap to grow.
