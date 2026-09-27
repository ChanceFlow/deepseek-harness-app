/// Agent-preset display copy resolution.
///
/// Port of the web `presetDisplayText` rule
/// (reference/deepseek-harness/packages/client/ui-agent-preset/src/client/
/// locales.ts): a row's own published metadata wins, and a row that publishes
/// none falls back to the localized copy for a shipped id, then to its id.
///
/// The rule used to be keyed on the row's trust — shipped ids resolved to
/// localized copy and every other row kept its published metadata. 0.1.7
/// removed the trust signal from the roster, so published metadata is now the
/// first choice everywhere and the localized copy is the fallback that keeps a
/// nameless shipped row readable.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/agent_preset.dart';

/// Built-in system preset copy, localized.
Map<String, (String, String)> _builtInCopy(AppLocalizations l10n) =>
    <String, (String, String)>{
      'standard': (l10n.presetStandardName, l10n.presetStandardDescription),
      'code': (l10n.presetCodeName, l10n.presetCodeDescription),
      'minimal': (l10n.presetMinimalName, l10n.presetMinimalDescription),
      'cordis': (l10n.presetCordisName, l10n.presetCordisDescription),
    };

/// Label a surface shows for one preset row.
String agentPresetDisplayName(AgentPresetEntry entry, AppLocalizations l10n) {
  final published = entry.name;
  if (published != null) return published;
  return _builtInCopy(l10n)[entry.id]?.$1 ?? entry.id;
}

/// One-sentence description for one preset row; null when nothing was
/// published and the id is not a known shipped one.
String? agentPresetDisplayDescription(
  AgentPresetEntry entry,
  AppLocalizations l10n,
) {
  final published = entry.description;
  if (published != null) return published;
  return _builtInCopy(l10n)[entry.id]?.$2;
}
