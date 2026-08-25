/// Screen for downloading and managing on-device ASR speech recognition models.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:asr/asr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../di/providers.dart';

/// Route widget wrapping [AsrModelsScreen] with the Riverpod stream.
class AsrModelsRoute extends ConsumerWidget {
  const AsrModelsRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsrModelsController controller =
        ref.watch(asrModelsControllerProvider);
    return StreamBuilder<AsrModelsUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder: (
        BuildContext context,
        AsyncSnapshot<AsrModelsUiState> snapshot,
      ) {
        final AsrModelsUiState uiState =
            snapshot.data ?? const AsrModelsUiState();
        return AsrModelsScreen(
          uiState: uiState,
          onAction: controller.onAction,
        );
      },
    );
  }
}

/// Screen presenting the ASR model catalog, source switchers, and controls.
class AsrModelsScreen extends StatelessWidget {
  const AsrModelsScreen({
    super.key,
    required this.uiState,
    required this.onAction,
  });

  final AsrModelsUiState uiState;
  final void Function(AsrModelsAction) onAction;

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const List<String> units = <String>['B', 'KB', 'MB', 'GB'];
    int unitIndex = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.asrModelsTitle),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => onAction(const RefreshAsrStateAction()),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            // Intro banner
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                l10n.asrModelsDescription,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),

            // Error banner if any
            if (uiState.errorMessage case final String error) ...<Widget>[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.error_outline, color: scheme.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        error,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: l10n.dismiss,
                      color: scheme.onErrorContainer,
                      onPressed: () => onAction(const DismissAsrErrorAction()),
                    ),
                  ],
                ),
              ),
            ],

            // Preferences Card: Default source + Cellular toggle
            Card(
              elevation: 0,
              color: scheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.asrDefaultSource,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.asrDefaultSourceDesc,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<ModelSource>(
                      segments: const <ButtonSegment<ModelSource>>[
                        ButtonSegment<ModelSource>(
                          value: ModelSource.hfMirror,
                          label: Text('HF Mirror (国内)'),
                          icon: Icon(Icons.hub_outlined),
                        ),
                        ButtonSegment<ModelSource>(
                          value: ModelSource.huggingFace,
                          label: Text('Hugging Face'),
                          icon: Icon(Icons.cloud_outlined),
                        ),
                      ],
                      selected: <ModelSource>{uiState.defaultSource},
                      onSelectionChanged: (Set<ModelSource> selected) {
                        if (selected.isNotEmpty) {
                          onAction(SetDefaultSourceAction(selected.first));
                        }
                      },
                    ),
                    const Divider(height: 24),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        l10n.asrAllowCellular,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        l10n.asrAllowCellularDesc,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      value: uiState.allowCellular,
                      onChanged: (bool value) {
                        onAction(SetAllowCellularAction(value));
                      },
                    ),
                    if (uiState.installedCount > 0) ...<Widget>[
                      const Divider(height: 24),
                      Text(
                        l10n.asrActiveModel,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.asrActiveModelDesc,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: uiState.activeModelId ??
                            uiState.models
                                .where((AsrModelCardState m) => m.isDownloaded)
                                .firstOrNull
                                ?.info
                                .id,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        items: uiState.models
                            .where((AsrModelCardState m) => m.isDownloaded)
                            .map((AsrModelCardState m) => DropdownMenuItem<String>(
                                  value: m.info.id,
                                  child: Text(m.info.name),
                                ))
                            .toList(),
                        onChanged: (String? modelId) {
                          if (modelId != null) {
                            onAction(SetActiveModelAction(modelId));
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Section Heading
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  l10n.settingsSectionAsr,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  l10n.asrInstalledCount(uiState.installedCount, uiState.totalCount),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Model Cards
            for (final AsrModelCardState modelState in uiState.models) ...<Widget>[
              _ModelCard(
                cardState: modelState,
                defaultSource: uiState.defaultSource,
                formatBytes: _formatBytes,
                onAction: onAction,
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.cardState,
    required this.defaultSource,
    required this.formatBytes,
    required this.onAction,
  });

  final AsrModelCardState cardState;
  final ModelSource defaultSource;
  final String Function(int) formatBytes;
  final void Function(AsrModelsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final AsrModelInfo info = cardState.info;
    final ModelRegistryEntry entry = cardState.entry;

    final String locale = Localizations.localeOf(context).languageCode;
    final String description =
        locale == 'zh' ? info.descriptionZh : info.descriptionEn;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Row 1: Model Title + Status Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        info.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: <Widget>[
                          _Chip(
                            label: info.languages,
                            icon: Icons.translate,
                          ),
                          _Chip(
                            label: info.license,
                            icon: Icons.gavel_outlined,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _StatusBadge(status: cardState.status),
              ],
            ),
            const SizedBox(height: 12),

            // Description
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),

            // Metadata row: Repo + Size
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.folder_outlined, size: 14, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          info.repoFor(entry.source),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        l10n.asrSourceLabel(entry.source.label),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        cardState.isDownloaded && cardState.diskUsageBytes != null
                            ? l10n.asrDiskUsage(formatBytes(cardState.diskUsageBytes!))
                            : formatBytes(info.estimatedSizeBytes),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Progress bar if downloading
            if (cardState.isDownloading) ...<Widget>[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: cardState.progress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    '${(cardState.progress * 100).toStringAsFixed(1)}% (${formatBytes(entry.downloadedBytes)} / ${formatBytes(entry.totalBytes)})',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (cardState.speedBytesPerSecond > 0)
                    Text(
                      l10n.asrSpeedLabel(formatBytes(cardState.speedBytesPerSecond.round())),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],

            // Error notice if failed
            if (cardState.isFailed && cardState.errorMessage != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                cardState.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                  fontSize: 11,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                if (cardState.isDownloading) ...<Widget>[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.close, size: 16),
                    label: Text(l10n.asrCancelButton),
                    onPressed: () => onAction(CancelDownloadAction(info.id)),
                  ),
                ] else if (cardState.isDownloaded) ...<Widget>[
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: scheme.error),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: Text(l10n.asrDeleteButton),
                    onPressed: () => _confirmDelete(context, info),
                  ),
                ] else if (cardState.isFailed) ...<Widget>[
                  // Retry with alternate source button
                  OutlinedButton(
                    onPressed: () {
                      final ModelSource alternate =
                          entry.source == ModelSource.hfMirror
                              ? ModelSource.huggingFace
                              : ModelSource.hfMirror;
                      onAction(RetryWithSourceAction(info.id, alternate));
                    },
                    child: Text(
                      l10n.asrSwitchSourceRetry(
                        entry.source == ModelSource.hfMirror
                            ? ModelSource.huggingFace.label
                            : ModelSource.hfMirror.label,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(l10n.asrRetryButton),
                    onPressed: () => onAction(
                      StartDownloadAction(info.id, sourceOverride: entry.source),
                    ),
                  ),
                ] else ...<Widget>[
                  // Idle or canceled: Download button
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.download, size: 16),
                    label: Text(l10n.asrDownloadButton),
                    onPressed: () => onAction(StartDownloadAction(info.id, sourceOverride: defaultSource)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, AsrModelInfo info) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(l10n.asrDeleteConfirmTitle),
        content: Text(l10n.asrDeleteConfirmBody(info.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () {
              Navigator.of(ctx).pop();
              onAction(DeleteModelAction(info.id));
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 10, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final AsrModelStatus status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    final (Color bg, Color fg, String text, IconData icon) = switch (status) {
      AsrModelStatus.idle => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          l10n.asrModelStatusIdle,
          Icons.cloud_download_outlined,
        ),
      AsrModelStatus.downloading => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          l10n.asrModelStatusDownloading,
          Icons.sync,
        ),
      AsrModelStatus.downloaded => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
          l10n.asrModelStatusDownloaded,
          Icons.check_circle_outline,
        ),
      AsrModelStatus.failed => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          l10n.asrModelStatusFailed,
          Icons.error_outline,
        ),
      AsrModelStatus.canceled => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          l10n.asrModelStatusCanceled,
          Icons.cancel_outlined,
        ),
      AsrModelStatus.deleting => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          'Deleting',
          Icons.hourglass_empty,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
