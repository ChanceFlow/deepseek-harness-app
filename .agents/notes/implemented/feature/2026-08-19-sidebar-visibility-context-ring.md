# Agent Note: Sidebar session visibility and context-ring occupancy

Status: implemented

## Problem

Two mobile surfaces diverged from the web. The sidebar listed subagent
child sessions as independent top-level sessions (they belong to their
parent's subagent catalog, never the session tree) and showed every blank
provisional session. The composer's context ring never rendered: the
`ComposerBar` fields existed since the B11 composer port but no call site
passed `contextPressure`/`contextBreakdown`, and the occupancy read lacked
the projection's `projectedTokens` — the value that answers for the next
request rather than the last one.

## Decision

Session visibility ports `sessionVisible` from
`reference/deepseek-harness/packages/client/ui-workspace/src/client/tree.ts`
as a `_sessionVisible` predicate in `session_panel.dart`, applied wherever
sessions enter the panel (grouped tree with counts, rail avatars, search
results): `origin != 'subagent' && (!blank || id == selected)`. The wire's
optional `SessionSummary.origin` (`'subagent'` marks a child) is decoded in
the adapter and carried on the domain summary; archived filtering stays
upstream in the adapter's `observeSessions` combination. Search additionally
never shows blank sessions, matching `deriveSearchResults`.

The ring's occupancy ports `contextOccupancy` from
`.../ui-conversation/src/client/chat/StatsLine.tsx`:
`usedTokens = projectedTokens ?? pressureTokens`, requiring `contextWindow`.
The fold (`context_pressure_fold.dart`) previously ported the `contextPressure`
projection from `.../llm/token-meter/src/usage-projection.ts`, now retired in
favor of direct host projection consumption in
[the context projection consumption note](../bug-fix/2026-08-30-context-pressure-host-projection-consumption.md).
`ChatPanel` passes the two projections to `ComposerBar`.

## Alternatives considered

- **Filter subagent children in the adapter**: rejected — the web applies
  the rule in the client tree derivation, and the chat screen still
  consumes subagent sessions through their own surfaces; the panel is the
  placement owner.
- **Nest subagent children under their parent in the tree**: rejected — the
  web browses children through the parent's subagent catalog view, not the
  sidebar tree.
- **Ring fed by `pressureTokens` alone**: rejected — the projection's view
  exists precisely so occupancy moves during a streaming turn; the last
  sample alone holds still and over-reports staleness after compaction.

## Consequences

Subagent children vanish from the sidebar tree, rail, and search; only the
selected blank session shows. The ring is a permanent composer seat — an
empty track until a usage sample and a route capacity exist — moves with
the surface during streaming, and drops after compaction; its visibility
and tap-open popup are decided in
[the ring visibility and popup note](../bug-fix/2026-08-29-context-ring-always-on-and-anchored-popup.md).
The token-drift gate flakes on first run (generator map ordering);
regeneration settles it byte-identical.
