# Agent Note: DSH 0.1.2 Restore Cursor Auto-Discovery, Cards Precedence, and ContextRing Stream Projections

Status: implemented

## Problem

Following the DSH 0.1.2 migration, three severe regressions and protocol drift issues emerged:

1. **Startup Auto-Restore Fails to Load Content**:
   When reopening and auto-restoring the last-selected session from `LocalStateStore`, the timeline remained blank. In PR #178, the invoker fallback block was deleted, stripping the auto-cursor discovery added in `c6240aa`. Because DSH 0.1.2 `session/page` rejects `throughSeq > sourceCursor` (`gateway/bad-request: session page through seq 999999999 is past cursor X`), and cold sessions without projection metadata do not index `asOfSeq`, `_loadHistory` sent `throughSeq: 999999999`. The server rejected the call and `ensureLoaded` aborted. Furthermore, `SessionHistoryValueWire.asOfSeq` was permanently `-1` because 0.1.2 `session/page` returns `{ records, hasMore }` without `projections`, so history never updated the cursor cache.

2. **Ask and Plan Cards Drifted in Placement, Timing, and Precedence**:
   In canonical DSH 0.1.2 (`dsh-client-ui-user-questions` and `dsh-plan-mode`), questions and plan reviews are composer takeovers (`conversation.composer` slot) that mount in the input dock replacing `ComposerBar` with strict precedence (`plan-review (2) > question (1) > approval (0)`), standing down `StatsLine`, `TodoPanel`, and `GoalBarStrip`. In Flutter, `TimelineQuestionRequest` was incorrectly routed into `_timelineBody`'s `ListView.builder` as a scrollable transcript item (`QuestionRow`), while the composer bar remained active below. `_PlanReviewCard` also used error red instead of warning amber (`scheme.warning`) and lacked scroll constraints.

3. **Context Ring and Live Projections Silently Failed Without Logs**:
   The composer context occupancy ring (`ContextRing`) stopped working. In DSH 0.1.2, session projections (`contextPressure`, `contextBreakdown`, `plan`, `todos`, `goal`, `permissions`, `title`) broadcast via `session/control` stream on `/api/remote.mux`. `DshConnectionManager` only subscribed to `workspace/follow` and omitted `session/control`. Additionally, `_collectMuxFrames` strictly matched `type == 'session/projection'` (missing 0.1.2's `type == 'projection'`), and `_loadSessions()` never seeded projections from `session.list`. Zero error logs were generated because `_tryDecode` swallowed `FormatException` and `TypeError`, `ContextRing` treats `pressure == null` as a normal empty track without throwing, and unhandled frames in `_collectMuxFrames` were silently discarded.

## Decision

1. **Canonical Cursor Auto-Discovery in `DshRemoteInvoker`**:
   - In `DshRemoteInvoker.call`, when `endpoint == DshRpcEndpoints.sessionPage` returns an error matching `r'past cursor (-?\d+)'`, parse the authoritative `sourceCursor` (including `-1` for empty sessions) and retry with `throughSeq: cursor`.
   - In `HarnessRepositoryImpl._loadSessions`, index session cursors when `session.asOfSeq >= 0`.
   - In `_loadHistory` and `loadSubagentHistory`, update `_sessionCursors` from `history.events.last['seq']` (or `-1` if empty) instead of absent `history.asOfSeq`.
   - In `ChatController._maybeRestoreSelectedSession`, only conclude a stored session is absent after initial `refreshSessions()` has settled (`_sessionsRefreshed`).

2. **Composer Takeover with 3-Tier Precedence in `ChatScreen`**:
   - Exclude `TimelineQuestionRequest` and `TimelineApprovalRequest` from `_timelineItems` so they never render as scrolling transcript items.
   - Promote `QuestionRow` to composer takeover seat in `_InputDock` with canonical 0.1.2 precedence: `planReview (2) > question (1) > approval (0) > ComposerBar`.
   - When any decision is pending (`_hasPendingDecision`), suppress `StatsLine`, `TodoPanel`, `GoalBarStrip`, and `TurnStatusRow` rotating status indicator.
   - In `_PlanReviewCard`, replace `errorContainer`/`scheme.error` with warning amber tokens (`scheme.warning`), and wrap plan markdown in `ConstrainedBox(maxHeight: ...)` with `SingleChildScrollView`.

3. **Open `session/control` Stream, Seed Projections, and Bridge Diagnostics**:
   - In `DshConnectionManager`, open `session-control` (`endpoint: 'session/control'`) alongside `workspace-follow` over `/api/remote.mux`.
   - In `HarnessRepositoryImpl`, disambiguate `session-control` baseline from `workspace-follow` baseline, parse control baseline projections/queues/jobs, and handle live `type: "projection"` frames for all keys including `agentPreset`.
   - In `_loadSessions`, seed `contextPressure`, `contextBreakdown`, `plan`, `todos`, `goal`, `permissions`, and `title` for every session from `session.projectionValues`.
   - In `timeline_reducer.dart`, support both `queue` / `session/queue` and `jobs` / `session/jobs`.
   - Introduce a pure-Dart diagnostic seam (`AdapterDiagnostic` + `AdapterDiagnosticListener`) in `harness_adapter`. Bridge it in `app/lib/di/providers.dart` into `ErrorLogCollector.instance` and `DebugTelemetry.instance`. Instrument `_tryDecode`, `openSession`, and unhandled frame types so silent failures are permanently eliminated.

## Alternatives considered

- **Polling `session.list` for projections without `session/control` stream**: Rejected — token usage during streaming turns and realtime todo/goal updates require push latency; polling introduces latency and excessive server load.
- **Requiring `session/follow` stream instead of unary `session/page` for history loading**: Deferred — while `session/follow` is the browser client's canonical opening stream, the Flutter adapter's unary paging architecture over `session/page` is fully functional once cursor discovery is restored.
- **Directly importing `ErrorLogCollector` inside `harness_adapter`**: Rejected — `packages/harness_adapter` is an anti-corruption layer that must not depend on `app` or `flutter` (enforced by `scripts/check_dart_imports.py`). The pure-Dart callback seam preserves module boundaries while delivering full diagnostic visibility.

## Consequences

- Cold-start session restore reliably loads the full conversation history across cold logs, empty sessions, and long message histories without server cursor rejections.
- Ask and plan review cards consistently take over the input dock with exact DSH 0.1.2 precedence and appropriate warning amber aesthetics.
- ContextRing immediately populates token pressure and breakdown on session open and continues updating live during streaming turns.
- Wire payload drift, bad projection shapes, or unhandled frames produce breadcrumbs and persistent error records in the Error Logs screen (`ErrorLogsScreen`) and SigNoz telemetry dashboard.
- All integration tests pass cleanly and verify auto-cursor discovery, empty session recovery, dock takeovers, control baselines, and precedence arbitration.
