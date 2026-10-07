/// Cross-session `@` mention candidates (`sessionReferenceResolver/
/// candidates`).
///
/// Reference: `reference/deepseek-harness/packages/context/session-reference/
/// src/types.ts` `SessionReferenceMentionCandidate` — the discovery record
/// plus the canonical `@[label](dsh-session:…)` mention the host serializes
/// into the prompt draft. The mention is opaque to the client: the composer
/// inserts its text and the host parses it back at prompt time
/// (packages/context/session-reference/src/uri.ts
/// `parseSessionReferenceText`).
library;

/// One session the reader can cite from the composer.
final class SessionReferenceCandidate {
  const SessionReferenceCandidate({
    required this.sessionId,
    required this.label,
    required this.mention,
    required this.sameWorkspace,
    required this.createdAtEpochMs,
    this.displayTitle,
    this.cwd,
  });

  /// Opaque source-session identity. The host excludes the requesting
  /// session itself, so this never names the session being addressed.
  final String sessionId;

  /// Latest log-backed title, falling back to the opaque session id.
  final String label;

  /// Display and mention label, preferring a subagent's durable creation
  /// label over [label]. Absent when the host projected no title.
  final String? displayTitle;

  /// The source session's working directory, when the host recorded one.
  final String? cwd;

  /// True when [cwd] is recorded and equals the requesting session's own.
  /// The host answers this rather than making the client compare a path it
  /// never received.
  final bool sameWorkspace;

  /// Creation time in Unix epoch milliseconds.
  final int createdAtEpochMs;

  /// Canonical `@[label](dsh-session:…)` mention the composer inserts and
  /// the host parses back out of the prompt text.
  final String mention;

  /// The label a row shows: the projected display title when there is one,
  /// [label] otherwise.
  String get rowTitle => displayTitle ?? label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionReferenceCandidate &&
          other.sessionId == sessionId &&
          other.label == label &&
          other.displayTitle == displayTitle &&
          other.cwd == cwd &&
          other.sameWorkspace == sameWorkspace &&
          other.createdAtEpochMs == createdAtEpochMs &&
          other.mention == mention);

  @override
  int get hashCode => Object.hash(
    sessionId,
    label,
    displayTitle,
    cwd,
    sameWorkspace,
    createdAtEpochMs,
    mention,
  );
}
