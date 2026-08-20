/// Agent-preset display copy resolution.
///
/// Port of the web `presetDisplayText` rule
/// (reference/deepseek-harness/packages/client/ui-agent-preset/src/client/
/// locales.ts): the four shipped system ids resolve to the web client's
/// English name/description; every other row (user-authored or unknown
/// system id) keeps its own published metadata, falling back to the id.
library;

import 'package:domain/model/agent_preset.dart';

const Map<String, (String, String)> _builtInCopy = <String, (String, String)>{
  'standard': (
    'Standard mode',
    'Full coding agent with file editing, shell, file and web search, '
        'skills, planning, goals, subagents, and workflows.',
  ),
  'code': (
    'Code mode',
    'All Standard mode capabilities, with tools exposed through the Code '
        'Mode SDK so the model can combine multi-step operations in one '
        'TypeScript program.',
  ),
  'minimal': (
    'Minimal mode',
    'Two-tool coding agent with persistent bash and str_replace_editor.',
  ),
  'cordis': (
    'Creator mode',
    'Built for creating custom agent presets, with all Standard mode '
        'capabilities plus runtime inspection, plugin experiments, and '
        'preset-authoring guidance.',
  ),
};

/// Label a surface shows for one preset row.
String agentPresetDisplayName(AgentPresetEntry entry) {
  if (entry.trust == AgentPresetTrust.system) {
    final builtIn = _builtInCopy[entry.id];
    if (builtIn != null) return builtIn.$1;
  }
  return entry.displayName;
}

/// One-sentence description for one preset row; null when nothing was
/// published.
String? agentPresetDisplayDescription(AgentPresetEntry entry) {
  if (entry.trust == AgentPresetTrust.system) {
    final builtIn = _builtInCopy[entry.id];
    if (builtIn != null) return builtIn.$2;
  }
  return entry.description;
}
