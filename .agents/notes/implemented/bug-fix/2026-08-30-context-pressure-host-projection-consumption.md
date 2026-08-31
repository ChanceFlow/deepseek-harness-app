# Agent Note: Consume host contextPressure and contextBreakdown projections

Status: implemented

## Problem

The composer's context ring permanently rendered as an empty track (appearing as a "black circle" on dark theme `#46464F` background) even in sessions with active LLM turns. Three-party evidence revealed the root cause:
1. **Host authority**: The dsh backend token-meter (`reference/deepseek-harness/packages/llm/token-meter/src/usage-projection.ts` and `breakdown-projection.ts`) folds context pressure and breakdown on the host and exposes authoritative projection snapshots in `session.history` tail pages (`projections.values.contextPressure` and `contextBreakdown`) as well as real-time push frames (`session/projection`).
2. **Web reference**: The reference web client (`projection-store.ts`) only consumes finished projections under higher-seq-wins rules and performs zero client-side event folding.
3. **Mobile client breakpoint**: The mobile adapter's `_loadHistory` only consumed `goal`, `plan`, and `todos` from the `projections` block, and `_handleProjection` dropped `contextPressure` and `contextBreakdown` push frames. Meanwhile, a custom `ContextPressureFold` attempted to reconstruct context pressure by folding raw session events and relied on `request/context` envelopes for `contextWindow`. Because the host emits `request/context` only on route changes and history tail paging truncates older events, `contextWindow` remained `null` indefinitely, starving `ContextRing` of route capacity.

## Decision

The mobile client aligns with the reference web client by consuming host projections directly and retiring client-side folding:
1. **DTO decoders**: Hand-written fail-loud decoders in `dsh_wire_types.dart` (`decodeContextPressureProjection` and `decodeContextBreakdownProjection`) decode `contextPressure` (`pressureTokens`, `projectedTokens`, `contextWindow`) and `contextBreakdown` (`systemTokens`, `toolsTokens`, `messageTokens`). Optional field semantics match host snapshot authority: missing fields stay `null` (or default 0 for breakdown counts), and non-object values fail loud to `null` via `_tryDecode`.
2. **History seeding**: `_loadHistory` extracts `contextPressure` and `contextBreakdown` from the tail page's `projections.values` block and seeds `_SessionState` with `asOfSeq`.
3. **Push frames**: `_handleProjection` routes `contextPressure` and `contextBreakdown` keys, updating `_SessionState` under higher-seq-wins rules (`seq >= current`).
4. **Retire custom fold**: Retired `ContextPressureFold` completely from `_SessionState`, `harness_repository_impl.dart`, and package exports.
5. **Panel composition bar parity**: Aligned `ContextRing._panel` and `_breakdownBar` with web `ContextMeter.tsx:83-90,127-148` and `ContextMeter.module.css` `.bar/.segment`. The bar renders whenever the panel is open (a single `scheme.outline` fallback part when `breakdown == null` or its parts total 0); legend rows render only when `breakdown != null`, with tilde-prefixed compact figures. Width math is ported literally: the remaining window is the bar's own track background, each colored part is `panel-width × percent% × share` with the `.segment` **min-width 2px** and 1px gaps, and only exact-zero shares drop. Integer `Expanded` flexes were the first port and failed live: a compacted session on the 1M-token window sits at ~1% occupancy, every part rounded sub-pixel, and the bar read as a colorless track. `MenuAnchor` sizes its menu through an `IntrinsicWidth`, so the panel cannot measure the track with a `LayoutBuilder`; the width comes from the panel's own 264−24 constant.

## Alternatives considered

- **Fix `request/context` assumptions in `ContextPressureFold`**: rejected — the host emits `request/context` only on route changes rather than per turn. Folding from tail-paged history windows cannot reconstruct complete surface state or compaction claims accurately, whereas the host projection store persists O(1) state across the session lifecycle.
- **Wait for host push frames without history seeding**: rejected — history tail pages already supply the authoritative projection cut (`asOfSeq`); waiting for a subsequent push frame would leave cold-opened sessions on an empty track until the next request completes.
- **Retain custom fold as a dual-write fallback**: rejected — maintaining parallel client-side folding alongside authoritative host projections creates conflicting truth sources, duplicate state updates, and regression risks. Deleting `ContextPressureFold` simplifies the codebase to a single direct consumption path.

## Consequences

Opening an existing session or receiving push frames immediately populates `ContextPressure` (including `contextWindow=1000000` on standard models) and `ContextBreakdown`. The composer's `ContextRing` transitions from empty track placeholder to active determinate arc painted with `scheme.secondary` and `scheme.outlineVariant` track, and tap opens the composition panel with token figures and the always-rendered breakdown composition bar. Supersedes the client folding mechanism in [the sidebar and context ring note](../feature/2026-08-19-sidebar-visibility-context-ring.md) and repairs the data pipeline referenced in [the context ring visibility note](2026-08-29-context-ring-always-on-and-anchored-popup.md).
