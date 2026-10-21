# Agent Note: A session created in a cwd-grouped workspace names its path

Status: implemented

## Problem

When the Host's workspace registry is empty — or a reconnect has not re-delivered
its roster yet — the client still groups the session list, by inferring one
workspace per session `cwd` (`_inferWorkspacesFromSessions`,
`HarnessRepositoryImpl`). Each inferred row wears a client-minted
`ws-inferred-<hash>` id, and every "new session in this workspace" seat passed
that id through `createSession` into `session/create`.

The Host resolves a workspace id against its own registry
([commands.ts](../../../../reference/deepseek-harness/packages/api/session-controller/src/commands.ts):
`workspaceRegistry.get(workspaceId)`, missing → `workspace/not-found`), so the
create was refused with `workspace "ws-inferred-154379903" not found` — the
release ERROR captured against `ChatController`. Nothing was created, and the
sidebar offered no way to create a session in a project on those hosts.

The roster had a second gap on the same path: its membership was computed only
while the list was empty, so even a session created in one of those directories
would have trailed in the Ungrouped bucket instead of the group.

## Decision

The fabricated id never crosses the wire, and the group tracks the session
list.

- `HarnessRepositoryImpl` keeps the path behind each id it mints
  (`_inferredWorkspacePaths`), beside the roster rather than derived from it:
  the Host's own roster can replace the inferred rows between the reader's tap
  and the call, and a pressed id must still resolve.
- `createSession` names that path as `cwd` and drops the workspace id.
  `session.create` accepts a workspace id or a cwd, never both, and a cwd
  needs no registry entry. A Host workspace id still crosses as
  `workspaceId`, unchanged.
- `_inferWorkspacesFromSessions` re-folds the inferred rows on every session
  pull, so a session created in a group (or by another client) joins it on the
  next pull. A roster that holds any Host row is never replaced.

## Alternatives considered

**Translate in `ChatController`, where the seat is** — rejected: the
controller cannot tell a Host workspace from a grouped one without a fabricated
flag in `domain`, and the id is minted by the adapter, which is the only code
that should know it. **Send no workspace and no cwd** (the Host's default
cwd) — rejected: the session lands in a directory the reader did not choose,
silently. **Materialize a Host workspace on the first create**
(`workspace/create` + `session/create`) — rejected: a new session is not a
project-registry mutation, and the next `workspace/follow` baseline would then
publish a roster that disagrees with what the client just did. **Drop the
inference and show every such session as Ungrouped** — rejected: the grouping
is the only project structure those hosts have.

## Consequences

- New session in a cwd-grouped workspace creates the session in that
  directory; the next pull folds it into the group.
- Hosts that publish a workspace roster are unaffected: the id still crosses as
  `workspaceId`, and a pull does not replace the roster with cwd groups.
- The inferred group's `sessionIds` now follow the session list, so a session
  another client archives or removes leaves the group on the next pull.
- No wire vocabulary moves: no new RPC and no new event.
- Known boundary: the Workspaces management screen still offers rename, delete
  and reorder on a cwd-grouped row, and those verbs address a Host record the
  group does not have, so they still fail with `workspace/not-found`. Hiding
  them is a decision for that surface, not this fix.

Regression evidence:
[harness_repository_integration_test.dart](../../../../flutter/packages/harness_adapter/test/harness_repository_integration_test.dart)
pins the create payload (`cwd`, never the inferred id), the Host-workspace
pass-through, the roster that survives a pull, and the group taking a new
session on the next pull.
