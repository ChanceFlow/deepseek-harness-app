/// Host command roster — the mobile stand-in for the web slash-menu
/// sources (on the web each command-owning plugin registers an input-
/// trigger source; the adapter cannot enumerate them over the wire).
///
/// Names, descriptions, and input hints mirror the host command registry
/// verbatim: plan (plan-mode), goal (command-goal), compact
/// (command-compact), permission (permission-presets), feedback
/// (command-feedback). `/export` stays web-only (its handler downloads a
/// ZIP through the browser, which this client cannot host).
library;

/// One roster entry: the slash name, its registry description, and the
/// input hint shown as the row's trailing detail.
final class HostCommand {
  const HostCommand(this.name, this.description, this.hint);

  final String name;
  final String description;
  final String? hint;
}

const List<HostCommand> kHostCommands = <HostCommand>[
  HostCommand('plan', 'Enter or leave plan mode', '[off|message]'),
  HostCommand(
    'goal',
    'set or view the goal for a long-running task',
    '[<objective>|clear|edit <objective>|pause|resume]',
  ),
  HostCommand('compact', 'Compact older conversation history', null),
  HostCommand(
    'permission',
    'Switch the permission preset (sandbox mode + approval policy)',
    '<preset>',
  ),
  HostCommand('feedback', 'record feedback about this session', '<text>'),
];
