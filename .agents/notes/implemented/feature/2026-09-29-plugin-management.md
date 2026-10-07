# Agent Note: Plugin management

Status: implemented

## Problem

The phone could read what the host had loaded (`pluginInventory/list`) and
nothing else. The pinned host serves a full manager — install a bundle, switch
a bundle or one of its plugin entries, remove it, list and change version
exemptions — and every one of those thirteen methods was unwired. A user who
needed a plugin had to reach a desktop or the CLI.

Two facts shaped the work. The installation lifecycle is not one call: the host
runs `pnpm` for minutes, and its own reference page drives it through inspect →
install (with `enabled: false`) → enable, reading progress from *pushed* events
rather than polling. And `managementAvailable` is a real gate — a deployment
that composes no manager answers `gateway/invocation-unavailable` for every one
of those methods, so a surface that offers them unconditionally offers broken
controls.

## Decision

Wire all thirteen methods and mirror the reference page's lifecycle, with two
deliberate divergences.

- `pluginManager/*` and `pluginRegistryProbe/fastest` join `DshRpcEndpoints`;
  the invoker passes each method's flat source parameters (`{spec, options}`,
  `{name, enabled}`, `{id, enabled}`, `{requestId}`, `{packageVersion,
  runtimeVersion, enabled, acceptRisk}`) with no request wrapping.
- Installation is unbounded on the client (`_noCallDeadline`) because a pnpm
  install is minutes; `inspect` gets two minutes (it probes registries and
  GitHub); a removal shares the install policy.
- Progress is event-driven: the three forwarded names
  (`plugin-manager/install-state`, `install-log`, `changed`) were falling into
  the unrecognised-event diagnostic. They now fold into an install-progress
  state stream, a log-chunk stream, and a change epoch that re-reads the roster.
- A client-minted `requestId` is what makes the host emit those events for this
  attempt, and a *lost unary reply* — not a failed install — reconciles through
  `waitForInstall`. Null there means the host has no record, which the surface
  reports as unconfirmed instead of guessing.
- A dropped error is impossible by construction: expected refusals arrive as
  values inside `ChangeResult.error` / `PluginSpecRefused`, and the decoder
  keeps that branch distinct from transport failure.
- **Divergence 1**: the version-exemption ledger gets its own page (list and
  revoke). The reference Web page has no exemption UI at all — the capability
  is reachable only from the agent tool and the CLI — so this surface is
  designed from the wire types. Granting needs the exact current runtime
  version plus `acceptRisk: true`, which is exactly what a version refusal
  carries; a list-and-revoke surface is what a phone can do without inventing
  that context.
- **Divergence 2**: the page is one screen — bundle cards with a row
  disclosure — rather than the reference's list/detail/row drill-down. A phone
  column cannot hold three levels and a switch; the information and the
  mutation set are the same.
- Not mirrored, because the wire does not describe them: the `plugins.*` slot
  system (React components other client plugins contribute), `configForms`,
  and `ctx.pluginNavigation`.

## Alternatives considered

Poll `listBundles` while an install runs: rejected — the host already pushes
phase and log events, and polling would either miss the log or waste the radio.
Treat an install as `enabled: true` in one call: rejected; the host's own page
defers activation so a broken plugin can be installed without being loaded, and
`restart-required` needs the human to decide when.
Enable the page from `listBundles` succeeding rather than
`managementAvailable`: rejected — the failing call is the thing being avoided,
and the inventory already answers the question.
Show the exemption page as a grant form: rejected as dishonest about its
requirements; a grant without the observed mismatch and its risk acceptance
would fail host-side, and the `acceptRisk` flag is a real acknowledgement, not
a formality.
Fold a malformed install-progress event into a failed install: rejected —
progress is advisory, and the unary result is the authority; a bad chunk is
reported and dropped.

## Consequences

`declared 67 / upstream 125 / identical 65 / missing 60`. The unrecognised
forwarded-event diagnostic lost three names because they now fold. A phone can
install, switch, remove, and reconcile plugins, and the surface hides itself on
a host that composes no manager. `PluginInventorySnapshot` gained
`managementAvailable`, which the inventory decoder previously dropped — that
field is the gate for this whole surface. The exemption grant flow stays
unbuilt and is recorded in docs/spec.md §10.
