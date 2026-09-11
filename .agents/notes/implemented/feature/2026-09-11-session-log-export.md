# Agent Note: Session-log export

Status: implemented

## Problem

The pinned 0.1.5 host exposes `GET|HEAD /api/session.export?sessionId=…&includeDescendants=true`,
which streams a ZIP of the session tree (`session.jsonl`, `subagents/<id>/…`,
`media/<attachmentId>.<ext>`) with `content-disposition: attachment`.
`command_roster.dart` documented `/export` as web-only because the host's
handler hands the transfer to the browser, and `grep` found no `session.export`
anywhere under `flutter/`. The artifact an agent produced could be read in the
transcript but never taken off the phone.

## Decision

**Transport.** A dedicated binary GET client in `packages/network`
(`dsh_download_client.dart`): `DshDownloadClient.download(pathAndQuery, {timeout})`
returns the buffered body plus `content-type`/`content-disposition`. It is
protocol-agnostic — it never composes a path, a query, or a filename, and it
learns no dsh vocabulary. It resolves the caller's path against
`baseUrl.origin`, which is what `HttpDshRpcClient` already does implicitly by
resolving `api/<endpoint>` against the base (a base path segment is dropped
either way), so both legs address one host. The body is read as a stream and
buffered, so a response that ends before its declared `content-length` throws
`DshTransportException` rather than settling as a short archive; non-2xx throws
with the status and a clipped reason. The caller's `headers` map is copied
through untouched, mirroring the RPC client's auth/header seam (today empty).

**Wire path.** `DshHttpRoutes.sessionLogExport = '/api/session.export'` in
`rpc_map.dart`, deliberately outside `DshRpcEndpoints` — the route is not a
Typert Remote method, and `verify_wire_pin.py` compares that class's members
against the pinned Remote surface. `session_log_export.dart` owns the query
(`sessionId`, `includeDescendants=true` only; absent is the host's `false`) and
the filename (`dsh-session-<id>.zip`, the id collapsed to `[A-Za-z0-9_-]`,
mirroring the host's `sessionLogZipFilename`).

**Deadline.** A third case beside the adapter's short unary deadline and its
explicitly unbounded agent calls: `kSessionLogExportTimeout = 5 minutes`. A
session tree's archive is orders of magnitude larger than any unary RPC, so
30 s would kill legitimate exports; unbounded would leave a wedged host
spinning forever.

**Repository surface.** `SessionLogExportRepository` in `domain`, returning
`SessionLogExport {filename, bytes}`. It is a second seam rather than a member
of `ChatRepository` because `HarnessRepositoryImpl` declares `implements
ChatRepository`: in Dart every interface member must be implemented by that
class, so widening `ChatRepository` would have forced an edit to a file this
change must not touch, and the route is not an RPC — it needs none of the
repository's connection state. `DshSessionLogExportRepository` is a small
standalone implementation over the download client.

**Saving on Android.** A `dsh/session_log_export` method channel
(`MainActivity.kt`, worked off the platform thread) inserts the archive into
`MediaStore.Downloads` on API 29+ — no storage permission exists for that path
— and falls back to the app-specific `getExternalFilesDir(DIRECTORY_DOWNLOADS)`
on API 24-28, where the public collection would need
`WRITE_EXTERNAL_STORAGE`; the app requests no storage permission and the
manifest is untouched. It returns the location for the success notice.

**UI.** A new `session_log_export_action.dart` header seat: compact
`IconButton`, spinner while streaming, snack bar on settle (localized failure;
the cause goes to the error log). A bare `/export` now dispatches to the same
controller flow instead of riding `commands/execute`, which would only answer
`Session log download requested.`; `/export` joins the roster (`export`, no
hint) so it is discoverable in the composer and image-carrying submissions are
refused.

## Alternatives considered

- **Squeeze the GET into `DshRpcClient.call`.** The RPC seam wraps payloads in
  `client-request` envelopes and decodes `server-response` JSON; a ZIP body has
  neither, so every layer would need a special case for a call that is not RPC.
- **Add `exportSessionLog` to `ChatRepository`.** Blocked by `implements
  ChatRepository` + the no-touch boundary on `harness_repository_impl.dart`;
  the separate domain seam keeps the contract in `domain` types anyway.
- **Share sheet (`share_plus`) or documents-directory plus a save intent.**
  Adds a dependency, and either leaves the file in app-private storage or hands
  placement to another app; the success notice could not honestly name a
  location.
- **HEAD then hand the URL to the platform download manager**, as the web
  client does. Android has no such call for an arbitrary authenticated URL
  without a DownloadManager request and its own notification/visibility rules;
  the GET is simpler and gives the client the bytes it must verify anyway.
- **Stream straight to a file sink.** Buffering is what makes truncation a
  failure; a streaming sink would leave a partial ZIP on disk that looks valid.

## Consequences

- An exported archive lands in Downloads (`Download/dsh-session-<id>.zip`),
  reachable from any file manager, with no new permission on either API band.
- `/export` and the header seat are the same flow; the roster's stale
  "web-only" justification is gone.
- The adapter exposes one non-RPC route; `docs/spec.md` §4.7 records it, §16
  records the client-local command, and README's feature surface gains the
  capability in both languages.
