# Agent Note: Open the session workspace in the host desktop

Status: implemented

## Problem

dsh's Session controller can hand a workspace path to the serving desktop's
native opener: `session/canOpenWorkspacePath` reports whether the deployment has
one, `session/workspacePathApplications` lists the file associations registered
for one path, and `session/openWorkspacePath` runs the gesture
(`reference/deepseek-harness/packages/api/session-controller/src/index.ts:318-382`).
The web client drives them through
`packages/client/ui-open-in-app/src/client/open-path.ts` and renders the
per-target split button (`OpenTargetButton.tsx`).

The phone carried none of it: no endpoint constant, no decoder, no repository
verb, no seat. A reader could watch an agent write a report and could not open
its workspace on the machine that produced it.

## Decision

- **The three methods join the wire registry.** The two request-object methods
  (`openWorkspacePath`, `workspacePathApplications`) append to
  `_requestWrappedEndpoints`; the probe takes no argument. Decoders mirror the
  reference exactly: the probe's bare boolean and the association array are
  read from the envelope's `value` slot, an application row requires all four
  keys with `icon` required-but-nullable, and `opened` must be `true` — the
  Host states no failure inside a success envelope here.
- **The registered applications are domain data.**
  `domain/model/open_in_app.dart` models one row (`id`, `name`, `isDefault`,
  `icon`) so the adapter's wire vocabulary stops at the boundary; the icon data
  URL is carried verbatim but not drawn, because a data URL is not a source the
  Flutter image pipeline loads and the sheet lists names.
- **The chat header owns the verb.** `ChatUiState.canOpenWorkspace` carries the
  probe (one read for the controller's lifetime, false on a failed read — the
  reference reads an unreachable Host as "no desktop"), and the verb appears
  only when that bit and the selected session's `cwd` are both present, in the
  compact bar's session-verbs menu and the wide bar's icon seat.
- **The gesture follows the host's answer.** No registered application opens
  through the operating system default (the request omits `application`),
  exactly one opens through its id, and more than one lists them in the house
  menu sheet in the host's order.
- **A failed open is stated.** The gesture dispatches through the controller,
  so a Host refusal reaches the shared error strip with its stable code and
  message instead of leaving the tap looking like it did nothing.
- **A failed association query falls back to the default open.** The query is
  an optimization over the OS association; the open's own refusal is what the
  reader is told.
- **`reveal` stays unsent.** The request's optional `action` field is not
  exposed: the phone's one gesture targets the session workspace directory,
  which the default association already opens in the file manager.

## Alternatives considered

- **Porting the web's per-target split button** — rejected: it hangs off the
  presented-file and deliverable controls, and the phone has no presented-file
  route; the session header is the one place a workspace path is already named.
- **Putting the verb on the session row's long-press menu too** — rejected: that
  menu browses many sessions at once, and each row would need its own probe for
  a gesture acting on one workspace.
- **Rendering the host's application icons** — rejected: the wire carries PNG or
  SVG data URLs, which would need a decoder plus an SVG renderer for a 14px
  glyph; Material's `open_in_new` seat reads the same.
- **Hiding the verb when the association query fails** — rejected: the Host has
  already said it can open the path, and the default association is exactly the
  answer for a reader who never picked an application.
- **Caching applications per path** — rejected: the Host resolves associations
  from the desktop's live state, so a cached list could name a handler that is
  gone; the reference refreshes on every menu open.

## Consequences

Three constants move the wire-pin counts to declared 100, identical 98, missing
30 of 128 upstream, so `docs/spec.md`'s coverage block and the README's coverage
sentence change with this note. A deployment with no native opener hides the
verb entirely; a probe that fails reads the same way, and a Host that becomes
unreachable after the probe states its refusal in the error strip. The
applications list is read per gesture, so the sheet shows the desktop's current
handlers. The header keeps its existing seats; nothing else in the bar moves.

## Testing

`packages/domain/test/model/open_in_app_test.dart` covers the model.
`packages/harness_adapter/test/harness_repository_integration_test.dart` covers
the probe's boolean and its missing `value`, the association array's request
wrapping and every row field, a row missing `default`, the open's named and
omitted `application`, an `opened: false` reply, and a refused open.
`app/test/ui/chat/open_workspace_verb_test.dart` drives the real controller and
screen: the hidden verb under both a negative probe and a failed one, the sheet
with two applications, the direct open with one, the OS-default open with none,
the query-failure fallback, the stated refusal, and the wide bar's icon seat.
