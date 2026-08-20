# Agent Note: Sidebar groups sessions by workspace account membership

Status: implemented

## Problem

No session ever landed in a sidebar workspace group — every session fell
into the Ungrouped bucket. The grouping matched on a `workspaceId` field
of the domain session summary, but the wire `SessionSummary`
(`reference/deepseek-harness/packages/host/apiproxy/src/api/sessions.ts`)
carries no workspace field at all, so the field was always null and the
predicate never matched.

## Decision

Sidebar membership follows the web rule exactly
(`reference/deepseek-harness/packages/client/ui-workspace/src/client/tree.ts`,
`groupByWorkspace`): a session belongs to the workspace whose account
`sessionIds` names it. Each workspace renders one group in host registry
order with members in the account's stored order (not recency — the
account order is the product decision); sessions no account names trail
in the Ungrouped bucket newest-first. The current-group derivation (which
account holds the selected session) and the search-result workspace label
use the same membership lookup. The dead `SessionSummary.workspaceId`
domain field is removed — the wire never carries it, and a permanently
null field invites the next membership bug.

## Alternatives considered

- **Populate `workspaceId` in the adapter by scanning workspace
  accounts**: rejected — it would duplicate the membership relation in a
  second place and desynchronize on registry updates the panel already
  observes.
- **Keep the field for future wire coverage**: rejected — the host has no
  such field; speculative coverage contradicts fail-loud wire decoding.

## Consequences

Workspace groups populate from the workspace registry alone; the account
may lead the session list pull, in which case a member row appears when
its summary lands (web rule, ported). Blank-session and subagent-origin
visibility rules compose unchanged ahead of grouping. Tests cover
membership grouping, stored member order, the folded Ungrouped bucket,
and the no-Ungrouped-header-when-empty case.
