/// Automation-tasks page behavior: the host-scheduler gate, the filtered
/// board, the read-only rules view, the compare-and-update edit with its
/// refusal notices, the delivery history, and the confirmed delete.
///
/// The page is presentation only — one state in, callbacks out — so these
/// assertions read what a user sees ([docs/testing.md](../../../../docs/testing.md)).
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/settings/schedule_manager.dart';
import 'package:domain/model/schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('en'));

ScheduleCatalogEntry _entry({
  String id = 'schedule-1',
  String title = 'Weekly review',
  String prompt = 'review the diff',
  ScheduleKind kind = ScheduleKind.weekly,
  List<int> weekdays = const <int>[1, 5],
  ScheduleStatus status = ScheduleStatus.active,
  String sessionId = 'session-s',
}) => ScheduleCatalogEntry(
  record: ScheduleRecord(
    id: id,
    kind: kind,
    title: title,
    prompt: prompt,
    scheduledAt: '2026-09-30T09:00:00.000Z',
    time: kind == ScheduleKind.weekly || kind == ScheduleKind.daily
        ? '09:00:00.000'
        : null,
    timeZone: kind == ScheduleKind.weekly || kind == ScheduleKind.daily
        ? 'Asia/Shanghai'
        : null,
    weekdays: kind == ScheduleKind.weekly ? weekdays : const <int>[],
  ),
  sessionId: sessionId,
  status: status,
);

/// Records every callback the page makes.
final class _Recorder {
  final List<String> calls = <String>[];
  ScheduleUpdateResult? updateResult;
  ScheduleDeleteResult? deleteResult;
  final StreamController<ScheduleHistoryUiState> history =
      StreamController<ScheduleHistoryUiState>.broadcast();

  ScheduleManagerActions actions() => ScheduleManagerActions(
    refresh: () => calls.add('refresh'),
    search: (String query) => calls.add('search:$query'),
    setFilter: (ScheduleFilter filter) => calls.add('filter:${filter.name}'),
    loadHistory: (ScheduleCatalogEntry entry) =>
        calls.add('history:${entry.record.id}'),
    loadOlderHistory: (ScheduleCatalogEntry entry) =>
        calls.add('historyOlder:${entry.record.id}'),
    update:
        ({
          required ScheduleCatalogEntry entry,
          String? title,
          String? prompt,
          ScheduleTimingChange? change,
        }) async {
          calls.add(
            'update:${entry.record.id}:${title ?? ''}:${prompt ?? ''}:'
            '${change?.runtimeType ?? ''}',
          );
          return updateResult;
        },
    delete: (ScheduleCatalogEntry entry) async {
      calls.add('delete:${entry.record.id}');
      return deleteResult ??
          ScheduleDeleteResult(id: entry.record.id, deleted: true);
    },
  );
}

Future<_Recorder> _pump(
  WidgetTester tester,
  ScheduleManagerUiState state,
) async {
  final recorder = _Recorder();
  addTearDown(recorder.history.close);
  await tester.pumpWidget(
    l10nApp(
      home: AutomationTasksBody(
        state: state,
        history: recorder.history.stream,
        actions: recorder.actions(),
      ),
    ),
  );
  await tester.pump();
  return recorder;
}

void main() {
  testWidgets('a host without a scheduler says so and offers no board', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const ScheduleManagerUiState(unavailable: true));

    expect(find.text(_l10n.automationTasksUnavailable), findsOneWidget);
    expect(find.text(_l10n.automationTasksEmpty), findsNothing);
  });

  testWidgets('the board filters by search and status', (
    WidgetTester tester,
  ) async {
    final recorder = await _pump(
      tester,
      ScheduleManagerUiState(
        entries: <ScheduleCatalogEntry>[
          _entry(),
          _entry(
            id: 'schedule-2',
            title: 'Nightly',
            prompt: 'smoke suite',
            kind: ScheduleKind.cron,
            status: ScheduleStatus.inactive,
          ),
        ],
      ),
    );

    expect(find.text('Weekly review'), findsOneWidget);
    expect(find.text('Nightly'), findsOneWidget);
    // The frequency line names a weekly rule's days, time, and zone.
    expect(
      find.textContaining(
        _l10n.automationFrequencyWeekly(
          'Mon, Fri',
          '09:00:00.000',
          'Asia/Shanghai',
        ),
      ),
      findsOneWidget,
    );
    // An ended task says so instead of naming a next run.
    expect(
      find.textContaining(_l10n.automationTaskStatusInactive),
      findsOneWidget,
    );

    await tester.tap(find.text(_l10n.automationTasksFilterInactive));
    await tester.pump();
    expect(recorder.calls, contains('filter:inactive'));

    // The page renders exactly the state it was given: filtering is the
    // controller's job, so the unfiltered rows are still here.
    expect(find.text('Weekly review'), findsOneWidget);
  });

  testWidgets('opening a task shows its rules and reads its history', (
    WidgetTester tester,
  ) async {
    final recorder = await _pump(
      tester,
      ScheduleManagerUiState(entries: <ScheduleCatalogEntry>[_entry()]),
    );

    await tester.tap(find.text('Weekly review'));
    await tester.pumpAndSettle();

    expect(recorder.calls, contains('history:schedule-1'));
    // The read-only rules view names the instruction, the rule, the next run,
    // and the task id.
    expect(find.text(_l10n.automationTaskInstruction), findsOneWidget);
    expect(find.text('review the diff'), findsOneWidget);
    expect(find.text('schedule-1'), findsOneWidget);
    expect(find.text(_l10n.automationTaskEdit), findsOneWidget);
  });

  testWidgets('an edit sends only the fields that changed', (
    WidgetTester tester,
  ) async {
    final recorder = await _pump(
      tester,
      ScheduleManagerUiState(entries: <ScheduleCatalogEntry>[_entry()]),
    );
    recorder.updateResult = ScheduleUpdateCommitted(record: _entry().record);

    await tester.tap(find.text('Weekly review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.automationTaskEdit));
    await tester.pumpAndSettle();

    // Rename only: the timing draft is untouched, so no `change` travels.
    await tester.enterText(
      find.widgetWithText(TextField, 'review the diff'),
      'review the release',
    );
    await tester.tap(find.text(_l10n.save));
    await tester.pumpAndSettle();

    expect(recorder.calls, contains('update:schedule-1::review the release:'));
    expect(find.text(_l10n.automationTaskSaved), findsOneWidget);
  });

  testWidgets('a conflict is reported instead of silently overwriting', (
    WidgetTester tester,
  ) async {
    final recorder = await _pump(
      tester,
      ScheduleManagerUiState(entries: <ScheduleCatalogEntry>[_entry()]),
    );
    recorder.updateResult = const ScheduleUpdateMiss(
      id: 'schedule-1',
      code: 'schedule_conflict',
      message: 'changed since the read',
    );

    await tester.tap(find.text('Weekly review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.automationTaskEdit));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.save));
    await tester.pumpAndSettle();

    expect(find.text(_l10n.automationTaskConflict), findsOneWidget);
  });

  testWidgets('a timing change travels as its own record', (
    WidgetTester tester,
  ) async {
    final recorder = await _pump(
      tester,
      ScheduleManagerUiState(entries: <ScheduleCatalogEntry>[_entry()]),
    );
    recorder.updateResult = ScheduleUpdateCommitted(record: _entry().record);

    await tester.tap(find.text('Weekly review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.automationTaskEdit));
    await tester.pumpAndSettle();

    // Switching the repeat kind makes a change, even with untouched fields.
    await tester.tap(find.text(_l10n.scheduleKindWeekly));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.scheduleKindDaily).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.save));
    await tester.pumpAndSettle();

    expect(
      recorder.calls.any((String call) => call.contains('ScheduleDailyChange')),
      isTrue,
    );
  });

  testWidgets('the records tab renders deliveries and offers older pages', (
    WidgetTester tester,
  ) async {
    final recorder = await _pump(
      tester,
      ScheduleManagerUiState(entries: <ScheduleCatalogEntry>[_entry()]),
    );

    await tester.tap(find.text('Weekly review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.automationTaskRecords));
    await tester.pump();
    recorder.history.add(
      const ScheduleHistoryUiState(
        page: ScheduleHistoryPage(
          id: 'schedule-1',
          records: <ScheduleDeliveryRecord>[
            ScheduleDeliveryRecord(
              scheduledAt: '2026-09-23T09:00:00.000Z',
              deliveredAt: '2026-09-23T09:00:01.000Z',
              messageId: 'msg-2',
              prompt: 'review the diff',
            ),
            ScheduleDeliveryRecord(
              scheduledAt: '2026-09-16T09:00:00.000Z',
              deliveredAt: '2026-09-16T09:00:01.000Z',
              messageId: 'msg-1',
            ),
          ],
          earlierRecordsUnavailable: true,
          earlierRecordsPruned: false,
          retention: ScheduleRetentionBounds(days: 30, records: 200),
          nextBefore: 'msg-1',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('2026-09-23T09:00:00.000Z'), findsOneWidget);
    // A legacy receipt never substitutes the current instruction.
    expect(find.text(_l10n.automationTaskLegacyRecord), findsOneWidget);
    expect(find.text(_l10n.automationTaskEarlierUnavailable), findsOneWidget);

    await tester.tap(find.text(_l10n.automationTaskLoadOlder));
    await tester.pump();
    expect(recorder.calls, contains('historyOlder:schedule-1'));
  });

  testWidgets('a missing history code is stated, not retried', (
    WidgetTester tester,
  ) async {
    final recorder = await _pump(
      tester,
      ScheduleManagerUiState(entries: <ScheduleCatalogEntry>[_entry()]),
    );

    await tester.tap(find.text('Weekly review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.automationTaskRecords));
    await tester.pump();
    recorder.history.add(
      const ScheduleHistoryUiState(code: 'schedule_not_found'),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text(_l10n.automationTaskNotFound), findsOneWidget);
    expect(find.text(_l10n.retry), findsNothing);
  });

  testWidgets('deleting a task is confirmed first', (
    WidgetTester tester,
  ) async {
    final recorder = await _pump(
      tester,
      ScheduleManagerUiState(entries: <ScheduleCatalogEntry>[_entry()]),
    );

    await tester.tap(find.text('Weekly review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.automationTaskDelete));
    await tester.pumpAndSettle();

    expect(recorder.calls.where((c) => c.startsWith('delete:')), isEmpty);
    expect(
      find.text(_l10n.automationTaskDeleteTitle('Weekly review')),
      findsOneWidget,
    );

    await tester.tap(
      find.widgetWithText(FilledButton, _l10n.automationTaskDelete),
    );
    await tester.pumpAndSettle();
    expect(recorder.calls, contains('delete:schedule-1'));
  });
}
