# Agent Note: Office documents convert to PDF over the wire

Status: implemented

## Problem

The preview registry states that `doc`, `docx`, `xls`, `xlsx`, `ppt` and
`pptx` cannot be previewed and spends no read on them
([renderer coverage](2026-10-12-file-preview-renderer-coverage.md)). The
reference client shows them, and not by rendering the Office layout in the
browser: it asks the host to convert the document and draws the returned PDF
(`reference/deepseek-harness/packages/client/ui-sidebar-documentpreview/src/client/office/index.ts`
calls `officeToPdf.render`). That route was entirely unwired here — no
endpoint constant, no invoker arm, no result decoder, no repository seam — so
a phone surface could not reach it even though the host registers it.

## Decision

- The endpoint is declared as `officeToPdfRender` in
  [rpc_map.dart](../../../../flutter/packages/harness_adapter/lib/src/rpc_map.dart).
  `render` takes the shared `workspaceFileScope` lookup as its first argument
  (`packages/document/office-to-pdf/src/index.ts:159-162`;
  `packages/api/workspace-files/src/index.ts:203-207` registers the lookup),
  so the invoker rewrites the caller's `sessionId` to the
  `workspaceFileScopeId` wire field exactly as the `workspaceFiles` arms do,
  and forwards `path` and the required `priority`.
- The reply is `RenderedDocumentBytes`, a `WorkspaceFileBytes` with a
  `Uint8Array` field (`.../office-to-pdf/src/types.ts:48-51`), so it rides the
  existing multipart attachment carrier rather than a new envelope: the
  transport splices the binary part over the codec's `null` placeholder
  before the adapter sees it
  ([byte preview](2026-09-28-workspace-file-byte-preview.md)).
  `OfficePdfDocumentWire` decodes `absolutePath`, `version`, the optional
  `bytes`, `offset`, `data`, `eof` and the required `missingFonts` with the
  same fail-loud semantics as its `WorkspaceFileBytesWire` neighbour.
- [OfficePdfDocument](../../../../flutter/packages/domain/lib/model/office_pdf.dart)
  is the neutral model the repository returns; it carries the whole PDF and
  the missing font families. The decoded source-identity fields are not
  surfaced: on the reference they exist for its browser-side cache.
- The repository method is `renderOfficeToPdf(sessionId, path)`, always
  `priority: 'foreground'` — an open preview is work the reader asked for,
  and the host's `background` lane is speculative with its own budget. Its
  deadline is two minutes: the host converts under its own `timeoutMs`
  (60 s default, `.../office-to-pdf/src/index.ts` `Config`) that excludes the
  queue wait behind another conversion, so the short unary deadline is wrong
  and an unbounded call would be too.
- A refusal is not swallowed. The host answers `document-render/failed` with a
  `details.reason` of `input-too-large`, `output-too-large`,
  `invalid-document`, `unsupported-format`, `invalid-output`, `timeout`,
  `unavailable`, `failed`, `busy` or `source-changed` (`types.ts:43-57`), and
  `gateway/invocation-unavailable` / `gateway/service-unavailable` mean the
  host mounts no office service. The existing business-exception path carries
  code, message and details intact, so the surface can branch on the reason
  instead of showing one generic failure.
- No PDF cache, and therefore no `officeToPdf/generation`. The reference reads
  `generation` only to invalidate its cached conversions
  (`.../src/client/office/index.ts`), keyed by source `version`; a phone path
  that converts on open and holds nothing has no entry to invalidate, and
  declaring a method nothing calls would only widen the registry.

## Alternatives considered

Declaring `officeToPdf/generation` for symmetry with `render`, or to leave the
door open for a cache: rejected — the wire-pin allowlist exists for names the
pin withdrew, not for speculative coverage, and a declared-but-unread endpoint
buys nothing. Adding a phone-side PDF cache matching the reference's
source-version plus generation key: rejected as this change's scope, and a
portrait phone holds no comparable byte budget. Surfacing `absolutePath`,
`version`, `offset` and `eof` on `OfficePdfDocument`: rejected — the method
renders complete documents and nothing consumes the identity without a cache.
Mapping the refusal to a generic `RepositoryFailure`: rejected, because that
type carries code and message only and would drop the `reason` the surface
branches on. Asking for base64 JSON: not available, the codec is multipart.
Issuing speculative `background` conversions to warm a cache this client does
not keep: rejected.

## Consequences

Coverage moves from 100 of 128 to 101 of 128 Remote methods, and the unwired
remainder from 28 to 27, with `officeToPdf/generation` now the only office
method left ([spec §4.6](../../../../docs/spec.md#46-wire-coverage)). A phone
surface can convert a document whenever the host mounts the office service.
The call is seconds to about a minute and the whole PDF — up to the host's
`maxOutputBytes` — is held in memory, so the surface shows progress and never
assumes a fast read. Re-opening the same document converts it again; that cost
is the deliberate price of holding no cache.
