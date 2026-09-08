/// Special screen for viewing and copying collected application error logs.
library;

import 'dart:io' show Platform;

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config.dart';
import '../../../di/providers.dart';
import '../../theme/theme.dart';

/// Route widget binding [ErrorLogsScreen] to [errorLogsControllerProvider].
class ErrorLogsRoute extends ConsumerWidget {
  const ErrorLogsRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ErrorLogsController controller = ref.watch(
      errorLogsControllerProvider,
    );
    return StreamBuilder<ErrorLogsUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder:
          (BuildContext context, AsyncSnapshot<ErrorLogsUiState> snapshot) {
            final ErrorLogsUiState uiState =
                snapshot.data ?? const ErrorLogsUiState();
            return ErrorLogsScreen(
              uiState: uiState,
              onAction: controller.onAction,
              onCopyAll: controller.copyAllToClipboard,
              onCopyEntry: controller.copyEntryToClipboard,
              onCopySystemInfo: controller.copySystemInfoToClipboard,
            );
          },
    );
  }
}

/// Screen presenting the list of error logs with filters and copy actions.
class ErrorLogsScreen extends StatelessWidget {
  const ErrorLogsScreen({
    required this.uiState,
    required this.onAction,
    this.onCopyAll,
    this.onCopyEntry,
    this.onCopySystemInfo,
    super.key,
  });

  final ErrorLogsUiState uiState;
  final void Function(ErrorLogsAction) onAction;
  final Future<String> Function({bool filteredOnly})? onCopyAll;
  final Future<String> Function(ErrorLogEntry entry)? onCopyEntry;
  final Future<String> Function()? onCopySystemInfo;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<ErrorLogEntry> filtered = uiState.filteredEntries;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.errorLogsTitle),
        actions: <Widget>[
          if (uiState.entries.isNotEmpty) ...<Widget>[
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.errorLogsClear,
              onPressed: () => _confirmClear(context, l10n),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(kShapeChip),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.copy_all, size: 18),
                label: Text(l10n.errorLogsCopyAll),
                onPressed: () => _handleCopyAll(context, l10n),
              ),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (uiState.isLoading)
              LinearProgressIndicator(
                minHeight: 2,
                color: scheme.primary,
                backgroundColor: Colors.transparent,
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: <Widget>[
                  // 1. System & Environment overview card
                  _SystemInfoCard(
                    uiState: uiState,
                    onCopySystemInfo: () =>
                        _handleCopySystemInfo(context, l10n),
                  ),
                  const SizedBox(height: 16),

                  // 2. Search & Filter Bar
                  _FilterAndSearchBar(uiState: uiState, onAction: onAction),
                  const SizedBox(height: 16),

                  // 3. Error list or empty states
                  if (uiState.entries.isEmpty)
                    _EmptyLogsView(l10n: l10n)
                  else if (filtered.isEmpty)
                    _NoSearchResultsView(l10n: l10n)
                  else
                    for (final ErrorLogEntry entry in filtered) ...<Widget>[
                      _ErrorLogCard(
                        entry: entry,
                        isExpanded: uiState.isExpanded(entry.id),
                        onToggleExpand: () =>
                            onAction(ToggleExpandAction(entry.id)),
                        onCopy: () => _handleCopyEntry(context, l10n, entry),
                      ),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleCopyAll(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    await onCopyAll?.call();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.errorLogsCopyAllSuccess),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleCopyEntry(
    BuildContext context,
    AppLocalizations l10n,
    ErrorLogEntry entry,
  ) async {
    await onCopyEntry?.call(entry);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.errorLogsCopyEntrySuccess),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleCopySystemInfo(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    await onCopySystemInfo?.call();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.errorLogsSystemInfoCopied),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _confirmClear(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(l10n.errorLogsClearConfirmTitle),
          content: Text(l10n.errorLogsClearConfirmMessage),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.errorLogsClear),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      onAction(const ClearLogsAction());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errorLogsClearSuccess),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

/// System diagnostics and app version overview card.
class _SystemInfoCard extends StatelessWidget {
  const _SystemInfoCard({
    required this.uiState,
    required this.onCopySystemInfo,
  });

  final ErrorLogsUiState uiState;
  final VoidCallback onCopySystemInfo;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(kShapeCard),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.info_outline, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.errorLogsSystemInfo,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(kShapeChip),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.copy, size: 14),
                label: Text(
                  l10n.errorLogsCopySystemInfo,
                  style: theme.textTheme.labelSmall,
                ),
                onPressed: onCopySystemInfo,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _InfoLine(
            label: 'App',
            value: 'DSH Mobile $kDshAppVersion ($kDshBuildNumber)',
          ),
          const SizedBox(height: 4),
          const _InfoLine(label: 'Commit', value: kDshSourceCommit),
          const SizedBox(height: 4),
          _InfoLine(
            label: 'OS',
            value:
                '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
          ),
          if (uiState.activeBackendUrl case final String url) ...<Widget>[
            const SizedBox(height: 4),
            _InfoLine(label: 'Host', value: url),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              _StatBadge(
                label: '${l10n.errorLogsFilterAll}: ${uiState.totalCount}',
                background: scheme.surfaceContainerHighest,
                foreground: scheme.onSurface,
              ),
              if (uiState.fatalCount > 0)
                _StatBadge(
                  label: '${l10n.errorLogsFilterFatal}: ${uiState.fatalCount}',
                  background: scheme.errorContainer,
                  foreground: scheme.onErrorContainer,
                ),
              if (uiState.errorCount > 0)
                _StatBadge(
                  label: '${l10n.errorLogsFilterError}: ${uiState.errorCount}',
                  background: scheme.errorContainer,
                  foreground: scheme.error,
                ),
              if (uiState.warnCount > 0)
                _StatBadge(
                  label: '${l10n.errorLogsFilterWarn}: ${uiState.warnCount}',
                  background: scheme.surfaceContainerHighest,
                  foreground: scheme.warning,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurface,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(kShapeChip),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Filter chips and search text field.
class _FilterAndSearchBar extends StatelessWidget {
  const _FilterAndSearchBar({required this.uiState, required this.onAction});

  final ErrorLogsUiState uiState;
  final void Function(ErrorLogsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Search bar
        TextField(
          onChanged: (String query) => onAction(SetSearchQueryAction(query)),
          decoration: InputDecoration(
            hintText: l10n.errorLogsSearchHint,
            prefixIcon: const Icon(Icons.search, size: 20),
            isDense: true,
            filled: true,
            fillColor: scheme.surfaceContainer,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kShapeCard),
              borderSide: BorderSide(color: scheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kShapeCard),
              borderSide: BorderSide(color: scheme.outlineVariant),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              _LevelFilterChip(
                label: l10n.errorLogsFilterAll,
                count: uiState.totalCount,
                selected: uiState.filterLevel == null,
                onSelected: () => onAction(const SetFilterLevelAction(null)),
              ),
              const SizedBox(width: 8),
              _LevelFilterChip(
                label: l10n.errorLogsFilterFatal,
                count: uiState.fatalCount,
                selected: uiState.filterLevel == ErrorLogLevel.fatal,
                onSelected: () =>
                    onAction(const SetFilterLevelAction(ErrorLogLevel.fatal)),
              ),
              const SizedBox(width: 8),
              _LevelFilterChip(
                label: l10n.errorLogsFilterError,
                count: uiState.errorCount,
                selected: uiState.filterLevel == ErrorLogLevel.error,
                onSelected: () =>
                    onAction(const SetFilterLevelAction(ErrorLogLevel.error)),
              ),
              const SizedBox(width: 8),
              _LevelFilterChip(
                label: l10n.errorLogsFilterWarn,
                count: uiState.warnCount,
                selected: uiState.filterLevel == ErrorLogLevel.warning,
                onSelected: () =>
                    onAction(const SetFilterLevelAction(ErrorLogLevel.warning)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LevelFilterChip extends StatelessWidget {
  const _LevelFilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text('$label ($count)'),
      selected: selected,
      onSelected: (_) => onSelected(),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kShapeChip),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// A card displaying a single error log entry.
class _ErrorLogCard extends StatelessWidget {
  const _ErrorLogCard({
    required this.entry,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onCopy,
  });

  final ErrorLogEntry entry;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context)!;

    final (Color badgeBg, Color badgeFg) = switch (entry.level) {
      ErrorLogLevel.fatal => (scheme.errorContainer, scheme.onErrorContainer),
      ErrorLogLevel.error => (scheme.errorContainer, scheme.error),
      ErrorLogLevel.warning => (scheme.surfaceContainerHighest, scheme.warning),
      ErrorLogLevel.info => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(kShapeCard),
        border: Border.all(
          color: entry.level == ErrorLogLevel.fatal
              ? scheme.error
              : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onToggleExpand,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Header row: Level chip, timestamp, copy button, expand arrow
                Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(kShapeChip),
                      ),
                      child: Text(
                        entry.level.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: badgeFg,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.formattedTimestamp,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: l10n.errorLogsCopyEntry,
                      visualDensity: VisualDensity.compact,
                      onPressed: onCopy,
                    ),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Error type / classifier
                Text(
                  entry.type,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: entry.level == ErrorLogLevel.fatal
                        ? scheme.error
                        : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),

                // Message summary
                Text(
                  entry.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                  ),
                  maxLines: isExpanded ? null : 3,
                  overflow: isExpanded ? null : TextOverflow.ellipsis,
                ),

                // Expanded details: Context, Breadcrumbs, Stack Trace
                if (isExpanded) ...<Widget>[
                  if (entry.context != null &&
                      entry.context!.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Divider(height: 1, color: scheme.outlineVariant),
                    const SizedBox(height: 8),
                    Text(
                      l10n.errorLogsContext,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final MapEntry<String, Object?> item
                        in entry.context!.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '${item.key}: ${item.value}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],

                  if (entry.breadcrumbs.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Divider(height: 1, color: scheme.outlineVariant),
                    const SizedBox(height: 8),
                    Text(
                      l10n.errorLogsBreadcrumbs,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(kShapeChip),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          for (final String line in entry.breadcrumbs)
                            Text(
                              line,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontFamily: 'monospace',
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],

                  if (entry.stackTrace != null &&
                      entry.stackTrace!.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Divider(height: 1, color: scheme.outlineVariant),
                    const SizedBox(height: 8),
                    Text(
                      l10n.errorLogsStackTrace,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(kShapeChip),
                      ),
                      child: SelectableText(
                        entry.stackTrace!.trim(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty state when no error logs exist at all.
class _EmptyLogsView extends StatelessWidget {
  const _EmptyLogsView({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.check_circle_outline, size: 56, color: scheme.success),
            const SizedBox(height: 16),
            Text(
              l10n.errorLogsEmptyTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                l10n.errorLogsEmptySubtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty state when filter/search yielded no matches.
class _NoSearchResultsView extends StatelessWidget {
  const _NoSearchResultsView({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.search_off, size: 44, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              l10n.errorLogsNoSearchResults,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
