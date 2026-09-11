/// Host command roster — the mobile stand-in for the web slash-menu
/// sources (on the web each command-owning plugin registers an input-
/// trigger source).
///
/// The live roster is `commands/list` (`ChatUiState.commands`): every
/// decision below consults it, so a host- or plugin-registered command is
/// dispatchable even though this file never names it. The static list is
/// only the pre-first-pull fallback — before a pull settles, and when one
/// fails (a subagent-owned session answers `session/agent-busy`), the
/// composer still offers and dispatches the built-in commands instead of
/// going empty.
///
/// Names, descriptions, input hints, and image-acceptance flags in the
/// static list mirror the host command registry verbatim: plan (plan-mode),
/// goal (command-goal), compact (command-compact), permission
/// (permission-presets), feedback (command-feedback), export
/// (session-log-download). `/export` is the one entry the client executes
/// itself: the host's handler only acknowledges the request because the
/// browser owns that transfer, so a bare `/export` runs the session-log
/// download locally (see `ChatController._exportSessionLog`) and never
/// rides `commands/execute`.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/command.dart';

/// One roster entry: the slash name, its registry description, the
/// input hint shown as the row's trailing detail, and whether the
/// command admits composer image attachments.
final class HostCommand {
  const HostCommand(
    this.name,
    this.description,
    this.hint, {
    this.acceptsImages = false,
  });

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
  HostCommand('export', '', null),
];

/// The built-in command roster; descriptions are localized, the input
/// hints mirror host syntax verbatim.
List<HostCommand> hostCommands(AppLocalizations l10n) => <HostCommand>[
  HostCommand(
    'plan',
    l10n.commandPlanDescription,
    '[off|message]',
    acceptsImages: true,
  ),
  HostCommand(
    'goal',
    l10n.commandGoalDescription,
    '[<objective>|clear|edit <objective>|pause|resume]',
    acceptsImages: true,
  ),
  HostCommand('compact', l10n.commandCompactDescription, null),
  HostCommand('permission', l10n.commandPermissionDescription, '<preset>'),
  HostCommand('feedback', l10n.commandFeedbackDescription, '<text>'),
  HostCommand('export', l10n.commandExportDescription, null),
];

/// Decision facts for one live `commands/list` roster: the name, the input
/// hint that decides bare-only versus arg-taking dispatch, and the
/// attachment flag. Descriptions ride along but every decision below reads
/// only the name, hint, and flag.
List<HostCommand> hostCommandFacts(List<CommandDescriptor> commands) =>
    <HostCommand>[
      for (final command in commands)
        HostCommand(
          command.name,
          command.description,
          command.inputHint,
          acceptsImages: command.acceptsAttachments,
        ),
    ];

/// Display roster for one live `commands/list` roster: a name the static
/// roster knows keeps its localized description; a host- or
/// plugin-registered name the client has no translation for shows the
/// host's description verbatim.
List<HostCommand> hostCommandsFor(
  AppLocalizations l10n,
  List<CommandDescriptor> commands,
) {
  final localized = <String, HostCommand>{
    for (final command in hostCommands(l10n)) command.name: command,
  };
  return <HostCommand>[
    for (final command in commands)
      HostCommand(
        command.name,
        localized[command.name]?.description ?? command.description,
        command.inputHint,
        acceptsImages: command.acceptsAttachments,
      ),
  ];
}

/// The host-command line a submit routes through `commands/execute`
/// (the web `matchEnter` decision table), or null when the text is not a
/// host command. Input-hinted commands are args-tolerant; bare-only
/// commands (no hint) execute bare only; any other line rides the prompt
/// channel. [roster] is the live facts once a pull settled; it defaults to
/// the static fallback.
String? hostCommandLineFor(
  String text, [
  List<HostCommand> roster = kHostCommandNames,
]) {
  if (!text.startsWith('/')) return null;
  final boundary = text.indexOf(RegExp(r'[\t\n\r ]'));
  final token = boundary == -1 ? text : text.substring(0, boundary);
  final name = token.substring(1);
  if (name.isEmpty) return null;
  for (final command in roster) {
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
String? hostCommandImageRefusal(
  String text, [
  List<HostCommand> roster = kHostCommandNames,
]) {
  if (hostCommandLineFor(text, roster) == null) return null;
  final boundary = text.indexOf(RegExp(r'[\t\n\r ]'));
  final token = boundary == -1 ? text : text.substring(0, boundary);
  final name = token.substring(1);
  for (final command in roster) {
    if (command.name == name) {
      return command.acceptsImages ? null : name;
    }
  }
  return null;
}

/// Whether [text] is the bare `/export` line the client runs itself.
///
/// The host's `/export` handler only reports that a download was requested
/// — the browser owns the transfer there — so dispatching it through
/// `commands/execute` would acknowledge a ZIP nobody downloads. The client
/// intercepts the bare line and runs the session-log download locally.
/// Args (which the host rejects) follow the roster's bare-only rule and
/// ride the prompt channel instead.
bool isBareSessionLogExport(String text) => text.trim() == '/export';

/// Whether [text] dispatches as a bare-only host command — one whose
/// registry entry advertises no input hint (today `compact` and `export`).
/// The web routes bare commands through a detached execute: the composer
/// is freed immediately and the outcome arrives as a timeline flow node,
/// never a held sending state. Input-hinted commands (`plan`, `goal`,
/// `permission`, `feedback`, and any live-registered one with a hint) stay
/// attached: their submissions settle fast and keep the
/// draft-for-correction semantics. [roster] is the live facts once a pull
/// settled; it defaults to the static fallback.
bool hostCommandIsBare(
  String text, [
  List<HostCommand> roster = kHostCommandNames,
]) {
  final line = hostCommandLineFor(text, roster);
  if (line == null) return false;
  final boundary = line.indexOf(RegExp(r'[\t\n\r ]'));
  final token = boundary == -1 ? line : line.substring(0, boundary);
  final name = token.substring(1);
  for (final command in roster) {
    if (command.name == name) return command.hint == null;
  }
  return false;
}
