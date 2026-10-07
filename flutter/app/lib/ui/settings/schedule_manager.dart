/// Automation tasks for Settings: the host's scheduled reminders across every
/// session, their delivery history, and the compare-and-update they accept.
///
/// Port of the reference `ui-schedule` page
/// (`reference/deepseek-harness/packages/client/ui-schedule/src/client/
/// TaskManagerPage.tsx`). Three host facts drive the shape of this surface:
///
///  - the `schedule` service ships **disabled** in the shipped web-app bundle,
///    so a call to it answers `gateway/invocation-unavailable` on a stock
///    host. The page therefore probes and, when the probe fails, says the
///    feature is absent instead of offering broken controls;
///  - `schedule/create` is **not** a Remote: a reminder is created by the
///    model's own tool, so this surface has no create form (neither has the
///    reference's page, whose New action starts a session);
///  - every mutation is a compare-and-update against the record the caller
///    observed, so a stale edit answers `schedule_conflict` rather than
///    overwriting someone else's change.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/schedule.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../shared/state_dot.dart';
import '../state_stream.dart';
import '../theme/theme.dart';
import 'settings_backend_scope.dart';
import 'settings_chrome.dart';

/// The status filter row: all, enabled, or ended.
enum ScheduleFilter { all, enabled, inactive }

/// How many saved deliveries one page asks for.
const int kScheduleHistoryPageSize = 20;

/// The page's state.
final class ScheduleManagerUiState {
  const ScheduleManagerUiState({
    this.isLoading = false,
    this.failed = false,
    this.unavailable = false,
    this.entries = const <ScheduleCatalogEntry>[],
    this.query = '',
    this.filter = ScheduleFilter.all,
  });

  final bool isLoading;
  final bool failed;

  /// The host serves no `schedule` service: every one of these methods answers
  /// `gateway/invocation-unavailable`.
  final bool unavailable;

  final List<ScheduleCatalogEntry> entries;
  final String query;
  final ScheduleFilter filter;

  /// The filtered, target-ordered board: overdue first, then the soonest.
  List<ScheduleCatalogEntry> get visible {
    final normalized = query.trim().toLowerCase();
    final rows = entries.where((entry) {
      final matchesFilter = switch (filter) {
        ScheduleFilter.all => true,
        ScheduleFilter.enabled => entry.status == ScheduleStatus.active,
        ScheduleFilter.inactive => entry.status == ScheduleStatus.inactive,
      };
      if (!matchesFilter) return false;
      if (normalized.isEmpty) return true;
      // The reference searches the stored name, the instruction, and the
      // internal session id — never a resolved session title.
      return entry.record.title.toLowerCase().contains(normalized) ||
          entry.record.prompt.toLowerCase().contains(normalized) ||
          entry.sessionId.toLowerCase().contains(normalized);
    }).toList();
    rows.sort((a, b) {
      final aTarget = a.record.scheduledAt;
      final bTarget = b.record.scheduledAt;
      final byTarget = aTarget.compareTo(bTarget);
      return byTarget != 0 ? byTarget : a.record.id.compareTo(b.record.id);
    });
    return rows;
  }
}

/// One task's saved deliveries.
final class ScheduleHistoryUiState {
  const ScheduleHistoryUiState({
    this.isLoading = false,
    this.failed = false,
    this.page,
    this.code,
  });

  final bool isLoading;
  final bool failed;
  final ScheduleHistoryPage? page;

  /// A non-mutating miss (`schedule_not_found` /
  /// `delivery_cursor_not_found`).
  final String? code;
}

/// One controller per backend, disposed with the Settings surface.
class ScheduleManagerController {
  ScheduleManagerController(this._repository) {
    unawaited(_refreshNow());
  }

  final ChatRepository _repository;
  final AppStateStream<ScheduleManagerUiState> _state =
      AppStateStream<ScheduleManagerUiState>(const ScheduleManagerUiState());
  final AppStateStream<ScheduleHistoryUiState> _history =
      AppStateStream<ScheduleHistoryUiState>(const ScheduleHistoryUiState());

  bool _isLoading = false;
  bool _failed = false;
  bool _unavailable = false;
  List<ScheduleCatalogEntry> _entries = const <ScheduleCatalogEntry>[];
  String _query = '';
  ScheduleFilter _filter = ScheduleFilter.all;

  ScheduleManagerUiState get state => _state.value;
  Stream<ScheduleManagerUiState> get uiState => _state.stream;
  Stream<ScheduleHistoryUiState> get history => _history.stream;

  void search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized == _query) return;
    _query = normalized;
    _publish();
  }

  void setFilter(ScheduleFilter filter) {
    if (_filter == filter) return;
    _filter = filter;
    _publish();
  }

  void refresh() => unawaited(_refreshNow());

  Future<void> _refreshNow() async {
    _isLoading = true;
    _publish();
    try {
      final entries = await _repository.scheduleCatalog();
      _entries = entries;
      _unavailable = false;
      _failed = false;
    } on DshBusinessException catch (error, stackTrace) {
      // A host that patches the schedule row out has no service exporting
      // these methods, which is the one failure that means "absent" rather
      // than "broken".
      _unavailable = error.code == 'gateway/invocation-unavailable';
      _failed = !_unavailable;
      _entries = const <ScheduleCatalogEntry>[];
      if (!_unavailable) {
        ErrorLogCollector.instance.captureError(
          error,
          stackTrace: stackTrace,
          context: const <String, Object?>{
            'controller': 'ScheduleManagerController',
            'action': 'catalog',
          },
        );
      }
    } catch (error, stackTrace) {
      _failed = true;
      _unavailable = false;
      _entries = const <ScheduleCatalogEntry>[];
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: const <String, Object?>{
          'controller': 'ScheduleManagerController',
          'action': 'catalog',
        },
      );
    } finally {
      _isLoading = false;
      _publish();
    }
  }

  /// Reads one task's first page of deliveries.
  Future<void> loadHistory(ScheduleCatalogEntry entry) async {
    _history.value = const ScheduleHistoryUiState(isLoading: true);
    try {
      final result = await _repository.scheduleHistory(
        sessionId: entry.sessionId,
        id: entry.record.id,
        limit: kScheduleHistoryPageSize,
      );
      _history.value = switch (result) {
        ScheduleHistoryPage() => ScheduleHistoryUiState(page: result),
        ScheduleHistoryMiss(:final code) => ScheduleHistoryUiState(code: code),
      };
    } catch (error, stackTrace) {
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: const <String, Object?>{
          'controller': 'ScheduleManagerController',
          'action': 'history',
        },
      );
      _history.value = const ScheduleHistoryUiState(failed: true);
    }
  }

  /// Loads the next page, keyed by the previous page's oldest message id.
  Future<void> loadOlderHistory(ScheduleCatalogEntry entry) async {
    final page = _history.value.page;
    final before = page?.nextBefore;
    if (page == null || before == null) return;
    _history.value = ScheduleHistoryUiState(page: page, isLoading: true);
    try {
      final result = await _repository.scheduleHistory(
        sessionId: entry.sessionId,
        id: entry.record.id,
        limit: kScheduleHistoryPageSize,
        before: before,
      );
      if (result is! ScheduleHistoryPage) {
        _history.value = ScheduleHistoryUiState(
          code: (result as ScheduleHistoryMiss).code,
        );
        return;
      }
      // Pages append, deduplicated by message id: an occurrence can be
      // re-read when a delivery lands between two requests.
      final seen = <String>{};
      final merged = <ScheduleDeliveryRecord>[];
      for (final record in <ScheduleDeliveryRecord>[
        ...page.records,
        ...result.records,
      ]) {
        if (seen.add(record.messageId)) merged.add(record);
      }
      _history.value = ScheduleHistoryUiState(
        page: ScheduleHistoryPage(
          id: result.id,
          records: merged,
          earlierRecordsUnavailable: result.earlierRecordsUnavailable,
          earlierRecordsPruned: result.earlierRecordsPruned,
          retention: result.retention,
          nextBefore: result.nextBefore,
        ),
      );
    } catch (error, stackTrace) {
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: const <String, Object?>{
          'controller': 'ScheduleManagerController',
          'action': 'historyOlder',
        },
      );
      _history.value = ScheduleHistoryUiState(page: page, failed: true);
    }
  }

  /// Saves one task's name, instruction, and/or timing.
  ///
  /// The observed record travels as `expected`, so a task edited elsewhere
  /// answers a conflict and this surface re-reads instead of overwriting.
  Future<ScheduleUpdateResult?> update({
    required ScheduleCatalogEntry entry,
    String? title,
    String? prompt,
    ScheduleTimingChange? change,
  }) async {
    try {
      final result = await _repository.updateSchedule(
        sessionId: entry.sessionId,
        id: entry.record.id,
        expected: entry.record,
        title: title,
        prompt: prompt,
        change: change,
      );
      await _refreshNow();
      return result;
    } catch (error, stackTrace) {
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: <String, Object?>{
          'controller': 'ScheduleManagerController',
          'action': 'update',
          'id': entry.record.id,
        },
      );
      return null;
    }
  }

  /// Deletes one task and its saved deliveries.
  Future<ScheduleDeleteResult?> delete(ScheduleCatalogEntry entry) async {
    try {
      final result = await _repository.deleteSchedule(
        sessionId: entry.sessionId,
        id: entry.record.id,
      );
      await _refreshNow();
      return result;
    } catch (error, stackTrace) {
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: <String, Object?>{
          'controller': 'ScheduleManagerController',
          'action': 'delete',
          'id': entry.record.id,
        },
      );
      return null;
    }
  }

  /// The page's callback surface, bound to this controller.
  ScheduleManagerActions get actions => ScheduleManagerActions(
    refresh: refresh,
    search: search,
    setFilter: setFilter,
    loadHistory: (ScheduleCatalogEntry entry) => unawaited(loadHistory(entry)),
    loadOlderHistory: (ScheduleCatalogEntry entry) =>
        unawaited(loadOlderHistory(entry)),
    update: ({
      required ScheduleCatalogEntry entry,
      String? title,
      String? prompt,
      ScheduleTimingChange? change,
    }) => update(entry: entry, title: title, prompt: prompt, change: change),
    delete: delete,
  );

  void _publish() {
    _state.value = ScheduleManagerUiState(
      isLoading: _isLoading,
      failed: _failed,
      unavailable: _unavailable,
      entries: _entries,
      query: _query,
      filter: _filter,
    );
  }
}

/// One controller per backend, disposed with the Settings surface.
final scheduleManagerControllerProvider = Provider.family
    .autoDispose<ScheduleManagerController, String>((ref, backendId) {
      final controller = ScheduleManagerController(
        ref.watch(chatRepositoryProvider(backendId)),
      );
      return controller;
    });

/// The operations the page may invoke, so the presentation is testable
/// without a repository double.
final class ScheduleManagerActions {
  const ScheduleManagerActions({
    required this.refresh,
    required this.search,
    required this.setFilter,
    required this.loadHistory,
    required this.loadOlderHistory,
    required this.update,
    required this.delete,
  });

  final void Function() refresh;
  final void Function(String query) search;
  final void Function(ScheduleFilter filter) setFilter;
  final void Function(ScheduleCatalogEntry entry) loadHistory;
  final void Function(ScheduleCatalogEntry entry) loadOlderHistory;
  final Future<ScheduleUpdateResult?> Function({
    required ScheduleCatalogEntry entry,
    String? title,
    String? prompt,
    ScheduleTimingChange? change,
  })
  update;
  final Future<ScheduleDeleteResult?> Function(ScheduleCatalogEntry entry)
  delete;
}

/// The Settings mount point.
class SettingsAutomationTasksPage extends ConsumerWidget {
  const SettingsAutomationTasksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backendId = ref.watch(settingsBackendScopeProvider);
    if (backendId.isEmpty) {
      return const SettingsPageScaffold(title: '', children: <Widget>[]);
    }
    final controller = ref.watch(scheduleManagerControllerProvider(backendId));
    return StreamBuilder<ScheduleManagerUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder: (context, snapshot) {
        final state = snapshot.data ?? const ScheduleManagerUiState();
        return AutomationTasksBody(
          state: state,
          history: controller.history,
          actions: controller.actions,
        );
      },
    );
  }
}

/// The page: one state in, callbacks out.
class AutomationTasksBody extends StatelessWidget {
  const AutomationTasksBody({
    required this.state,
    required this.history,
    required this.actions,
    super.key,
  });

  final ScheduleManagerUiState state;
  final Stream<ScheduleHistoryUiState> history;
  final ScheduleManagerActions actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = state.visible;
    return SettingsPageScaffold(
      title: l10n.automationTasksTitle,
      children: <Widget>[
        SettingsSectionHeading(
          title: l10n.automationTasksTitle,
          intro: l10n.automationTasksIntro,
          showTitle: false,
        ),
        Row(
          children: <Widget>[
            IconButton(
              tooltip: l10n.refresh,
              icon: const Icon(Icons.refresh),
              onPressed: state.isLoading ? null : actions.refresh,
            ),
          ],
        ),
        if (!state.isLoading && state.unavailable) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            l10n.automationTasksUnavailable,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ] else if (state.failed && rows.isEmpty) ...<Widget>[
          const SizedBox(height: 8),
          SettingsNavRow(
            title: l10n.retry,
            leading: const Icon(Icons.refresh),
            onTap: actions.refresh,
          ),
        ] else ...<Widget>[
          const SizedBox(height: 8),
          TextField(
            decoration: InputDecoration(
              hintText: l10n.automationTasksSearchHint,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: actions.search,
          ),
          const SizedBox(height: 8),
          SegmentedButton<ScheduleFilter>(
            segments: <ButtonSegment<ScheduleFilter>>[
              ButtonSegment<ScheduleFilter>(
                value: ScheduleFilter.all,
                label: Text(l10n.automationTasksFilterAll),
              ),
              ButtonSegment<ScheduleFilter>(
                value: ScheduleFilter.enabled,
                label: Text(l10n.automationTasksFilterEnabled),
              ),
              ButtonSegment<ScheduleFilter>(
                value: ScheduleFilter.inactive,
                label: Text(l10n.automationTasksFilterInactive),
              ),
            ],
            selected: <ScheduleFilter>{state.filter},
            onSelectionChanged: (Set<ScheduleFilter> selection) =>
                actions.setFilter(selection.first),
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty && !state.isLoading)
            Text(
              state.entries.isEmpty
                  ? l10n.automationTasksEmpty
                  : l10n.automationTasksNoMatches,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          for (final entry in rows)
            _TaskRow(
              entry: entry,
              onOpen: () => unawaited(
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => ScheduleTaskSheet(
                    entry: entry,
                    history: history,
                    actions: actions,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// One catalog row: stored name, status, frequency, and next run — never the
/// session's display name, which the reference also does not show here.
class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.entry, required this.onOpen});

  final ScheduleCatalogEntry entry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = entry.status == ScheduleStatus.active;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: StateDot(
        state: active ? StateDotState.ongoing : StateDotState.disabled,
        size: 8,
      ),
      title: Text(entry.record.title),
      subtitle: Text(
        '${scheduleFrequencyLabel(entry.record, l10n)}'
        '${active ? ' · ${l10n.automationTaskNextRun(entry.record.scheduledAt)}' : ' · ${l10n.automationTaskStatusInactive}'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onOpen,
    );
  }
}

/// The stored rule as one line. Wall-clock kinds name their time and zone; the
/// instant-based ones name the target only.
String scheduleFrequencyLabel(ScheduleRecord record, AppLocalizations l10n) =>
    switch (record.kind) {
      ScheduleKind.after ||
      ScheduleKind.at => l10n.automationFrequencyOnce(record.scheduledAt),
      ScheduleKind.every => l10n.automationFrequencyEvery(
        record.everySeconds ?? 0,
      ),
      ScheduleKind.daily => l10n.automationFrequencyDaily(
        record.time ?? '',
        record.timeZone ?? '',
      ),
      ScheduleKind.weekly => l10n.automationFrequencyWeekly(
        scheduleWeekdayList(record.weekdays, l10n),
        record.time ?? '',
        record.timeZone ?? '',
      ),
      ScheduleKind.cron => l10n.automationFrequencyCron(
        record.expression ?? '',
        record.timeZone ?? '',
      ),
    };

/// ISO weekdays as their localized short names, joined.
String scheduleWeekdayList(List<int> weekdays, AppLocalizations l10n) {
  const names = <int, String Function(AppLocalizations)>{
    1: _weekdayMon,
    2: _weekdayTue,
    3: _weekdayWed,
    4: _weekdayThu,
    5: _weekdayFri,
    6: _weekdaySat,
    7: _weekdaySun,
  };
  return weekdays
      .where(names.containsKey)
      .map((int day) => names[day]!(l10n))
      .join(', ');
}

String _weekdayMon(AppLocalizations l10n) => l10n.automationWeekdayMon;
String _weekdayTue(AppLocalizations l10n) => l10n.automationWeekdayTue;
String _weekdayWed(AppLocalizations l10n) => l10n.automationWeekdayWed;
String _weekdayThu(AppLocalizations l10n) => l10n.automationWeekdayThu;
String _weekdayFri(AppLocalizations l10n) => l10n.automationWeekdayFri;
String _weekdaySat(AppLocalizations l10n) => l10n.automationWeekdaySat;
String _weekdaySun(AppLocalizations l10n) => l10n.automationWeekdaySun;

/// The task detail: its rules, its saved deliveries, and the two mutations a
/// phone can make — a compare-and-update and a delete.
class ScheduleTaskSheet extends StatefulWidget {
  const ScheduleTaskSheet({
    required this.entry,
    required this.history,
    required this.actions,
    super.key,
  });

  final ScheduleCatalogEntry entry;
  final Stream<ScheduleHistoryUiState> history;
  final ScheduleManagerActions actions;

  @override
  State<ScheduleTaskSheet> createState() => _ScheduleTaskSheetState();
}

class _ScheduleTaskSheetState extends State<ScheduleTaskSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.entry.record.title,
  );
  late final TextEditingController _instruction = TextEditingController(
    text: widget.entry.record.prompt,
  );
  late ScheduleTimingDraft _timing = ScheduleTimingDraft.from(
    widget.entry.record,
  );
  bool _editing = false;
  bool _records = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    widget.actions.loadHistory(widget.entry);
  }

  @override
  void dispose() {
    _name.dispose();
    _instruction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final record = widget.entry.record;
    final active = widget.entry.status == ScheduleStatus.active;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          12 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      record.title,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (widget.entry.status == ScheduleStatus.inactive)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        l10n.automationTaskStatusInactive,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: l10n.close,
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              SegmentedButton<bool>(
                segments: <ButtonSegment<bool>>[
                  ButtonSegment<bool>(
                    value: false,
                    label: Text(l10n.automationTaskRules),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text(l10n.automationTaskRecords),
                  ),
                ],
                selected: <bool>{_records},
                onSelectionChanged: (Set<bool> selection) =>
                    setState(() => _records = selection.first),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: _records
                    ? _RecordsTab(
                        history: widget.history,
                        entry: widget.entry,
                        actions: widget.actions,
                      )
                    : _RulesTab(
                        entry: widget.entry,
                        editing: _editing,
                        name: _name,
                        instruction: _instruction,
                        timing: _timing,
                        notice: _notice,
                        onEdit: active
                            ? () => setState(() {
                                _editing = true;
                                _notice = null;
                              })
                            : null,
                        onCancel: () => setState(() {
                          _editing = false;
                          _name.text = record.title;
                          _instruction.text = record.prompt;
                          _timing = ScheduleTimingDraft.from(record);
                          _notice = null;
                        }),
                        onTimingChanged: (ScheduleTimingDraft draft) =>
                            setState(() => _timing = draft),
                        onSave: () => unawaited(_save()),
                        onDelete: () => unawaited(_confirmDelete()),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final record = widget.entry.record;
    final title = _name.text.trim();
    final prompt = _instruction.text.trim();
    final change = _timing.changeFrom(record);
    final result = await widget.actions.update(
      entry: widget.entry,
      // Only fields that differ travel; the host keeps what is omitted.
      title: title == record.title ? null : title,
      prompt: prompt == record.prompt ? null : prompt,
      change: change,
    );
    if (!mounted) return;
    final notice = switch (result) {
      null => l10n.automationTaskError,
      ScheduleUpdateCommitted() => l10n.automationTaskSaved,
      ScheduleUpdateMiss(:final code) => switch (code) {
        'schedule_conflict' => l10n.automationTaskConflict,
        'schedule_ended' => l10n.automationTaskEnded,
        'schedule_not_found' => l10n.automationTaskMissing,
        _ => l10n.automationTaskError,
      },
    };
    setState(() {
      _notice = notice;
      if (result is ScheduleUpdateCommitted) _editing = false;
    });
  }

  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.automationTaskDeleteTitle(widget.entry.record.title)),
        content: Text(l10n.automationTaskDeleteBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.automationTaskDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await widget.actions.delete(widget.entry);
    if (!mounted) return;
    // A task the session no longer owns reads as already gone, not as a
    // failure: the row disappears with the refresh either way.
    if (result == null || !result.deleted) {
      setState(() => _notice = l10n.automationTaskMissing);
      return;
    }
    Navigator.of(context).pop();
  }
}

class _RulesTab extends StatelessWidget {
  const _RulesTab({
    required this.entry,
    required this.editing,
    required this.name,
    required this.instruction,
    required this.timing,
    required this.notice,
    required this.onEdit,
    required this.onCancel,
    required this.onTimingChanged,
    required this.onSave,
    required this.onDelete,
  });

  final ScheduleCatalogEntry entry;
  final bool editing;
  final TextEditingController name;
  final TextEditingController instruction;
  final ScheduleTimingDraft timing;
  final String? notice;
  final VoidCallback? onEdit;
  final VoidCallback onCancel;
  final void Function(ScheduleTimingDraft draft) onTimingChanged;
  final VoidCallback onSave;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final record = entry.record;
    return ListView(
      shrinkWrap: true,
      children: <Widget>[
        if (notice != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              notice!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        if (editing) ...<Widget>[
          TextField(
            controller: name,
            decoration: InputDecoration(
              labelText: l10n.automationTaskName,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: instruction,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: l10n.automationTaskInstruction,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          ScheduleTimingEditor(draft: timing, onChanged: onTimingChanged),
        ] else ...<Widget>[
          _Fact(label: l10n.automationTaskInstruction, value: record.prompt),
          _Fact(
            label: l10n.automationTaskFrequency,
            value: scheduleFrequencyLabel(record, l10n),
          ),
          if (entry.status == ScheduleStatus.active)
            _Fact(label: l10n.automationTaskNext, value: record.scheduledAt),
          _Fact(label: l10n.automationTaskId, value: record.id),
          if (entry.lastDelivery case final delivery?)
            _Fact(
              label: l10n.automationTaskLastDelivery,
              value: delivery.deliveredAt,
            ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: <Widget>[
            if (editing) ...<Widget>[
              FilledButton(onPressed: onSave, child: Text(l10n.save)),
              TextButton(onPressed: onCancel, child: Text(l10n.cancel)),
            ] else if (onEdit != null)
              FilledButton.tonal(
                onPressed: onEdit,
                child: Text(l10n.automationTaskEdit),
              ),
            TextButton(
              onPressed: onDelete,
              child: Text(
                l10n.automationTaskDelete,
                style: TextStyle(color: scheme.error),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _RecordsTab extends StatelessWidget {
  const _RecordsTab({
    required this.history,
    required this.entry,
    required this.actions,
  });

  final Stream<ScheduleHistoryUiState> history;
  final ScheduleCatalogEntry entry;
  final ScheduleManagerActions actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return StreamBuilder<ScheduleHistoryUiState>(
      stream: history,
      initialData: const ScheduleHistoryUiState(isLoading: true),
      builder: (context, snapshot) {
        final state = snapshot.data ?? const ScheduleHistoryUiState();
        final page = state.page;
        if (page == null) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.failed) {
            return SettingsNavRow(
              title: l10n.retry,
              leading: const Icon(Icons.refresh),
              onTap: () => actions.loadHistory(entry),
            );
          }
          if (state.code != null) {
            // A task the session no longer owns, or a cursor the host dropped.
            return Text(
              state.code == 'delivery_cursor_not_found'
                  ? l10n.automationTaskCursorError
                  : l10n.automationTaskNotFound,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            );
          }
          return Text(
            l10n.automationTaskRecordsEmpty,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          );
        }
        if (page.records.isEmpty) {
          return Text(
            l10n.automationTaskRecordsEmpty,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          );
        }
        return ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final record in page.records)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(record.scheduledAt),
                subtitle: Text(
                  record.prompt ?? l10n.automationTaskLegacyRecord,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (page.nextBefore != null)
              SettingsNavRow(
                title: l10n.automationTaskLoadOlder,
                leading: const Icon(Icons.history),
                onTap: () => actions.loadOlderHistory(entry),
              ),
            if (page.earlierRecordsPruned && page.nextBefore == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.automationTaskRetention(
                    page.retention.days,
                    page.retention.records,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (page.earlierRecordsUnavailable)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.automationTaskEarlierUnavailable,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.warning,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The rule editor's working copy.
///
/// It starts from the stored record, so an untouched save sends no `change` at
/// all — the host keeps the committed target, including milliseconds and the
/// stored zone spelling, exactly as the reference's draft does.
final class ScheduleTimingDraft {
  const ScheduleTimingDraft({
    required this.kind,
    this.date = '',
    this.time = '',
    this.timeZone = 'UTC',
    this.seconds = '3600',
    this.expression = '',
    this.weekdays = const <int>[1],
  });

  factory ScheduleTimingDraft.from(ScheduleRecord record) =>
      ScheduleTimingDraft(
        kind: switch (record.kind) {
          ScheduleKind.after || ScheduleKind.at => ScheduleEditKind.once,
          ScheduleKind.every => ScheduleEditKind.every,
          ScheduleKind.daily => ScheduleEditKind.daily,
          ScheduleKind.weekly => ScheduleEditKind.weekly,
          ScheduleKind.cron => ScheduleEditKind.cron,
        },
        time: record.time ?? '',
        timeZone: record.timeZone ?? 'UTC',
        seconds: '${record.everySeconds ?? 3600}',
        expression: record.expression ?? '',
        weekdays: record.weekdays.isEmpty ? const <int>[1] : record.weekdays,
      );

  final ScheduleEditKind kind;

  /// `YYYY-MM-DD` for a one-shot target.
  final String date;
  final String time;
  final String timeZone;
  final String seconds;
  final String expression;
  final List<int> weekdays;

  ScheduleTimingDraft copyWith({
    ScheduleEditKind? kind,
    String? date,
    String? time,
    String? timeZone,
    String? seconds,
    String? expression,
    List<int>? weekdays,
  }) => ScheduleTimingDraft(
    kind: kind ?? this.kind,
    date: date ?? this.date,
    time: time ?? this.time,
    timeZone: timeZone ?? this.timeZone,
    seconds: seconds ?? this.seconds,
    expression: expression ?? this.expression,
    weekdays: weekdays ?? this.weekdays,
  );

  /// The change to send, or null when the draft still describes the stored
  /// rule (a name or instruction edit alone must not reset the target).
  ScheduleTimingChange? changeFrom(ScheduleRecord record) {
    final stored = ScheduleTimingDraft.from(record);
    if (kind == stored.kind && _sameTiming(stored)) {
      return null;
    }
    return switch (kind) {
      ScheduleEditKind.once => ScheduleAtChange(
        at: <String, Object?>{
          'date': date,
          'time': time,
          'time_zone': timeZone,
        },
      ),
      ScheduleEditKind.every => ScheduleEveryChange(
        everySeconds: int.tryParse(seconds) ?? 3600,
      ),
      ScheduleEditKind.daily => ScheduleDailyChange(
        time: time,
        timeZone: timeZone,
      ),
      ScheduleEditKind.weekly => ScheduleWeeklyChange(
        time: time,
        timeZone: timeZone,
        weekdays: weekdays,
      ),
      ScheduleEditKind.cron => ScheduleCronChange(
        expression: expression,
        timeZone: timeZone,
      ),
    };
  }

  bool _sameTiming(ScheduleTimingDraft other) =>
      date == other.date &&
      time == other.time &&
      timeZone == other.timeZone &&
      seconds == other.seconds &&
      expression == other.expression &&
      weekdays.join(',') == other.weekdays.join(',');

  ScheduleTimingDraft withWeekday(int day, bool selected) {
    final next = <int>{...weekdays};
    if (selected) {
      next.add(day);
    } else {
      next.remove(day);
    }
    return copyWith(weekdays: next.toList()..sort());
  }
}

/// The repeat choices a phone can express; the stored kinds map onto them.
enum ScheduleEditKind { once, every, daily, weekly, cron }

/// The timing editor: a repeat choice plus that choice's own fields.
class ScheduleTimingEditor extends StatelessWidget {
  const ScheduleTimingEditor({
    required this.draft,
    required this.onChanged,
    super.key,
  });

  final ScheduleTimingDraft draft;
  final void Function(ScheduleTimingDraft draft) onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        DropdownButtonFormField<ScheduleEditKind>(
          initialValue: draft.kind,
          decoration: InputDecoration(
            labelText: l10n.scheduleEditRepeat,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: <DropdownMenuItem<ScheduleEditKind>>[
            for (final kind in ScheduleEditKind.values)
              DropdownMenuItem<ScheduleEditKind>(
                value: kind,
                child: Text(scheduleEditKindLabel(kind, l10n)),
              ),
          ],
          onChanged: (ScheduleEditKind? kind) {
            if (kind == null) return;
            onChanged(draft.copyWith(kind: kind));
          },
        ),
        const SizedBox(height: 8),
        if (draft.kind == ScheduleEditKind.once) ...<Widget>[
          _Field(
            label: l10n.scheduleFieldDate,
            value: draft.date,
            hint: '2030-01-01',
            onChanged: (String value) => onChanged(draft.copyWith(date: value)),
          ),
        ],
        if (draft.kind == ScheduleEditKind.once ||
            draft.kind == ScheduleEditKind.daily ||
            draft.kind == ScheduleEditKind.weekly)
          _Field(
            label: l10n.scheduleFieldTime,
            value: draft.time,
            hint: '09:00:00',
            onChanged: (String value) => onChanged(draft.copyWith(time: value)),
          ),
        if (draft.kind == ScheduleEditKind.every)
          _Field(
            label: l10n.scheduleFieldSeconds,
            value: draft.seconds,
            hint: '3600',
            onChanged: (String value) =>
                onChanged(draft.copyWith(seconds: value)),
          ),
        if (draft.kind == ScheduleEditKind.cron)
          _Field(
            label: l10n.scheduleFieldExpression,
            value: draft.expression,
            hint: '0 2 * * *',
            onChanged: (String value) =>
                onChanged(draft.copyWith(expression: value)),
          ),
        if (draft.kind == ScheduleEditKind.weekly) ...<Widget>[
          Text(
            l10n.scheduleFieldWeekdays,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: <Widget>[
              for (var day = 1; day <= 7; day++)
                FilterChip(
                  label: Text(scheduleWeekdayName(day, l10n)),
                  selected: draft.weekdays.contains(day),
                  onSelected: (bool selected) =>
                      onChanged(draft.withWeekday(day, selected)),
                ),
            ],
          ),
        ],
        if (draft.kind != ScheduleEditKind.every)
          _Field(
            label: l10n.scheduleFieldZone,
            value: draft.timeZone,
            hint: 'UTC',
            onChanged: (String value) =>
                onChanged(draft.copyWith(timeZone: value)),
          ),
      ],
    );
  }
}

String scheduleEditKindLabel(ScheduleEditKind kind, AppLocalizations l10n) =>
    switch (kind) {
      ScheduleEditKind.once => l10n.scheduleKindOnce,
      ScheduleEditKind.every => l10n.scheduleKindEvery,
      ScheduleEditKind.daily => l10n.scheduleKindDaily,
      ScheduleEditKind.weekly => l10n.scheduleKindWeekly,
      ScheduleEditKind.cron => l10n.scheduleKindCron,
    };

String scheduleWeekdayName(int day, AppLocalizations l10n) => switch (day) {
  1 => l10n.automationWeekdayMon,
  2 => l10n.automationWeekdayTue,
  3 => l10n.automationWeekdayWed,
  4 => l10n.automationWeekdayThu,
  5 => l10n.automationWeekdayFri,
  6 => l10n.automationWeekdaySat,
  _ => l10n.automationWeekdaySun,
};

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    required this.hint,
    required this.onChanged,
  });

  final String label;
  final String value;
  final String hint;
  final void Function(String value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: onChanged,
      ),
    );
  }
}
