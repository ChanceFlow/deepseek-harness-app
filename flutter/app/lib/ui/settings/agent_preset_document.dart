/// `Settings` → Agent presets → one preset's declared composition.
///
/// `agentPresets/read` answers a *view*: the child plugin list the preset
/// declares, rendered as entry-list YAML in the Loader's own dialect (so
/// `!!js` conditions read as declared rather than as expression objects), plus
/// the copy the preset published. Presets are composed on the host — the
/// roster's own note says the client can read and switch them but never
/// manage them — so this page reads and selects the text, and writes nothing.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/agent_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../theme/theme.dart';
import 'settings_backend_scope.dart';
import 'settings_chrome.dart';

class SettingsAgentPresetDocumentPage extends ConsumerStatefulWidget {
  const SettingsAgentPresetDocumentPage({
    required this.agentPreset,
    required this.label,
    super.key,
  });

  /// The preset identity the read names.
  final String agentPreset;

  /// The roster's label for it, so the bar carries a title before the read
  /// lands (the document's own name is the same copy when it publishes one).
  final String label;

  @override
  ConsumerState<SettingsAgentPresetDocumentPage> createState() =>
      _SettingsAgentPresetDocumentPageState();
}

class _SettingsAgentPresetDocumentPageState
    extends ConsumerState<SettingsAgentPresetDocumentPage> {
  AgentPresetDocument? _document;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final backendId = ref.read(settingsBackendScopeProvider);
    if (backendId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final document = await ref
          .read(chatRepositoryProvider(backendId))
          .readAgentPreset(widget.agentPreset);
      if (!mounted) return;
      setState(() {
        _document = document;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final document = _document;
    return SettingsPageScaffold(
      title: document?.name ?? widget.label,
      children: <Widget>[
        SettingsSectionHeading(
          title: l10n.agentPresetDocumentTitle,
          intro: l10n.agentPresetDocumentIntro,
          showTitle: false,
        ),
        SettingsSectionCard(
          children: <Widget>[
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (document == null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.agentPresetDocumentUnavailable,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (document.description case final String description
                        when description.trim().isNotEmpty) ...<Widget>[
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // The declaration is a document: selectable, monospaced
                    // and uncropped. It scrolls sideways rather than wrapping,
                    // because YAML indentation *is* the structure — a wrapped
                    // line loses the cue that says which list an entry belongs
                    // to.
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText(
                        document.content,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: kCodeFontFamily,
                          fontFamilyFallback: kCodeFontFamilyFallback,
                          fontSize: 12.5,
                          height: 1.5,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
