/// Plugin-manager page behavior: the management gate, the bundle roster with
/// its switches, the confirmed uninstall, the pushed installation progress
/// with its build approval, and the version-exemption ledger.
///
/// The page is presentation only — one state in, callbacks out — so these
/// assertions read what a user sees while the wire stays with the controller
/// ([docs/testing.md](../../../../docs/testing.md)).
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/settings/plugin_manager.dart';
import 'package:domain/model/plugin_management.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('en'));

PluginBundle _bundle({
  String name = 'dsh-schedule',
  String? version = '0.1.7-rc.2',
  bool enabled = false,
  bool installed = true,
  bool optional = true,
  bool removable = true,
  PluginReadOnlyReason? readOnlyReason,
  PluginManagementError? error,
  List<PluginBundleRow> rows = const <PluginBundleRow>[],
}) => PluginBundle(
  name: name,
  version: version,
  enabled: enabled,
  installed: installed,
  optional: optional,
  removable: removable,
  readOnlyReason: readOnlyReason,
  error: error,
  title: const PluginLocalizedText(<String, String>{
    'en': 'Scheduled tasks',
    'zh': '定时任务',
  }),
  description: 'Reminders on the host',
  rows: rows,
);

/// Records every callback the page makes.
final class _Recorder {
  final List<String> calls = <String>[];

  PluginManagerActions actions() => PluginManagerActions(
    refresh: () => calls.add('refresh'),
    search: (String query) => calls.add('search:$query'),
    setBundleEnabled: (String name, bool enabled) =>
        calls.add('bundle:$name:$enabled'),
    setPluginEnabled: (String entryId, bool enabled) =>
        calls.add('row:$entryId:$enabled'),
    uninstall: (String name) => calls.add('uninstall:$name'),
    startInstall: (String spec, String? registry) =>
        calls.add('install:$spec:${registry ?? ''}'),
    cancelInstall: () => calls.add('cancel'),
    approveBuildsAndRetry: () => calls.add('approve'),
    enableInstalled: () => calls.add('enableInstalled'),
    dismissInstall: () => calls.add('dismiss'),
    loadExemptions: () => calls.add('loadExemptions'),
    revokeExemption: (String packageVersion, String runtimeVersion) =>
        calls.add('revoke:$packageVersion:$runtimeVersion'),
  );
}

Future<_Recorder> _pump(WidgetTester tester, PluginManagerUiState state) async {
  final recorder = _Recorder();
  await tester.pumpWidget(
    l10nApp(
      home: PluginManagerBody(
        state: state,
        states: const Stream<PluginManagerUiState>.empty(),
        actions: recorder.actions(),
      ),
    ),
  );
  // One frame only: an indeterminate progress bar never settles.
  await tester.pump();
  return recorder;
}

void main() {
  testWidgets('an unmanaged host offers no roster and says so', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const PluginManagerUiState(managementAvailable: false));

    expect(find.text(_l10n.pluginManagerUnavailable), findsOneWidget);
    // The install action is disabled when the host composes no manager.
    final add = tester.widget<FilledButton>(
      find
          .ancestor(
            of: find.text(_l10n.pluginManagerAdd),
            matching: find.byType(FilledButton),
          )
          .first,
    );
    expect(add.onPressed, isNull);
  });

  testWidgets('the roster shows identity, tags, and locked reasons', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      PluginManagerUiState(
        managementAvailable: true,
        bundles: <PluginBundle>[
          _bundle(
            name: '@deepseek-ai/dsh-experimental-agent-team',
            enabled: true,
            error: const PluginManagementError(
              code: PluginManagementErrorCode.operationError,
              diagnostic: 'peer range unsatisfied',
            ),
          ),
          _bundle(
            name: 'locked-bundle',
            readOnlyReason: PluginReadOnlyReason.managementRequired,
          ),
        ],
      ),
    );

    expect(find.text('Scheduled tasks'), findsNWidgets(2));
    expect(find.text(_l10n.pluginManagerBetaTag), findsOneWidget);
    expect(find.text(_l10n.pluginManagerProblemTag), findsOneWidget);
    expect(find.text('peer range unsatisfied'), findsOneWidget);
    expect(find.text(_l10n.pluginManagerReadOnlyManagement), findsOneWidget);

    // The locked bundle's switch cannot be moved; the experimantal one can.
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches.where((s) => s.onChanged == null), hasLength(1));
  });

  testWidgets('a bundle switch and a row switch call back with their target', (
    WidgetTester tester,
  ) async {
    final recorder = await _pump(
      tester,
      PluginManagerUiState(
        managementAvailable: true,
        bundles: <PluginBundle>[
          _bundle(
            enabled: true,
            rows: const <PluginBundleRow>[
              PluginBundleRow(
                rowId: 'core',
                moduleName: '@deepseek-ai/dsh-schedule',
                entryId: 'entry-1',
              ),
            ],
          ),
        ],
        plugins: const <PluginInfo>[
          PluginInfo(
            entryId: 'entry-1',
            moduleName: '@deepseek-ai/dsh-schedule',
            enabled: true,
            patchId: 'patch-1',
          ),
        ],
      ),
    );

    // The bundle switch is the first; the row switch sits behind the row
    // disclosure the reference only shows for an enabled bundle.
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(recorder.calls, contains('bundle:dsh-schedule:false'));

    await tester.tap(find.text(_l10n.pluginManagerRowsTitle(1)));
    await tester.pumpAndSettle();
    expect(find.text('@deepseek-ai/dsh-schedule'), findsOneWidget);
    await tester.tap(find.byType(Switch).last);
    await tester.pump();
    expect(recorder.calls, contains('row:entry-1:false'));
  });

  testWidgets('uninstall is the one confirmed action', (
    WidgetTester tester,
  ) async {
    final recorder = await _pump(
      tester,
      PluginManagerUiState(
        managementAvailable: true,
        bundles: <PluginBundle>[_bundle()],
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.pluginManagerUninstall).last);
    await tester.pumpAndSettle();

    // Nothing happens until the dialog is confirmed.
    expect(recorder.calls, isEmpty);
    expect(
      find.text(_l10n.pluginManagerUninstallTitle('dsh-schedule')),
      findsOneWidget,
    );

    await tester.tap(
      find.widgetWithText(FilledButton, _l10n.pluginManagerUninstall),
    );
    await tester.pumpAndSettle();
    expect(recorder.calls, <String>['uninstall:dsh-schedule']);
  });

  testWidgets('a refused install offers the build approval and retries', (
    WidgetTester tester,
  ) async {
    final recorder = await _pump(
      tester,
      const PluginManagerUiState(
        managementAvailable: true,
        install: PluginInstallState(
          stage: PluginInstallStage.failed,
          spec: 'some-plugin@1.0.0',
          error: PluginManagementError(
            code: PluginManagementErrorCode.invalidSpec,
            diagnostic: 'build scripts were not approved',
          ),
          pendingBuilds: <String>['some-plugin'],
        ),
      ),
    );

    expect(find.text('some-plugin@1.0.0'), findsOneWidget);
    expect(find.text(_l10n.pluginInstallFailed), findsOneWidget);
    expect(find.text('build scripts were not approved'), findsOneWidget);

    await tester.tap(find.text(_l10n.pluginInstallApproveBuilds));
    await tester.pump();
    expect(recorder.calls, <String>['approve']);
  });

  testWidgets('a running install shows its pushed progress and log', (
    WidgetTester tester,
  ) async {
    final recorder = await _pump(
      tester,
      const PluginManagerUiState(
        managementAvailable: true,
        install: PluginInstallState(
          stage: PluginInstallStage.running,
          spec: 'some-plugin@1.0.0',
          requestId: 'req-1',
          attempt: 'https://registry.npmmirror.com/ (1/2)',
          log: 'Progress: resolved 1\n',
        ),
      ),
    );

    // The stage label and the attempt share one line.
    expect(find.textContaining(_l10n.pluginInstallRunning), findsOneWidget);
    expect(find.textContaining('(1/2)'), findsOneWidget);
    expect(find.textContaining('resolved 1'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.tap(find.text(_l10n.cancel));
    await tester.pump();
    expect(recorder.calls, <String>['cancel']);
  });

  testWidgets('an unconfirmed install says so instead of guessing', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const PluginManagerUiState(
        managementAvailable: true,
        install: PluginInstallState(
          stage: PluginInstallStage.unconfirmed,
          spec: 'some-plugin@1.0.0',
          requestId: 'req-1',
        ),
      ),
    );

    // The reference keeps an unconfirmed attempt in its pending panel — the
    // host may still be installing — but the notice says the result is not
    // known rather than claiming progress.
    expect(find.text(_l10n.pluginInstallUnconfirmed), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('a done install offers activation and names the restart need', (
    WidgetTester tester,
  ) async {
    final recorder = await _pump(
      tester,
      const PluginManagerUiState(
        managementAvailable: true,
        install: PluginInstallState(
          stage: PluginInstallStage.done,
          spec: 'some-plugin@1.0.0',
          bundle: 'some-plugin',
          needsRestart: true,
        ),
      ),
    );

    expect(find.text(_l10n.pluginInstallDone), findsOneWidget);
    expect(find.text(_l10n.pluginInstallRestartRequired), findsOneWidget);

    await tester.tap(find.text(_l10n.pluginInstallEnableNow));
    await tester.pump();
    expect(recorder.calls, <String>['enableInstalled']);
  });
}
