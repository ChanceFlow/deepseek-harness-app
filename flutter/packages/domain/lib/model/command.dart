/// Host-command vocabulary — the `commands/execute` result slot.
///
/// A slash-command line submitted by the user runs through the host's
/// command registry (never the model); this is the settled execution the
/// host returns: the lifecycle pairing id and the handler's outcome.
library;

/// The handler's outcome kind.
enum CommandOutcomeKind { success, error }

/// One settled host-command execution.
final class CommandExecution {
  const CommandExecution({
    required this.commandId,
    required this.kind,
    this.text,
  });

  /// Pairing id carried by this execution's `command/run`/`command/done`
  /// lifecycle events.
  final String commandId;

  final CommandOutcomeKind kind;

  /// The handler's human-readable outcome (success carries one only when
  /// the command produced text; errors always do).
  final String? text;
}
