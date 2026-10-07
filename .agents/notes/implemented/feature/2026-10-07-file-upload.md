# Agent Note: composer file upload through `fileUploads/upload`

Status: implemented

## Problem

The composer could attach images only. The host already stores arbitrary
files: `packages/client/file-upload/src/index.ts` registers the `fileUploads`
Remote namespace with `@Remote('upload')` over `EncodedFileUploadRequest`
(`{data: canonical base64, name?}`) and answers `FileUploadValue` — a staged
`receiptId` plus a durable `FileAttachmentRef` (`{attachmentId, name, bytes}`,
`packages/attachment/attachment/src/types.ts`). A prompt then cites the
receipt as a `{type: 'file', receiptId}` content part, which the host resolves
inside the receiving Agent's scope; the same receipt rides
`commands/execute`'s `submittedAttachments`. None of that existed on the
phone, so a reader who wanted the model to read a PDF had no way to hand it
one.

## Decision

- **Unary base64 `fileUploads/upload`.** The wire shape is
  `{'agentId': sessionId, 'request': {'data': <base64>, 'name': ?}}` — the
  same `(agentId, request)` form `goals/create` and `terminal/create` use. The
  reference client takes this branch for a byte array and reserves the
  raw-byte route (`/api/session/uploadFileBinary`) for blobs and streams; the
  phone already holds one picked document's bytes.
- **`FileUploadLimits.maxFileBytes` (8 MiB) is the phone's own bound.** The
  host stores verbatim files without an admission limit
  (`attachment/src/index.ts` `saveFile`), so this cap is ours: the base64
  body, its decoded copy, and the JSON envelope are resident together. The
  adapter enforces it before the call and answers a `RepositoryFailure` with
  the host's own `session/attachment-invalid` code; the picker passes the same
  cap down so an oversized document fails before its bytes are read.
- **Domain vocabulary.** `UploadedFile` is the staged receipt plus the durable
  reference; `PendingFile` is the composer row with
  `PendingFileStatus.{uploading, ready, failed}` and the failure reason.
  `SendMessageRequest.files` carries only ready uploads; the adapter emits
  `{type: 'file', receiptId}` parts after the image parts, and
  `executeCommand` appends the same entries to `submittedAttachments`.
- **A failed upload keeps its row and its reason.** The controller mints the
  row before the call and replaces it in place; a failure publishes the host's
  `code: message` on the attachment chip instead of removing it, because a
  vanished attachment hides the only fact the reader can act on.
- **Send refuses an unsettled file.** Web `conversation.sendSession` throws
  when a file has not finished uploading; the phone refuses the submission and
  says which file, keeping the draft. A ready file leaves the strip only when
  the host accepted the prompt.
- **Staged receipts are session-scoped.** A session switch clears the
  attachment rows: a receipt minted for the leaving session is refused by the
  arriving one (`FILE_NOT_STAGED`). Inline images stay, because they carry
  their own bytes.
- **The picker is a platform bridge.** Android has no browse-and-return path
  in plain Dart, so `app/lib/platform/document_picker.dart` opens
  `ACTION_OPEN_DOCUMENT` through a `dsh/document_picker` channel
  (`MainActivity.kt`), reads the chosen `content://` document off the platform
  thread, and applies the byte cap before reading. `ComposerBar.onPickFile`
  injects the pick, so widget tests drive the attach and failure paths without
  a channel. No new pub dependency.
- **The edit sits in the composer's existing shape.** The plus sheet gains an
  `Attach a file` row beside `Attach images`; the strip gains a chip (Material
  3 `errorContainer` on failure, an indeterminate bar in flight, name and size
  in every state) with an always-present remove seat. Strings are ARB keys in
  both locales.

## Alternatives considered

- **The raw-byte route.** Deferred: it exists for bodies the client cannot
  assemble in memory, and the phone's cap keeps the base64 path inside that
  budget. Wiring it would add a second transport seam and a second failure
  shape.
- **A file-picker pub package.** Rejected: a dependency and pubspec churn for
  one system intent the platform bridge already expresses.
- **Sending file bytes inline in the prompt.** Rejected: the host's prompt
  contract accepts only staged receipts; an inline file part is not a variant
  the host reads.
- **Uploading on send.** Rejected: the web client uploads as the reader
  attaches, which makes the failure visible before the draft is spent;
  uploading at send turns a failed transfer into a failed prompt.
- **Dropping failed rows automatically.** Rejected: it removes the reason the
  reader needs and silently changes the submission.
- **Command-file support as a follow-on.** Not deferred: the same acceptance
  flag governs images and receipts, so `executeCommand` carries both from the
  start.

## Consequences

One `fileUploads/upload` call per attached document and none for a cancelled
pick. The strip reports state, not byte progress — the unary call offers none
— so the in-flight bar is indeterminate. A failure is cleared by removing the
row and picking again; the bytes are not retained for a retry. The bridge is
Android-only: a host without the channel surfaces a pick error, and every
widget test injects its own picker. The phone cap is a client policy, not a
host fact, and belongs with the upload call that enforces it.
