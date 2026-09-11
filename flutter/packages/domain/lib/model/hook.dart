/// Durable hook-audit vocabulary.
///
/// `hook/invoked` / `hook/result` are log-only session events (the
/// reference marks them NOT a `SurfaceEventType`): a bridge that runs a
/// configured `PreToolUse`/`Stop`/… hook records the invocation and its
/// decided outcome so a blocking deny has an audit trail instead of reading
/// as an ordinary tool failure. Wire truth:
/// `reference/deepseek-harness/packages/hooks/hook-protocol/src/events.ts`
/// and `types.ts`.
library;

/// Which hook bridge ran the invocation (`HookDialect`).
enum HookDialect { claudeCode, codex }

/// One hook invocation paired with its settled outcome.
///
/// [decision] is the reference's derived durable decision — the parsed
/// permission result, `stop` for `continue:false`, or `pass` — and stays a
/// string because the bridge dialect's vocabulary is merge-extensible.
/// [settled] is false while only `hook/invoked` has been folded.
final class HookAudit {
  const HookAudit({
    required this.handlerId,
    required this.turn,
    required this.point,
    required this.dialect,
    this.matcher,
    this.decision,
    this.exitCode,
    this.stderrSummary,
    this.durationMs,
  });

  /// Stable id correlating the invoked event with its result.
  final String handlerId;

  /// The open turn the invocation lives inside.
  final int turn;

  /// The hook point (`PreToolUse`, `Stop`, …).
  final String point;

  final HookDialect dialect;

  /// The matcher-group pattern that selected it; null for match-all.
  final String? matcher;

  /// The derived durable decision, or null while the pair is unsettled.
  final String? decision;

  /// Raw process exit code; null when the hook could not be run.
  final int? exitCode;

  /// Trimmed, capped stderr summary; null when stderr was blank.
  final String? stderrSummary;

  /// Wall-clock duration of the run; null until the result lands.
  final int? durationMs;

  /// Whether the paired `hook/result` has been folded.
  bool get settled => decision != null;

  HookAudit withResult({
    required String decision,
    required int durationMs,
    int? exitCode,
    String? stderrSummary,
  }) => HookAudit(
    handlerId: handlerId,
    turn: turn,
    point: point,
    dialect: dialect,
    matcher: matcher,
    decision: decision,
    exitCode: exitCode,
    stderrSummary: stderrSummary,
    durationMs: durationMs,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HookAudit &&
          other.handlerId == handlerId &&
          other.turn == turn &&
          other.point == point &&
          other.dialect == dialect &&
          other.matcher == matcher &&
          other.decision == decision &&
          other.exitCode == exitCode &&
          other.stderrSummary == stderrSummary &&
          other.durationMs == durationMs);

  @override
  int get hashCode => Object.hash(
    handlerId,
    turn,
    point,
    dialect,
    matcher,
    decision,
    exitCode,
    stderrSummary,
    durationMs,
  );
}
