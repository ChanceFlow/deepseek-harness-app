/// Host command roster — the mobile stand-in for the web slash-menu
/// sources (on the web each command-owning plugin registers an input-
/// trigger source; the adapter cannot enumerate them over the wire).
///
/// Names, descriptions, input hints, and image-acceptance flags mirror
/// the host command registry verbatim: plan (plan-mode), goal
/// (command-goal), compact (command-compact), permission
/// (permission-presets), feedback (command-feedback). `/export` stays
/// web-only (its handler downloads a ZIP through the browser, which
/// this client cannot host).
library;

import 'package:app/l10n/app_localizations.dart';

/// One roster entry: the slash name, its registry description, the
/// input hint shown as the row's trailing detail, and whether the
/// command admits composer image attachments.
final class HostCommand {
  const HostCommand(this.name, this.description, this.hint,
      {this.acceptsImages = false});

  final String name;
  final String description;
  final String? hint;
  final bool acceptsImages;
}

/// The built-in command roster, names and input hints only — the wire
/// membership check the controller performs (names and hints mirror host
/// syntax verbatim, never localized; the localized descriptions live in
/// [hostCommands]).
const List<HostCommand> kHostCommandNames = <HostCommand>[
  HostCommand('plan', '', '[off|message]', acceptsImages: true),
  HostCommand(
    'goal',
    '',
    '[<objective>|clear|edit <objective>|pause|resume]',
    acceptsImages: true,
  ),
  HostCommand('compact', '', null),
  HostCommand('permission', '', '<preset>'),
  HostCommand('feedback', '', '<text>'),
];

/// The built-in command roster; descriptions are localized, the input
/// hints mirror host syntax verbatim.
List<HostCommand> hostCommands(AppLocalizations l10n) => <HostCommand>[
  HostCommand('plan', l10n.commandPlanDescription, '[off|message]',
      acceptsImages: true),
  HostCommand(
    'goal',
    l10n.commandGoalDescription,
    '[<objective>|clear|edit <objective>|pause|resume]',
    acceptsImages: true,
  ),
  HostCommand('compact', l10n.commandCompactDescription, null),
  HostCommand(
    'permission',
    l10n.commandPermissionDescription,
    '<preset>',
  ),
  HostCommand('feedback', l10n.commandFeedbackDescription, '<text>'),
];

/// The host-command line a submit routes through `commands/execute`
/// (the web `matchEnter` decision table on the roster's stand-in), or
/// null when the text is not a host command. Input-hinted commands are
/// args-tolerant; bare-only commands (no hint) execute bare only; any
/// other line rides the prompt channel.
String? hostCommandLineFor(String text) {
  if (!text.startsWith('/')) return null;
  final boundary = text.indexOf(RegExp(r'[\t\n\r ]'));
  final token = boundary == -1 ? text : text.substring(0, boundary);
  final name = token.substring(1);
  if (name.isEmpty) return null;
  for (final command in kHostCommandNames) {
    if (command.name != name) continue;
    // A bare-only command (no input hint) with args rides the prompt
    // channel (web: `if (!bare) return undefined`).
    if (command.hint == null && boundary != -1) return null;
    return text;
  }
  return null;
}

/// The command name a submission carrying images must refuse, or null
/// when the line is not a dispatched host command or the command
/// admits attachments. Web envelope policy: an enter submission
/// carrying images resolves only through a command declaring image
/// acceptance — every other command route refuses before anything
/// executes, keeping the draft and the images in place.
String? hostCommandImageRefusal(String text) {
  if (hostCommandLineFor(text) == null) return null;
  final boundary = text.indexOf(RegExp(r'[\t\n\r ]'));
  final token = boundary == -1 ? text : text.substring(0, boundary);
  final name = token.substring(1);
  for (final command in kHostCommandNames) {
    if (command.name == name) {
      return command.acceptsImages ? null : name;
    }
  }
  return null;
}

/// Whether [text] dispatches as a bare-only host command — one whose
/// registry entry advertises no input hint (today only `compact`). The
/// web routes bare commands through a detached execute: the composer is
/// freed immediately and the outcome arrives as a timeline flow node,
/// never a held sending state. Input-hinted commands (`plan`, `goal`,
/// `permission`, `feedback`) stay attached: their submissions settle
/// fast and keep the draft-for-correction semantics.
bool hostCommandIsBare(String text) {
  final line = hostCommandLineFor(text);
  if (line == null) return false;
  final boundary = line.indexOf(RegExp(r'[\t\n\r ]'));
  final token = boundary == -1 ? line : line.substring(0, boundary);
  final name = token.substring(1);
  for (final command in kHostCommandNames) {
    if (command.name == name) return command.hint == null;
  }
  return false;
}
