# Agent Note: First-run default verbs and the `@` session family

Status: implemented

## Problem

Four pinned Host verbs were unwired on the phone: two first-run defaults
(`workspace/initializeDefault`, `session/initializeDefaultModel`), the
cross-session half of the `@` reference source
(`sessionReferenceResolver/candidates`), and a live goal read (`goals/get`).
The phone already landed `fileReferences/list` for `@` and folds the `goal`
session projection, so each verb needs a placement decision rather than
blanket coverage.

## Decision

**`workspace/initializeDefault` is wired end to end.**
`reference/deepseek-harness/packages/api/workspace-controller/src/index.ts:98-107`
registers `@Remote('initializeDefault')`: it takes only the transport's
injected `signal` and answers `WorkspaceValue | undefined`, where `undefined`
means first-use initialization is ineligible. The web client calls it exactly
when the installation is empty
(`packages/client/ui-workspace/src/client/navigation.ts:338-343`). The phone's
create flow does not get a default implicitly — `workspace/create` requires a
directory path — so a fresh install could only get a workspace by making the
reader find a folder. The empty workspace tree now offers the deployment's own
default (`flutter/app/lib/ui/workspace/workspace_screen.dart:992-993`) through
`InitializeDefaultWorkspaceAction` (`workspace_ui_state.dart:246`) and
`WorkspaceController._initializeDefault` (`workspace_controller.dart:311-325`).
An ineligible answer is null, not an error: the empty tree and the folder
browser stay.

**`sessionReferenceResolver/candidates` is wired as the second family of the
same `@` menu, not as a fallback.** It is a distinct provider, not the path
lookup through another resolver: it is `ctx.sessionReferenceResolver`
(`packages/context/session-reference/src/index.ts:98`), `@Remote('candidates')`
at :271-283, answering `SessionReferenceMentionCandidate[]`
(`packages/context/session-reference/src/types.ts:69-73`) — the discovery
record plus the canonical mention. `fileReferences/list` answers path/kind
candidates (`packages/api/session-controller/src/file-references.ts:22-39`).
The web client runs both in one `@` source and renders one menu
(`packages/client/ui-reference/src/client/index.ts:71-75`), so
`FileReferencePickerState` carries both families and the composer inserts the
host's canonical session mention verbatim — the `dsh-session:` markdown form
`formatSessionReferenceMention` renders
(`flutter/app/lib/ui/chat/file_reference_picker.dart:134-167`), the text the
host parses back out of the prompt
(`packages/context/session-reference/src/uri.ts:48-51`, :69). The reference
asks for sessions only while the path is unquoted, so an open quote keeps the
menu file-only (`file_reference_picker.dart:206-213`).

**`session/initializeDefaultModel` stays unwired.** Its handler is
`packages/api/session-controller/src/index.ts:291-303`: a bare `@Remote`, no
arguments, a no-op when any provider API key exists, otherwise it saves the
first `deepseek-account` model as the deployment default. Its only caller is
the account sign-in edge
(`packages/client/ui-settings-account/src/client/index.ts:125-133`), and the
phone cannot produce that edge: `startSignIn`/`cancelSignIn`/`signOut` are
deliberately unwired
(`flutter/packages/harness_adapter/lib/src/rpc_map.dart:179-183`). The phone's
create flow already inherits the host default: `SessionCreateRequest` carries
no model field (`packages/api/session-controller/src/types.ts:285-290`), so
`session/create` fills `agentOptions()` from
`agentDefaultModel.currentSelection()`
(`packages/api/session-controller/src/agent.ts:497-500`). Calling the verb
from the phone would rewrite the host's configured default with no user action.

**`goals/get` stays unwired.** `@Remote('get')` answers a `GoalView |
undefined` for one *live* agent and refuses a session the host does not hold as
its live instance (`packages/goal/goal/src/index.ts:276-280`). The only field
it carries beyond the `goal` projection is `activation`, process-local and
never persisted (`GoalView` at `packages/goal/goal/src/types.ts:90-98`;
`GoalProjection` at :107-118, whose doc says activation is deliberately
absent). The phone already reads that projection on session open
(`flutter/packages/harness_adapter/lib/src/harness_repository_impl.dart:4058-4061`,
:4880-4882) and drops `goal/activation-changed` (:5465) as unrendered, so a
`goals/get` read would deliver a field no phone surface shows; the read and
the projection overlap exactly for every durable goal fact, including one
created before this client connected.

## Alternatives considered

- **Call `session/initializeDefaultModel` on connect.** Rejected: it would
  overwrite the host's configured default model on every phone connect with no
  user action, and its only correct trigger is a sign-in completion edge this
  client cannot produce.
- **Auto-bootstrap the default workspace at startup, as the web does.**
  Rejected: the phone has no startup selection-restore step to hang it on, and
  registering a host directory from a network side effect the reader never
  asked for is worse than a labelled button in the empty state.
- **Treat session candidates as a fallback when the path lookup is empty.**
  Rejected: the two families answer different kinds of result and the web asks
  for both in parallel; a fallback would hide sessions whenever any path
  matched.
- **Read `activation` through `goals/get` and render it.** Rejected: no phone
  surface shows continuation eligibility, and the projection already answers
  the durable goal state.
- **A second picker holder per `@` family.** Rejected: the web merges them
  into one list, and two holders would let one family's answer stand under the
  other's query.

## Consequences

One `workspace/initializeDefault` call per empty-state tap; it creates no
session and no message, so a reader who only looked around keeps an empty tree.
The `@` menu issues two lookups per settled prefix where it issued one, each
family failing independently — a refused family answers empty rows instead of
failing the query, and an open quote suppresses the sessions rows. The
composer half is wired on the client only: the mention text is ordinary prompt
text and the host owns its meaning. `session/initializeDefaultModel` and
`goals/get` stay in the wire-pin gate's missing count; the `docs/spec.md`
coverage block moves with the two endpoints this change adds.
