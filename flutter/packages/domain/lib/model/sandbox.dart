/// Session sandbox-mode fact.
///
/// A runtime switch appends one `sandbox/mode` session event; the LAST such
/// event is the session's override (`effective = override ?? deployment
/// default`). The event is log-only. Wire truth:
/// `reference/deepseek-harness/packages/sandbox/sandbox-policy/src/
/// session-mode.ts` (`SANDBOX_MODES`).
library;

/// The three confinement modes the session policy can select.
enum SandboxMode { readOnly, workspaceWrite, dangerFullAccess }

/// One session's effective sandbox-mode override.
final class SandboxModeFact {
  const SandboxModeFact({required this.mode, this.seededByDelegation = false});

  final SandboxMode mode;

  /// True when the override was seeded into a child at delegation
  /// (`source: 'delegation'`) rather than switched at runtime.
  final bool seededByDelegation;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SandboxModeFact &&
          other.mode == mode &&
          other.seededByDelegation == seededByDelegation);

  @override
  int get hashCode => Object.hash(mode, seededByDelegation);
}
