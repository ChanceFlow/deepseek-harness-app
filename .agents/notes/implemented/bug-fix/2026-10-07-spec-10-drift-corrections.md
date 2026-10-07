# Agent Note: Correcting the drift §10 carried against the shipped client

Status: implemented

## Problem

Five claims in [docs/spec.md §10](../../../../docs/spec.md) describe a client
that no longer exists — three of them contradicted another bullet in the same
section:

- §10 said plugin management "is read-only over the wire", while
  `rpc_map.dart` declares `pluginManager/installBundle`, `waitForInstall`,
  `cancelInstall`, `setBundleEnabled`, `setPluginEnabled`, `removeBundle`,
  `listVersionExemptions` and `setVersionExemption`, `settings/plugin_manager`
  drives all of them, and §18 documents them.
- §10 said "compaction and session-end markers stay deferred", while the
  Compaction bullet eight lines above documents the marker and
  `chat_screen.dart` renders `CompactionRow` for `TimelineCompaction`. Only the
  session-end marker is absent.
- §10 said question cards do not support "plan-review intents", while
  `_planReviewOf` parses the intent and `_PlanReviewCard` renders the decision
  card, as the plan-review bullet eight lines below states.
- §10 said `settings.mutate` had "no dedicated UI", while
  `llm_providers.dart` calls `mutateSetting` with `SettingPathOp` on three
  paths: a pasted key's env ref, adding or configuring a profile, and removing
  one.
- §10 named `host.listDirectory` / `host.createDirectory` / `host.pickDirectory`
  as the directory-browsing routes; the client declares `directoryPicker/list`,
  `directoryPicker/createDirectory`, and knows the desktop verb as
  `directoryPicker/pick`. No `host.*` endpoint exists in the registry.

A stale test-technology claim sat in the same section: the turn-grouping bullet
called `groupTimelineByTurn`/`promptPreview` "JVM-tested" a Flutter rewrite
after the Kotlin stack was deleted.

## Decision

Rewrite each claim to the shipped behavior, verified against the code rather
than against the older prose:

- Split the plugin bullet: `pluginInventory/list` stays the read-only
  inventory; plugin lifecycle is the `pluginManager/*` verbs §18 owns. What
  genuinely stays host-side is named explicitly — preset authoring, plugin
  configuration slots, granting (not revoking) a version exemption, and skill
  authoring.
- Name only the session-end marker as deferred, and say where a compaction
  marker renders.
- Keep the plan-review intent as supported, with any other presentation intent
  falling back to the generic editor.
- Name `settings.mutate`'s three real call sites as its dedicated UI.
- Replace the `host.*` names with the `directoryPicker/*` routes.
- Point the grouping tests at `app/test/ui/chat/timeline_grouping_test.dart`.

## Alternatives considered

Leave the claims and fix them when a reader trips: rejected — §10 is where a
new contributor learns what the phone does, and three of the five contradicted
the same section, so the section cannot arbitrate itself. Delete the corrected
bullets instead of rewriting them: rejected — each carries a real deferred
limitation (session-end marker, plugin configuration slots, secret-slot writes),
and deleting them would hide the limit rather than the mistake. Restate the
plugin surface by pointing at §18 alone: rejected — §10's job is the client's
own limit, and the limit is narrower than "read-only".

## Consequences

§10 now agrees with §18 and with the code, and no claim in it names a route or
a test technology the repository does not have. The corrections move no
behavior: every claim was checked against a call site or an endpoint constant
before it was rewritten, and no client code changed.
