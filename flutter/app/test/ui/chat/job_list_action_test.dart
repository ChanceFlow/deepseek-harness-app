/// Background-jobs sheet behavior: the ordered roster, the section fold, the
/// retained-output panel (`job/follow`), and the two-press stop (`job/kill`).
///
/// The widget tree is real and the sheet reads the same chat state the header
/// does; the wire seams are injected exactly as the production route injects
/// the controller's, so these tests assert what a user sees rather than a
/// re-encode ([docs/testing.md](../../../../docs/testing.md)).
library;

import 'dart:async';

import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/job_list_action.dart';
import 'package:app/ui/shared/menu_material.dart';
import 'package:domain/model/jobs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('en'));

/// One job's observation, driven by the test rather than a socket.
class _JobSeams {
  final StreamController<JobOutputFrame> frames =
      StreamController<JobOutputFrame>.broadcast();

  /// The live roster the sheet follows; the header's snapshot is only the
  /// first-frame seed.
  final StreamController<List<JobView>> roster =
      StreamController<List<JobView>>.broadcast();

  final List<int?> resumeOffsets = <int?>[];
  final List<(String, String)> kills = <(String, String)>[];
  bool killAccepted = true;

  Stream<JobOutputFrame> observe(
    String sessionId,
    String jobId, {
    int? resumeFrom,
  }) {
    resumeOffsets.add(resumeFrom);
    return frames.stream;
  }

  Future<bool> kill(String sessionId, String jobId) async {
    kills.add((sessionId, jobId));
    return killAccepted;
  }
}

JobView _job({
  required String id,
  required JobStatus status,
  String label = 'pnpm test',
  String kind = 'bash',
  String? progress,
  String? detail,
  int startedAt = 1000,
  int? finishedAt,
  int? outputTotal,
}) => JobView(
  id: id,
  kind: kind,
  label: label,
  status: status,
  progress: progress,
  detail: detail,
  startedAt: startedAt,
  finishedAt: finishedAt,
  output: outputTotal == null
      ? null
      : JobOutputWindow(total: outputTotal, earliest: 0),
);

Future<void> _pump(
  WidgetTester tester,
  List<JobView> jobs,
  _JobSeams seams,
) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(seams.frames.close);
  addTearDown(seams.roster.close);
  final state = ChatUiState(jobs: jobs);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // The sheet reads the same chat state the header does, so a lifecycle
        // frame settles a row and a kill converges through the roster rather
        // than a local guess.
        chatUiStateProvider(kDshBaseUrl)
            .overrideWith((ref) => Stream<ChatUiState>.value(state)),
      ],
      child: l10nApp(
        home: Scaffold(
          body: JobListAction(
            jobs: jobs,
            sessionId: 'session-j',
            observeJobOutput: seams.observe,
            killJob: seams.kill,
            jobRoster: seams.roster.stream,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openSheet(
  WidgetTester tester,
  List<JobView> jobs,
  _JobSeams seams,
) async {
  await _pump(tester, jobs, seams);
  await tester.tap(find.byType(JobListAction));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the pill counts live jobs and opens the ordered roster', (
    WidgetTester tester,
  ) async {
    final seams = _JobSeams();
    await _openSheet(tester, <JobView>[
      _job(id: 'bash-1', status: JobStatus.running, progress: '3/10'),
      _job(
        id: 'bash-2',
        status: JobStatus.completed,
        label: 'build apk',
        startedAt: 10,
        finishedAt: 40,
        detail: 'exit code: 0',
      ),
    ], seams);

    // The header pill names the live count before the sheet opens.
    expect(find.text(_l10n.jobCountRunning(1)), findsOneWidget);
    // Both rows are listed; the settled tail folds behind its count while
    // live work exists.
    expect(find.text('pnpm test'), findsOneWidget);
    expect(find.text(_l10n.jobSettledCount(1)), findsOneWidget);
    expect(find.text('build apk'), findsNothing);

    await tester.tap(find.text(_l10n.jobSettledCount(1)));
    await tester.pumpAndSettle();
    expect(find.text('build apk'), findsOneWidget);
    expect(find.text('exit code: 0'), findsOneWidget);
  });

  testWidgets('the roster opens on the house menu card', (tester) async {
    final seams = _JobSeams();
    await _openSheet(tester, <JobView>[
      _job(id: 'bash-1', status: JobStatus.running, progress: '3/10'),
    ], seams);

    // The pin draws this list as a menu, not as a Material sheet
    // (`ui-jobs/src/client/JobListAction.module.css` `.menu`, :41-65), so the
    // opener must seat it on the shared menu material — a `showModalBottomSheet`
    // here would paint Material's own fill and elevation under the card.
    final card = find.byKey(const ValueKey('anchored-menu-card'));
    expect(card, findsOneWidget);
    expect(tester.widget(card), isA<MenuMaterial>());
  });

  testWidgets('an observable row expands into its output panel', (
    WidgetTester tester,
  ) async {
    final seams = _JobSeams();
    await _openSheet(tester, <JobView>[
      _job(
        id: 'bash-1',
        status: JobStatus.completed,
        startedAt: 10,
        finishedAt: 40,
        outputTotal: 120,
      ),
    ], seams);

    expect(find.text(_l10n.jobOutputEmpty), findsNothing);
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    // The stream has produced nothing yet, and the panel says so rather than
    // rendering an empty box; the copy control is present before any output.
    expect(find.text(_l10n.jobOutputEmpty), findsOneWidget);
    expect(find.byIcon(Icons.copy_all_outlined), findsOneWidget);
    expect(seams.resumeOffsets, <int?>[null]);

    // A lossy chunk arrives while the row stays expanded, so the retention
    // notice sits above the output.
    seams.frames.add(
      const JobOutputChunks(
        chunks: <JobOutputChunk>[
          JobOutputChunk(
            at: 0,
            text: 'build started\n',
            channel: JobChannel.stdout,
            gapBefore: true,
          ),
        ],
        next: 14,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('build started'), findsOneWidget);
    expect(find.text(_l10n.jobOutputGap), findsOneWidget);

    // Collapsing cancels the observation; re-expanding resumes at the last
    // published offset instead of replaying the retained head.
    await tester.tap(find.byIcon(Icons.expand_less));
    await tester.pumpAndSettle();
    expect(find.textContaining('build started'), findsNothing);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(seams.resumeOffsets, <int?>[null, 14]);
  });

  testWidgets('a roster frame settles the row in place', (
    WidgetTester tester,
  ) async {
    final seams = _JobSeams();
    await _openSheet(tester, <JobView>[
      _job(id: 'bash-1', status: JobStatus.running),
    ], seams);
    expect(find.text(_l10n.jobKillStop), findsOneWidget);

    // The sheet outlives the header's rebuilds, so the roster stream is what
    // takes the row off `running`; the stop affordance goes with it.
    seams.roster.add(<JobView>[
      _job(
        id: 'bash-1',
        status: JobStatus.killed,
        finishedAt: 2000,
        detail: 'cancelled by the user',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text(_l10n.jobKillStop), findsNothing);
    expect(find.text('cancelled by the user'), findsOneWidget);
  });

  testWidgets('a running row arms its stop on the first press', (
    WidgetTester tester,
  ) async {
    final seams = _JobSeams();
    await _openSheet(tester, <JobView>[
      _job(id: 'bash-1', status: JobStatus.running),
    ], seams);

    expect(find.text(_l10n.jobKillStop), findsOneWidget);
    // One frame only: the arming window is real wall-clock time, so settling
    // would run it out and disarm the control.
    await tester.tap(find.text(_l10n.jobKillStop));
    await tester.pump();
    expect(find.text(_l10n.jobKillConfirm), findsOneWidget);
    expect(seams.kills, isEmpty);

    // The confirming press fires the stop for this session and job; an
    // admitted kill stays pending until the roster takes the row off
    // `running`, so the control disables instead of re-arming.
    await tester.tap(find.text(_l10n.jobKillConfirm));
    await tester.pump();
    expect(seams.kills, <(String, String)>[('session-j', 'bash-1')]);
    expect(find.text(_l10n.jobKillStop), findsOneWidget);
    final control = tester.widget<TextButton>(
      find.ancestor(
        of: find.text(_l10n.jobKillStop),
        matching: find.byType(TextButton),
      ),
    );
    expect(control.onPressed, isNull);
  });
}
