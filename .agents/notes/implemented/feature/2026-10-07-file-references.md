# Agent Note: `@` file references in the composer

Status: implemented

## Problem

The host exposes path-only `@` mention discovery as `fileReferences/list`
(`reference/deepseek-harness/packages/api/session-controller/src/
file-references.ts`: namespace `fileReferences`, `list(agent, query, signal)`
answering `FileReferenceCandidate[]`, a `{path, kind}` record from
`packages/context/file-reference/src/types.ts`). The reference web client
registers it as an `inputTriggers` source
(`packages/client/ui-reference/src/client/index.ts`): typing `@` opens a menu
of ranked paths and accepting one lands an `@path` token in the draft.

The phone client had no `@` surface at all. The endpoint was one of the
unwired methods, and the composer offered only the `/` roster, so a reader who
wanted the model to read a file had to type its path from memory and could not
discover what the working directory even holds.

## Decision

- **`fileReferences/list` joins `DshRpcEndpoints`** and decodes into
  `domain.FileReferenceCandidate{path, kind}`. Both wire fields are required: a
  missing field or an unknown `kind` throws naming the field. The result is a
  bare JSON array, so it rides the envelope's `value` slot exactly like
  `commands/list`.
- **One repository method**, `listFileReferences(sessionId, query)`: the Agent
  lookup rides `agentId`, the wire-visible text after `@` or `@"` rides
  `query`.
- **The composer owns the text grammar, the controller owns the query
  lifecycle.** `app/lib/ui/chat/file_reference_picker.dart` mirrors the shared
  browser-safe token grammar (`packages/context/file-reference/src/
  grammar.ts`), formats the mention, and performs the insertion. An
  `UpdateFileReferences` action carries the live query; `ChatUiState.
  fileReferences` carries the last resolved query with its rows, and the menu
  renders only a holder whose query equals the live token — a slower answer to
  an earlier prefix never stands.
- **Debounce plus a sequence guard.** Keystrokes inside one path prefix
  collapse into one RPC (180 ms), and an answer the newest query superseded is
  dropped. A refused pull publishes the query with no candidates; the reference
  client reads a failed file lookup as an empty one, so the menu closes rather
  than offering rows the text no longer matches.
- **Directory rows keep the token open** (`@src/`) for the next level; a file
  row completes the mention and takes a separating space unless the draft
  already has one — the reference insertion rule
  (`ui-conversation/src/client/input/facade.ts` `insertReference`).

## Alternatives considered

- **Decode through a serialization library.** Rejected by ADR-0001 and
  `docs/spec.md` §Non-Goals: hand-written decoders with required-field
  semantics are the standing rule for this seam.
- **Hold the picker state in the composer instead of `ChatUiState`.** Rejected:
  the composer would own a second asynchronous source of truth beside the
  controller's, and a session switch would have to clear both; the `/` roster
  already carries its state in `ChatUiState.commands`, and the picker is the
  same kind of fact.
- **Query the host on every keystroke.** Rejected: each query walks the host's
  workspace index, and a path prefix is several keystrokes.
- **Reuse the `_PlusButton` sheet (`showMenuSheet`) for candidates.**
  Rejected: a modal sheet covers the composer and takes focus off the field the
  reader is typing into, while the `/` source already established the in-place
  band above the draft.
- **Quote every mention (`@"path"`).** Rejected: the reference grammar leaves a
  whitespace-free path unquoted so mentions stay readable and paste cleanly
  into a prompt.
- **Offer session references too (the web source combines files and
  sessions).** Deferred: the phone has no session-reference resolver wired, and
  the file surface stands alone without it.

## Consequences

One `fileReferences/list` call per settled path prefix, and none while no token
is live. The menu sits above the draft band and is suppressed while a `/` token
owns that band, so the two composer sources never stack. Paths render verbatim
and the client resolves nothing locally: a mention is ordinary prompt text, and
file contents stay behind the model's own read tool. The coverage block in
`docs/spec.md` §4.6 moves with this endpoint and with the account surface
landing in the same PR; the aggregate gate recomputes it.

## Testing

`packages/harness_adapter/test/harness_repository_integration_test.dart` pins
the request fields (`agentId`, `query`), the decode of both kinds, and three
fail-loud arms (missing `path`, unknown `kind`, non-array result).
`app/test/ui/chat/file_reference_picker_test.dart` covers the token grammar,
the mention and insertion rules, the debounce and sequence guard through the
real `ChatController`, and the composer menu through the real `ChatScreen`:
offered candidates, pick-to-insert, directory descent, and a draft with no
token.
