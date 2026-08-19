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
The fold (`context_pressure_fold.dart`) ports the `contextPressure`
projection from `.../llm/token-meter/src/usage-projection.ts`: a running
heuristic surface total over model-visible messages
(user/assistant/tool-result content under the fixed density estimator), a
usage sample stamping `sampledSurfaceTokens` before its own event joins the
surface, and `projectedTokens = max(0, pressureTokens + surfaceTokens -
sampledSurfaceTokens)`. Compaction subtracts `shadowedTokenCount` and the
adjacent replacement message rejoins through the ordinary append estimate —
the arithmetic equivalent of the web's claim/replace protocol under the same
estimator. `ChatPanel` passes the two projections to `ComposerBar`.

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
selected blank session shows. The ring renders once a provider reports a
usage sample and a route capacity, moves with the surface during streaming,
and drops after compaction. The token-drift gate flakes on first run
(generator map ordering); regeneration settles it byte-identical.
