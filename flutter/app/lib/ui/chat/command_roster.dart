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

import 'package:app/l10n/app_localizations.dart';

/// One roster entry: the slash name, its registry description, and the
/// input hint shown as the row's trailing detail.
final class HostCommand {
  const HostCommand(this.name, this.description, this.hint);

  final String name;
  final String description;
  final String? hint;
}

/// The built-in command roster; descriptions are localized, the input
/// hints mirror host syntax verbatim.
List<HostCommand> hostCommands(AppLocalizations l10n) => <HostCommand>[
  HostCommand('plan', l10n.commandPlanDescription, '[off|message]'),
  HostCommand(
    'goal',
    l10n.commandGoalDescription,
    '[<objective>|clear|edit <objective>|pause|resume]',
  ),
  HostCommand('compact', l10n.commandCompactDescription, null),
  HostCommand(
    'permission',
    l10n.commandPermissionDescription,
    '<preset>',
  ),
  HostCommand('feedback', l10n.commandFeedbackDescription, '<text>'),
];
