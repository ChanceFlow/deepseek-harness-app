/// The on-device error log viewer: the collector's entries, their details and
/// the recent breadcrumbs, readable and copyable without adb.
///
/// The screen renders the collector's stream over its snapshot, so an entry
/// captured while it is open appears without leaving the page. Every color
/// comes from the [ColorScheme] roles and every radius from the named scale in
/// `theme/theme.dart`; the only data it owns is which filter seat is selected
/// and which entries are expanded.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../theme/theme.dart';
import 'error_log_collector.dart';
import 'error_log_entry.dart';

/// The level seats the filter bar offers. [all] is the unfiltered list.
enum _LevelFilter { all, fatal, error, warning }

/// The viewer screen behind the settings page's error-log row.
class ErrorLogViewerScreen extends StatefulWidget {
  const ErrorLogViewerScreen({this.collector, super.key});

  /// The collector this screen reads. Null reads
  /// [ErrorLogCollector.instance]; a test injects its own so the singleton
  /// keeps whatever the production app captured.
  final ErrorLogCollector? collector;

  @override
  State<ErrorLogViewerScreen> createState() => _ErrorLogViewerScreenState();
}

class _ErrorLogViewerScreenState extends State<ErrorLogViewerScreen> {
  ErrorLogCollector get _collector =>
      widget.collector ?? ErrorLogCollector.instance;

  /// The selected filter seat; [all] shows every level.
  _LevelFilter _filter = _LevelFilter.all;

  /// The ids of the entries whose details are open.
  final Set<String> _expanded = <String>{};

  List<ErrorLogEntry> _filtered(List<ErrorLogEntry> entries) {
    if (_filter == _LevelFilter.all) return entries;
    final ErrorLogLevel level = switch (_filter) {
      _LevelFilter.fatal => ErrorLogLevel.fatal,
      _LevelFilter.error => ErrorLogLevel.error,
      _LevelFilter.warning => ErrorLogLevel.warning,
      _LevelFilter.all => ErrorLogLevel.info,
    };
    return <ErrorLogEntry>[
      for (final ErrorLogEntry entry in entries)
        if (entry.level == level) entry,
    ];
  }

  Future<void> _copyAll(AppLocalizations l10n) async {
    await Clipboard.setData(
      ClipboardData(text: _collector.formatExportReport()),
    );
    if (!mounted) return;
    _toast(l10n.errorLogsCopyAllSuccess);
  }

  Future<void> _copyEntry(AppLocalizations l10n, ErrorLogEntry entry) async {
    await Clipboard.setData(ClipboardData(text: entry.toMarkdown()));
    if (!mounted) return;
    _toast(l10n.errorLogsCopyEntrySuccess);
  }

  Future<void> _copySystemInfo(AppLocalizations l10n) async {
    await Clipboard.setData(ClipboardData(text: _systemInfoText()));
    if (!mounted) return;
    _toast(l10n.errorLogsSystemInfoCopied);
  }

  /// The build facts the footer shows and copies.
  String _systemInfoText() => <String>[
    'App: $kDshAppVersion ($kDshBuildNumber)',
    'Commit: $kDshSourceCommit',
    'Repo: $kDshSourceRepo',
    'Base URL: $kDshBaseUrl',
    'OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
  ].join('\n');

  Future<void> _confirmClear(AppLocalizations l10n) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
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
      ),
    );
    if (confirmed != true || !mounted) return;
    _collector.clear();
    _toast(l10n.errorLogsClearSuccess);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.bgBase,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _ViewerHeader(title: l10n.errorLogsTitle),
            Expanded(
              child: StreamBuilder<List<ErrorLogEntry>>(
                stream: _collector.stream,
                initialData: _collector.entries,
                builder:
                    (
                      BuildContext context,
                      AsyncSnapshot<List<ErrorLogEntry>> snapshot,
                    ) {
                      final List<ErrorLogEntry> entries =
                          snapshot.data ?? _collector.entries;
                      final List<ErrorLogEntry> visible = _filtered(entries);
                      final List<String> breadcrumbs = _collector.breadcrumbs;
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        children: <Widget>[
                          _SummaryBar(
                            count: entries.length,
                            onCopyAll: entries.isEmpty
                                ? null
                                : () => unawaited(_copyAll(l10n)),
                            onClear: entries.isEmpty
                                ? null
                                : () => unawaited(_confirmClear(l10n)),
                          ),
                          const SizedBox(height: 10),
                          _FilterBar(
                            selected: _filter,
                            onSelected: (_LevelFilter filter) {
                              setState(() => _filter = filter);
                            },
                          ),
                          if (breadcrumbs.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 16),
                            _BreadcrumbsSection(lines: breadcrumbs),
                          ],
                          const SizedBox(height: 16),
                          if (entries.isEmpty)
                            _EmptyState(l10n: l10n)
                          else if (visible.isEmpty)
                            _NoMatches(l10n: l10n)
                          else
                            for (final ErrorLogEntry entry in visible)
                              _EntryCard(
                                entry: entry,
                                expanded: _expanded.contains(entry.id),
                                onToggle: () {
                                  setState(() {
                                    if (!_expanded.remove(entry.id)) {
                                      _expanded.add(entry.id);
                                    }
                                  });
                                },
                                onCopy: () =>
                                    unawaited(_copyEntry(l10n, entry)),
                              ),
                          const SizedBox(height: 4),
                          _SystemInfoSection(
                            info: _systemInfoText(),
                            onCopy: () => unawaited(_copySystemInfo(l10n)),
                          ),
                        ],
                      );
                    },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The viewer's header: the settings page's own header shape.
class _ViewerHeader extends StatelessWidget {
  const _ViewerHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      height: 52,
      padding: const EdgeInsets.only(left: 4, right: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(width: 0.5, color: scheme.borderL2)),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DshType.l20.style(color: scheme.labelPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The count badge and the two collection-wide actions.
class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.count,
    required this.onCopyAll,
    required this.onClear,
  });

  final int count;
  final VoidCallback? onCopyAll;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: scheme.bgLayer2,
            borderRadius: BorderRadius.circular(kShapePill),
            border: Border.all(width: 0.5, color: scheme.borderL4),
          ),
          child: Text(
            l10n.errorLogsCountBadge(count),
            style: DshType.xxsStrong12.style(color: scheme.labelSecondary),
          ),
        ),
        const Spacer(),
        if (onCopyAll != null)
          TextButton.icon(
            onPressed: onCopyAll,
            icon: const Icon(Icons.copy_all, size: 16),
            label: Text(l10n.errorLogsCopyAll),
          ),
        if (onClear != null)
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text(l10n.errorLogsClear),
          ),
      ],
    );
  }
}

/// The level filter seats: all, fatal, error, warn.
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelected});

  final _LevelFilter selected;
  final ValueChanged<_LevelFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: <Widget>[
        _FilterSeat(
          label: l10n.errorLogsFilterAll,
          selected: selected == _LevelFilter.all,
          onTap: () => onSelected(_LevelFilter.all),
        ),
        _FilterSeat(
          label: l10n.errorLogsFilterFatal,
          selected: selected == _LevelFilter.fatal,
          onTap: () => onSelected(_LevelFilter.fatal),
        ),
        _FilterSeat(
          label: l10n.errorLogsFilterError,
          selected: selected == _LevelFilter.error,
          onTap: () => onSelected(_LevelFilter.error),
        ),
        _FilterSeat(
          label: l10n.errorLogsFilterWarn,
          selected: selected == _LevelFilter.warning,
          onTap: () => onSelected(_LevelFilter.warning),
        ),
      ],
    );
  }
}

/// One filter seat on the pin's pill radius.
class _FilterSeat extends StatelessWidget {
  const _FilterSeat({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kShapePill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? scheme.stateBusinessTertiary : scheme.bgLayer2,
            borderRadius: BorderRadius.circular(kShapePill),
            border: Border.all(
              width: 0.5,
              color: selected ? scheme.stateBusinessPrimary : scheme.borderL4,
            ),
          ),
          child: Text(
            label,
            style: DshType.xs13.style(
              color: selected ? scheme.labelPrimary : scheme.labelSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The collector's whole breadcrumb ring, newest last.
class _BreadcrumbsSection extends StatelessWidget {
  const _BreadcrumbsSection({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return _Panel(
      children: <Widget>[
        Text(
          l10n.errorLogsBreadcrumbs,
          style: DshType.xsStrong13.style(color: scheme.labelSecondary),
        ),
        const SizedBox(height: 6),
        for (final String line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(line, style: _codeStyle(scheme, scheme.labelTertiary)),
          ),
      ],
    );
  }
}

/// The build facts, as the old viewer's first card carried them.
class _SystemInfoSection extends StatelessWidget {
  const _SystemInfoSection({required this.info, required this.onCopy});

  final String info;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: _Panel(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.errorLogsSystemInfo,
                  style: DshType.xsStrong13.style(color: scheme.labelSecondary),
                ),
              ),
              TextButton(
                onPressed: onCopy,
                child: Text(l10n.errorLogsCopySystemInfo),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(info, style: _codeStyle(scheme, scheme.labelTertiary)),
        ],
      ),
    );
  }
}

/// One captured entry: level, time, type, message, and its details when open.
class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.expanded,
    required this.onToggle,
    required this.onCopy,
  });

  final ErrorLogEntry entry;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color ink = _levelInk(scheme, entry.level);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.bgLayer2,
        borderRadius: BorderRadius.circular(kRadiusMd),
        border: Border.all(width: 0.5, color: scheme.borderL4),
      ),
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    _levelLabel(l10n, entry.level),
                    style: DshType.xxsStrong12.style(color: ink),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.formattedTimestamp,
                      style: _codeStyle(scheme, scheme.labelTertiary),
                    ),
                  ),
                  IconButton(
                    onPressed: onCopy,
                    tooltip: l10n.errorLogsCopyEntry,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.copy, size: 18),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: scheme.labelTertiary,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.type,
                      style: DshType.sStrong14.style(
                        color: scheme.labelPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.message,
                      maxLines: expanded ? null : 3,
                      overflow: expanded ? null : TextOverflow.ellipsis,
                      style: DshType.xs13.style(color: scheme.labelSecondary),
                    ),
                    if (expanded) ..._details(l10n, scheme),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _details(AppLocalizations l10n, ColorScheme scheme) {
    final Map<String, Object?>? context = entry.context;
    final List<String> breadcrumbs = entry.breadcrumbs;
    final String? stackTrace = entry.stackTrace;
    return <Widget>[
      if (context != null && context.isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        const _Hairline(),
        const SizedBox(height: 8),
        Text(
          l10n.errorLogsContext,
          style: DshType.xxsStrong12.style(color: scheme.labelSecondary),
        ),
        const SizedBox(height: 2),
        for (final MapEntry<String, Object?> item in context.entries)
          Text(
            '${item.key}: ${item.value}',
            style: _codeStyle(scheme, scheme.labelTertiary),
          ),
      ],
      if (breadcrumbs.isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        const _Hairline(),
        const SizedBox(height: 8),
        Text(
          l10n.errorLogsBreadcrumbs,
          style: DshType.xxsStrong12.style(color: scheme.labelSecondary),
        ),
        const SizedBox(height: 2),
        for (final String line in breadcrumbs)
          Text(line, style: _codeStyle(scheme, scheme.labelTertiary)),
      ],
      if (stackTrace != null && stackTrace.trim().isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        const _Hairline(),
        const SizedBox(height: 8),
        Text(
          l10n.errorLogsStackTrace,
          style: DshType.xxsStrong12.style(color: scheme.labelSecondary),
        ),
        const SizedBox(height: 2),
        SelectableText(
          stackTrace.trim(),
          style: _codeStyle(scheme, scheme.labelTertiary),
        ),
      ],
    ];
  }
}

/// The empty state when nothing was captured at all.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: <Widget>[
          Icon(Icons.check_circle_outline, size: 56, color: scheme.success),
          const SizedBox(height: 16),
          Text(
            l10n.errorLogsEmptyTitle,
            textAlign: TextAlign.center,
            style: DshType.m18.style(color: scheme.labelPrimary),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              l10n.errorLogsEmptySubtitle,
              textAlign: TextAlign.center,
              style: DshType.xs13.style(color: scheme.labelTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The empty state when the selected level has no entry.
class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: <Widget>[
          Icon(Icons.search_off, size: 44, color: scheme.labelTertiary),
          const SizedBox(height: 12),
          Text(
            l10n.errorLogsNoSearchResults,
            textAlign: TextAlign.center,
            style: DshType.xs13.style(color: scheme.labelTertiary),
          ),
        ],
      ),
    );
  }
}

/// A raised panel on the settings card's surface: one border, one radius.
class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: scheme.bgLayer2,
        borderRadius: BorderRadius.circular(kRadiusMd),
        border: Border.all(width: 0.5, color: scheme.borderL4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// The hairline the details sections open with.
class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Divider(height: 1, thickness: 0.5, color: scheme.borderL2);
  }
}

/// The entry's level as the filter bar names it.
String _levelLabel(AppLocalizations l10n, ErrorLogLevel level) =>
    switch (level) {
      ErrorLogLevel.fatal => l10n.errorLogsFilterFatal,
      ErrorLogLevel.error => l10n.errorLogsFilterError,
      ErrorLogLevel.warning => l10n.errorLogsFilterWarn,
      ErrorLogLevel.info => level.label,
    };

/// The level's ink: errors share the failure mark, warnings the warn tone.
Color _levelInk(ColorScheme scheme, ErrorLogLevel level) => switch (level) {
  ErrorLogLevel.fatal || ErrorLogLevel.error => scheme.stateErrorPrimary,
  ErrorLogLevel.warning => scheme.warning,
  ErrorLogLevel.info => scheme.labelTertiary,
};

/// The code face at the smallest type step.
TextStyle _codeStyle(ColorScheme scheme, Color color) => DshType.xxs12
    .style(color: color)
    .copyWith(
      fontFamily: kCodeFontFamily,
      fontFamilyFallback: kCodeFontFamilyFallback,
    );
