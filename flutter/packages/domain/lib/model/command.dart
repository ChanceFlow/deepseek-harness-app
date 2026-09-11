/// Host-command vocabulary — the live registry roster and the
/// `commands/execute` result slot.
///
/// A slash-command line submitted by the user runs through the host's
/// command registry (never the model); [CommandDescriptor] is one live
/// registry entry (`commands/list`) and [CommandExecution] is the settled
/// execution the host returns.
library;

/// The handler's outcome kind.
enum CommandOutcomeKind { success, error }

/// One live command-registry entry (`commands/list`, a
/// `CommandDescriptor` from
/// `reference/deepseek-harness/packages/interaction/commands/src/types.ts`).
///
/// [inputHint] is the command's advertised free-form input placeholder. Its
/// absence is the wire's own bare-only signal: a command that declares no
/// `input` accepts no arguments, so a dispatching surface must send the
/// bare line through the prompt channel instead (web `matchEnter`:
/// `if (!bare) return undefined`). When present, the command is
/// args-tolerant: the whole line rides `commands/execute`.
///
/// [acceptsAttachments] mirrors the descriptor's `input.attachments` flag:
/// a submission carrying images resolves only through a command that
/// declares image acceptance; every other command route refuses before
/// anything executes.
final class CommandDescriptor {
  const CommandDescriptor({
    required this.name,
    required this.description,
    this.inputHint,
    this.acceptsAttachments = false,
  });

  /// Lowercase command name without the leading slash.
  final String name;

  /// Human-readable summary the host's registry published.
  final String description;

  /// Advertised free-form input hint; null when the command advertises no
  /// input and is therefore bare-only.
  final String? inputHint;

  /// Whether composer attachments may accompany an invocation.
  final bool acceptsAttachments;

  /// Whether the command advertises free-form input.
  bool get acceptsArgs => inputHint != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CommandDescriptor &&
          other.name == name &&
          other.description == description &&
          other.inputHint == inputHint &&
          other.acceptsAttachments == acceptsAttachments);

  @override
  int get hashCode =>
      Object.hash(name, description, inputHint, acceptsAttachments);
}

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CommandExecution &&
          other.commandId == commandId &&
          other.kind == kind &&
          other.text == text);

  @override
  int get hashCode => Object.hash(commandId, kind, text);
}
