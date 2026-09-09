# Agent Note: DSH 0.1.2 Restore Cursor Auto-Discovery and Cards Precedence Alignment

Status: implemented

## Problem

Following the DSH 0.1.2 migration, two severe user-facing regressions and protocol drift issues emerged:

1. **Startup Auto-Restore Fails to Load Session Content**:
   When the client reopens and auto-restores the last-selected session from device-local state (`LocalStateStore`), the conversation timeline remained permanently blank. In commit `8a98c29` (PR #178), while locking RPC endpoints to canonical DSH 0.1.2 naming, the invoker fallback block was deleted. In doing so, the vital auto-cursor discovery mechanism added in commit `c6240aa` was stripped. Because DSH 0.1.2 `session/page` strictly forbids `throughSeq > sourceCursor` (`gateway/bad-request: session page through seq 999999999 is past cursor X`), and cold sessions without projection metadata do not index `asOfSeq` in `_sessionCursors`, `_loadHistory` sent `throughSeq: 999999999`. The server rejected the call, `ensureLoaded` caught the exception and aborted, leaving the restored session empty. Furthermore, `SessionHistoryValueWire.asOfSeq` was permanently `-1` because 0.1.2 `session/page` returns `SessionPage { records, hasMore }` without `projections`, so history never updated the cursor cache.

2. **Ask and Plan Cards Drifted in Placement, Timing, and Precedence**:
   In canonical DSH 0.1.2 (`dsh-client-ui-user-questions` and `dsh-plan-mode`), questions and plan reviews are composer takeovers (`conversation.composer` slot) that mount in the input dock replacing `ComposerBar` with strict precedence (`plan-review (2) > question (1) > approval (0)`), while standing down `StatsLine`, `TodoPanel`, and `GoalBarStrip`. In the Flutter client, `TimelineQuestionRequest` was incorrectly routed into `_timelineBody`'s `ListView.builder` as a scrollable transcript item (`QuestionRow`), while the composer bar remained active at the bottom. `_PlanReviewCard` also used error red (`errorContainer` / `scheme.error`) instead of the warning amber role (`scheme.warning`) and lacked scroll constraints.

## Decision

1. **Canonical Cursor Auto-Discovery in `DshRemoteInvoker`**:
   - In `DshRemoteInvoker.call`, when `endpoint == DshRpcEndpoints.sessionPage` returns an error matching `r'past cursor (-?\d+)'`, the invoker parses the authoritative `sourceCursor` (including `-1` for empty sessions) and immediately retries the call with `throughSeq: cursor`.
   - In `HarnessRepositoryImpl._loadSessions`, index session cursors when `session.asOfSeq >= 0` (supporting sequence 0).
   - In `HarnessRepositoryImpl._loadHistory` and `loadSubagentHistory`, update `_sessionCursors` from `history.events.last['seq']` (or `-1` if empty) instead of the absent projection `history.asOfSeq`.
   - In `ChatController._maybeRestoreSelectedSession`, only conclude a stored session is absent after initial `refreshSessions()` has settled (`_sessionsRefreshed`), preventing premature abandonment on empty list seeds.

2. **Composer Takeover with 3-Tier Precedence in `ChatScreen`**:
   - Exclude `TimelineQuestionRequest` and `TimelineApprovalRequest` from `_timelineItems` so they never render as scrolling transcript items in the message list.
   - Promote `QuestionRow` to the composer takeover seat in `_InputDock` with canonical 0.1.2 precedence:
     1. `_pendingQuestion` (with `_planReviewOf` -> `_PlanReviewCard`) [Priority 2]
     2. `_pendingQuestion` (generic -> `_QuestionCard`) [Priority 1]
     3. `_pendingApproval` (`ApprovalPanel`) [Priority 0]
     4. Default: `ComposerBar`
   - When any decision is pending (`_hasPendingDecision`), `StatsLine`, `TodoPanel`, and `GoalBarStrip` stand down, and `TurnStatusRow` rotating status indicator is suppressed.
   - In `_PlanReviewCard`, replace `errorContainer` and `scheme.error` with warning amber tokens (`scheme.warning` dot and header text, `scheme.warning.withValues(alpha: 0.12)` strip background, `scheme.outlineVariant` border), and wrap the plan markdown in `ConstrainedBox(maxHeight: ...)` with `SingleChildScrollView` to prevent viewport overflow.

## Alternatives considered

- **Requiring `session/follow` stream instead of unary `session/page` for history loading**: Deferred — while `session/follow` is the browser client's canonical opening stream, the Flutter adapter's unary paging architecture over `session/page` is fully functional once cursor discovery is restored, avoiding an invasive rewrite of `HarnessRepositoryImpl` stream topology.
- **Keeping `QuestionRow` in the transcript while mirroring it in the dock**: Rejected — rendering interactive quiz and plan review widgets inside the historical chat log violates DSH 0.1.2's composer takeover architecture, causes duplicate rendering, and causes jarring layout shifts when the question resolves.
- **Using a fixed dialog or modal bottom sheet for questions and plan review**: Rejected — DSH stock Material 3 design and reference web client parity anchor interactive decisions directly in the input dock (`_InputDock`), keeping conversation context visible above the decision card.

## Consequences

- Cold-start session restore reliably loads the full conversation history across cold logs, empty sessions, and long message histories without getting blocked by server cursor checks.
- Ask and plan review cards consistently take over the input dock with exact DSH 0.1.2 precedence and appropriate warning amber aesthetics.
- Decision cards constrain long plan markdown text to a scrollable container, preventing layout overflows on mobile screens.
- All integration tests pass cleanly and verify auto-cursor discovery, empty session recovery, dock takeovers, and precedence arbitration.
