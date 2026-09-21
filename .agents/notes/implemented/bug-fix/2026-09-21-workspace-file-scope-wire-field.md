# Agent Note: Workspace file previews sent the wrong scope argument

Status: implemented

## Problem

Every file preview failed. `workspaceFiles/read`, `stat`, and `list` scope a
file to a Session through a Typert **lookup** parameter — the service declares
`read(workspaceFileScope: WorkspaceFileScope, path, range, signal)` and
registers the lookup as `{parameter: 'workspaceFileScope', wire:
'workspaceFileScopeId'}` (`reference/deepseek-harness/packages/api/
workspace-files/src/index.ts`). The generator composes a lookup's wire field
name from its key, `<key>Id`
(`packages/typert/generator/src/analyzer.ts:1122-1130`), so the argument the
host accepts is `workspaceFileScopeId`.

The adapter sent `sessionId`. The gateway validates argument field names
exactly and refuses the whole call:

```text
gateway/arguments-invalid: typert gateway: workspaceFiles/stat: args fields do
not match the descriptor: missing "workspaceFileScopeId"; unexpected "sessionId"
```

The preview sheet, the produced-file chips, and any
`listWorkspaceDirectory` caller therefore all failed on a real host. The
unit suite missed it in the way the wire-pin gate's docstring already
describes: `workspace_files_wire_test.dart` asserted the wrong name into its
own expectation, so the fake host agreed with the client about a contract
neither shared with the pin, and the opt-in real-host e2e asserted nothing
about the workspace-file surface.

## Decision

`DshRemoteInvoker._prepareArgs` maps the adapter's local `sessionId` payload
key onto the wire field `workspaceFileScopeId` for `workspaceFiles/read`,
`readBytes`, `readAll`, `stat`, and `list`. The local key stays `sessionId`
because that is what the repository method receives; the translation lives in
the one place that owns wire field names. The unit test now asserts the
emitted field and the absence of `sessionId` for read, stat, and list.

The opt-in real-host e2e (`local_dsh_e2e_test.dart`) covers the wire surface a
preview rides: a workspace listing of the root (`.` — the host refuses an
empty path), a `stat` of a listed regular file, and a paged `read` of it that
must agree with the stat's `absolutePath`. Two supporting facts came out of
making it run:

- A 0.1.5 `/api` answers only a caller holding the authority-bound browser
  cookie minted from the URL token `dsh web` prints, so the test takes that
  cookie from `DSH_E2E_COOKIE`. Without it the run died at the WebSocket
  handshake and reached no assertion at all.
- The e2e now selects a **root** session (`!blank && origin != 'subagent'`).
  `session/list` carries subagent children, and `openSession` refuses one by
  design — the subagent catalog is its route — so the previous
  `!blank` filter could pick a child and fail on an empty window.

## Alternatives considered

- **Send both `workspaceFileScopeId` and `sessionId`.** Rejected: the
  descriptor check fails on an unexpected field exactly as it fails on a
  missing one, so the pair is no more robust than the single wrong name.
- **Retry with `sessionId` when the host answers `gateway/arguments-invalid`.**
  Rejected: no pinned dsh release names this scope anything but the lookup key
  — `Agent`/`agentId` before the 0.1.5 scope introduction, then
  `workspaceFileScope`/`workspaceFileScopeId`. A retry would only hide the
  next rename behind a second round trip.
- **Extend `verify_wire_pin.py` to compare argument field names, not just
  endpoint names.** Deferred, not rejected: the gate derives endpoints from
  `@Remote` declarations, and deriving each descriptor's argument set (lookups
  included) against the adapter's emitted payload is the follow-up that would
  have failed this bug statically. The live-host e2e is the guard until then.

## Consequences

- A 0.1.5 host serves the preview sheet and produced-file chips again; the
  failure was entirely client-side, so nothing changes on the host.
- `README.md` and `README.zh.md` document `DSH_E2E_COOKIE` in the opt-in e2e
  section.
- `ChatRepository.listWorkspaceDirectory` states that `path` is a workspace
  path and that `'.'` names its root.
- The reference's own `交付文件` row (explicitly *presented* files, `row.title`
  in `ui-deliverables/src/client/locales.ts`) stays unimplemented; this
  client's produced-files row is the reference's `produced.label`
  (`本轮文件改动` / "Files changed"), which is what the model's mutation calls
  changed in the turn.
