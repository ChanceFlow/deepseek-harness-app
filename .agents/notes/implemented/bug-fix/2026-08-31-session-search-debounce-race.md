# Agent Note: Session search debounce, race guard, and local match layer

Status: implemented

## Problem

In `ChatController._searchSessions`, session search dispatched an immediate host `session.search` RPC on every keystroke without debouncing or cancellation. Each host response unconditionally overwrote `_searchResults`, creating an out-of-order race where a slow response for an older query could overwrite a faster response for a newer query. Furthermore, empty queries were not short-circuiting pending searches, queries lacked the wire-contract length cap and NUL sanitization, and client-side metadata matches (session title and workspace label) were omitted unless returned by the host content index. A comment in `session_panel.dart` incorrectly claimed "debounce lives in the host wiring", whereas in the reference web implementation, debouncing, query cancellation, sanitization, and local metadata matching reside entirely in the client UI controller.

## Decision

Aligned `ChatController._searchSessions` with the reference web implementation (`WorkspaceBrowser.tsx` and `tree.ts`):

1. **Trailing Debounce (250ms)**: Added `_searchDebounceDelay = Duration(milliseconds: 250)` (mirroring `WorkspaceBrowser.tsx` line 35 `SEARCH_DEBOUNCE_MS`). Typing within the window cancels the pending timer and re-arms. An empty or whitespace-only query cancels any pending debounce timer, clears `_searchResults` immediately, and returns without dispatching a host RPC.
2. **Monotonic Sequence Guard**: Introduced `int _searchSeq` incremented on each search action. Because the Dart repository interface does not accept an `AbortSignal`, this latest-wins sequence check provides the semantic equivalent of the reference's per-query `AbortController` (`WorkspaceBrowser.tsx` lines 872 and 900), guaranteeing that only responses from the latest dispatched search sequence may update `_searchResults`.
3. **Query Sanitization and 500 Code-Unit Cap**: Implemented `_sanitizeSearchQuery` (mirroring `WorkspaceBrowser.tsx` lines 42–50 `sanitizeSearchQuery` and line 37 `SEARCH_QUERY_MAX_CODE_UNITS`). Strips NUL (`\x00`) characters and bounds length to 500 UTF-16 code units while preventing truncation from splitting surrogate pairs.
4. **Local Match and Merge Layer**: Added `_mergeSearchResults` (mirroring `tree.ts` lines 321–393 `deriveSearchResults`). Evaluates client-side session titles (`session.displayTitle`) and workspace labels/titles against the case-insensitive trimmed query, filtering out blank placeholders and subagent children. Local matches are sorted by recency (`updatedAtEpochMs` descending, tie-breaking on session ID, matching `tree.ts` line 107 `byRecency`) and placed ahead of host content results, with host snippets attached when available and de-duplicated by session ID.
5. **Deferred UI Comment Cleanup**: Left the stale comment in `session_panel.dart` line 201 untouched to prevent merge collisions with concurrent agents editing UI files; noted here for future refactoring sweeps.

## Alternatives considered

- **Debouncing inside `session_panel.dart` UI widget**: Rejected — moving debounce and race handling into the UI widget would duplicate state management, complicate widget lifecycle disposal, and violate the controller UDF architectural pattern.
- **Dropping local matches and relying solely on host index**: Rejected — reference web client (`tree.ts` `deriveSearchResults`) computes local metadata matches synchronously so titles and workspace names surface instantly even when offline or before the host search RPC settles.
- **Cancelling HTTP requests via custom transport hooks**: Rejected — the repository interface does not expose cancellation tokens, and monotonic sequence comparison achieves identical latest-wins consistency without altering transport contracts.

## Consequences

Keystrokes in the session search input are debounced by 250ms, eliminating redundant host RPC bursts. Local title and workspace matches appear immediately upon typing. Monotonic sequence tagging prevents slow out-of-order network responses from overwriting newer query results. Wire bounds (500 UTF-16 code units and NUL stripping) protect host payloads. Controller disposal cleanly cancels pending debounce timers.
