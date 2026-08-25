/// Agent-preset display copy resolution.
///
/// Port of the web `presetDisplayText` rule
/// (reference/deepseek-harness/packages/client/ui-agent-preset/src/client/
/// locales.ts): the four shipped system ids resolve to localized
/// name/description; every other row (user-authored or unknown
/// system id) keeps its own published metadata, falling back to the id.
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
  if (entry.trust == AgentPresetTrust.system) {
    final builtIn = _builtInCopy(l10n)[entry.id];
    if (builtIn != null) return builtIn.$1;
  }
  return entry.displayName;
}

/// One-sentence description for one preset row; null when nothing was
/// published.
String? agentPresetDisplayDescription(
  AgentPresetEntry entry,
  AppLocalizations l10n,
) {
  if (entry.trust == AgentPresetTrust.system) {
    final builtIn = _builtInCopy(l10n)[entry.id];
    if (builtIn != null) return builtIn.$2;
  }
  return entry.description;
}
