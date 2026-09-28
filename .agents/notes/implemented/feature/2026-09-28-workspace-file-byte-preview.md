# Agent Note: Workspace file previews read bytes, not only text

Status: implemented

## Problem

A delivered or changed file could be tapped in the transcript but many could
never be shown. The preview sheet read the file through `workspaceFiles/read`,
which decodes UTF-8 text, so the host refused everything else: `read()` throws
`workspace-file/not-text` for a page containing NUL bytes, and `cutPage()`
refuses a page over `maxBytes` (2 MiB) with `workspace-file/too-large`
(`packages/api/workspace-files/src/index.ts`). Every such failure collapsed
into one state — "load failed" with a Retry that could never succeed — because
the sheet caught the error and discarded it, and a failed unary call reported
no diagnostic. A rendered PNG, a PDF, a ZIP or an oversized text file was
therefore permanently unopenable, with nothing in the error log to say why.

The reference client never forces a text read on a binary: its document
preview reads bytes and dispatches by type
(`packages/client/ui-sidebar-documentpreview/`), and its delivered-file card
asks the host to open the path (`packages/client/ui-deliverables/src/present-open.ts`).

## Decision

- The wire layer carries binary results. A 0.1.7 Remote result holding a byte
  field is answered as `multipart/form-data`: the bytes ride `bytes-<i>` Blob
  parts and a `metadata` JSON part carries the envelope with that field
  replaced by `null` (`packages/typert/protocol/src/types.ts` result codec,
  `packages/typert/generator/src/emitter.ts`, `packages/api/gateway/src/index.ts`,
  `packages/client/connection/src/rpc-host.ts`). `rpc_binary_envelope.dart`
  parses that response, walks each attachment's `path` from `{value: …}`,
  requires the leaf to be exactly `null`, and fails loudly on a missing or
  duplicated `metadata` part, an unclaimed form field or a truncated body — the
  same contract the reference carrier implements
  (`packages/client/connection/src/client/rpc.ts`). Matching the reply's `rpcId`
  to the request belongs to the carrier, not the decoder
  (`http_dsh_rpc_client.dart`).
- `workspaceFiles/readBytes` is declared and read. `read` pages decoded text;
  `readBytes` returns native bytes — the whole file when `options.range` is
  absent, one window otherwise — and both resolve the file through the
  `workspaceFileScope` lookup, whose wire field is `workspaceFileScopeId`.
- The preview dispatches on the path: text-like files keep the paged text
  read, an image renders from those bytes, and a type the app cannot render
  states that it cannot be previewed and offers the path — no Retry that
  cannot succeed. A text read the host refuses as `not-text` falls back to the
  bytes and their image signature, so a suffix-less or mis-named image still
  renders; the fallback is gated on that refusal alone, which is the one a
  binary's first page produces.
- A failed read is reported with its host error code and path through the
  existing diagnostic seam, so the next report names its cause.

## Alternatives considered

`GET|HEAD /api/file?path=<absolute>` — the pin's plain-HTTP whole-file route on
the same cookie-authenticated `/api` fence
(`packages/api/session-controller/src/media-references.ts`) — was rejected: it
ignores `Range`, caps at the attachment image limit (20 MiB) rather than the
Remote read's own caps, returns neither `version` nor `eof`, needs an already
absolute path so a Session-relative declaration cannot be resolved, and the
download client resolves it against the origin only, so a host mounted under a
prefix would 404. Reading text only and reporting the refusal honestly was
rejected because the refusal is permanent for a binary — the file exists and
the reader asked to see it. Base64 in JSON is not available; the codec is
multipart.

## Consequences

Non-text deliverables and oversized pages open, or say why they cannot, instead
of failing behind a Retry. The byte path is one extra call per open and holds
one window in memory. The engine's whole-file cap (32 MiB) and page cap (2 MiB)
apply unchanged; the preview never requests a range, so it reads the whole file
up to that cap. The reference's other renderers (PDF, office, HTML) are not
ported: those types report that the app cannot preview them, and a suffix list
taken from the reference's own decides which read to make — an image suffix
reads bytes, an unrenderable suffix spends no call, and everything else
including `.svg`, `.html` and `.csv` stays on the text path. A suffix that
promises an image but whose bytes carry no image signature lands in the
unrenderable state rather than in the decoder.

A refusal the app can explain loses its Retry; only a failure with no host code,
or one this build does not know, stays retryable. Every failure is reported with
its code and path.

One limitation is deliberate and has a named follow-up: the sheet reads the host
code out of `DshBusinessException`'s `toString()` because `app` outside
`lib/di/` may not import `package:network/`, and reaching the DI assembly from a
leaf widget is worse. The durable fix is a neutral code-carrying failure type in
`domain` that the adapter maps at the repository boundary; until then, a wrapped
or reworded failure falls to the generic state rather than to a wrong one.
