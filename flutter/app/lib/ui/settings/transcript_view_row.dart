/// Transcript view row — the Settings → Chat control for the work-details
/// mode, and the sheet carrying its four choices.
///
/// The reference registers one selector into the general settings items
/// (`ui-chat/src/client/apply.ts:156-166`, `TranscriptViewRow.tsx`) whose value
/// is the Host user-settings field `ui-chat.transcriptView`
/// (`chat-settings.ts:6`, `:9`), over the four modes `compact`, `standard`,
/// `detailed` and `verbose` (`:12`). This is that row: the persisted mode in
/// words on the index, the four seats in a sheet, and the labels the pin's own
/// copy gives them (`locale.ts:103-108`, `:296-301`).
///
/// The value is read and written through [TranscriptViewController], the same
/// controller the transcript folds by, so a selection here reaches the open
/// transcript with the tap.
///
/// The generic Settings → Plugins → Plugin settings editor renders every Host
/// namespace unfiltered, so the raw `transcriptView` field can appear there
/// unlabelled. That editor stays a raw reader; this row is the control that
/// governs the transcript.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../chat/transcript_view_mode.dart';
import 'settings_chrome.dart';

/// The Settings → Chat index row: the persisted mode in words, opening the
/// four-seat sheet.
class SettingsTranscriptViewEntryRow extends ConsumerWidget {
  const SettingsTranscriptViewEntryRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final String backendId = ref.watch(activeBackendIdProvider).value ?? '';
    if (backendId.isEmpty) {
      return SettingsNavRow(
        title: l10n.settingsTranscriptViewTitle,
        leading: const Icon(Icons.article_outlined),
        value: l10n.settingsValueUnavailable,
        enabled: false,
        onTap: () {},
      );
    }
    final TranscriptViewController controller = ref.watch(
      transcriptViewControllerProvider(backendId),
    );
    return StreamBuilder<TranscriptViewState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder:
          (BuildContext context, AsyncSnapshot<TranscriptViewState> snapshot) {
            final TranscriptViewState state = snapshot.data ?? controller.state;
            return SettingsNavRow(
              title: l10n.settingsTranscriptViewTitle,
              leading: const Icon(Icons.article_outlined),
              // The field is optional in the Host document: an absent value
              // means the client default is in force, which is still a real
              // answer to render. Only a Host that never answered for the
              // namespace reads as unavailable.
              value: state.exposed
                  ? transcriptViewModeLabel(l10n, state.mode)
                  : l10n.settingsValueUnavailable,
              onTap: () => showSettingsSheet<void>(
                context,
                builder: (BuildContext sheetContext) =>
                    const TranscriptViewChoiceRow(),
              ),
            );
          },
    );
  }
}

/// One mode's display name, from the pin's own labels.
String transcriptViewModeLabel(
  AppLocalizations l10n,
  TranscriptViewMode mode,
) => switch (mode) {
  TranscriptViewMode.compact => l10n.settingsTranscriptViewCompact,
  TranscriptViewMode.standard => l10n.settingsTranscriptViewStandard,
  TranscriptViewMode.detailed => l10n.settingsTranscriptViewDetailed,
  TranscriptViewMode.verbose => l10n.settingsTranscriptViewVerbose,
};

/// The sheet body: the four modes over the persisted value, with the Host's
/// describe/write state stated rather than hidden.
class TranscriptViewChoiceRow extends ConsumerWidget {
  const TranscriptViewChoiceRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final String backendId = ref.watch(activeBackendIdProvider).value ?? '';
    if (backendId.isEmpty) return const SizedBox.shrink();
    final TranscriptViewController controller = ref.watch(
      transcriptViewControllerProvider(backendId),
    );
    return StreamBuilder<TranscriptViewState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder: (BuildContext context, AsyncSnapshot<TranscriptViewState> snap) {
        final TranscriptViewState state = snap.data ?? controller.state;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.settingsTranscriptViewTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.settingsTranscriptViewDescription,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (state.loading && !state.exposed)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else if (!state.exposed) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                l10n.settingsTranscriptViewUnavailable,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (!state.loading)
                TextButton(
                  onPressed: controller.refresh,
                  child: Text(l10n.retry),
                ),
            ] else
              RadioGroup<TranscriptViewMode>(
                groupValue: state.mode,
                onChanged: (TranscriptViewMode? choice) {
                  if (choice == null) return;
                  unawaited(controller.select(choice));
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final TranscriptViewMode mode
                        in TranscriptViewMode.values)
                      RadioListTile<TranscriptViewMode>(
                        contentPadding: EdgeInsets.zero,
                        value: mode,
                        // Every seat is inert while the Host refuses writes or
                        // a save is in flight.
                        enabled: state.writable && !state.saving,
                        title: Text(transcriptViewModeLabel(l10n, mode)),
                      ),
                  ],
                ),
              ),
            if (state.failed)
              Text(
                l10n.settingsTranscriptViewSaveFailed,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
          ],
        );
      },
    );
  }
}
