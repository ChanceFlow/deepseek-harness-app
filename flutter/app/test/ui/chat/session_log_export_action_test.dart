/// Session-log export tests: the header seat and the `/export` command run
/// the real [ChatController] over the shared fake repository, so the
/// success and failure notices a user sees are produced by the production
/// path (download seam → platform save step → uiState → snack bar).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:domain/model/session.dart';
import 'package:domain/model/session_log_export.dart';
import 'package:domain/repository/session_log_export_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/chat/chat_controller.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/command_roster.dart';
import 'package:app/ui/chat/session_log_export_action.dart';

import '../../l10n_app.dart';
import 'chat_controller_test.dart' show FakeChatRepository;

/// The archive server a test pretends to talk to; [gate] holds the download
/// open so the in-progress seat is observable, [failure] makes it throw.
class _FakeExportRepository implements SessionLogExportRepository {
  _FakeExportRepository(this.archive);

  final SessionLogExport archive;
  Object? failure;
  Completer<void>? gate;
  final List<String> requested = <String>[];

  @override
  Future<SessionLogExport> exportSessionLog(
    String sessionId, {
    bool includeDescendants = true,
  }) async {
    requested.add(sessionId);
    final pending = gate;
    if (pending != null) await pending.future;
    final error = failure;
    if (error != null) throw error;
    return archive;
  }
}

/// The platform write step: records what it was handed and answers with the
/// location a user would see (or throws).
class _RecordingSaver {
  /// The location the fake platform step answers with.
  String location = 'Download/dsh-session-session-1.zip';
  Object? failure;
  final List<({String filename, Uint8List bytes})> calls =
      <({String filename, Uint8List bytes})>[];

  Future<String> call({
    required String filename,
    required Uint8List bytes,
  }) async {
    calls.add((filename: filename, bytes: bytes));
    final error = failure;
    if (error != null) throw error;
    return location;
  }
}

final _archiveBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

/// One harness: the real controller over the shared fake repository, the
/// fake archive seam, and the recording save step, all rendered through the
/// header seat a real header would mount.
({ChatController controller, _RecordingSaver saver, Widget host}) _harness({
  required _FakeExportRepository exports,
  _RecordingSaver? saver,
  bool composeExport = true,
}) {
  final repository = FakeChatRepository(
    initialSessions: const <SessionSummary>[
      SessionSummary(id: 'session-1', title: 'Test session'),
    ],
  );
  final writeStep = saver ?? _RecordingSaver();
  final controller = ChatController(
    repository,
    sessionLogExport: composeExport ? exports : null,
    saveSessionLog: writeStep.call,
  );
  return (
    controller: controller,
    saver: writeStep,
    host: l10nApp(
      home: Scaffold(
        body: StreamBuilder<ChatUiState>(
          stream: controller.uiState,
          builder: (context, snapshot) => SessionLogExportAction(
            uiState: snapshot.data ?? const ChatUiState(),
            onAction: controller.onAction,
          ),
        ),
      ),
    ),
  );
}

Future<void> _selectSession(
  WidgetTester tester,
  ChatController controller,
) async {
  controller.onAction(const SelectSession('session-1'));
  // Two frames plus the controller's upstream publish window, so no
  // coalescing timer is left pending at teardown.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 40));
}

void main() {
  testWidgets('no seat is offered without an export seam', (tester) async {
    final run = _harness(
      exports: _FakeExportRepository(
        SessionLogExport(filename: 'x.zip', bytes: _archiveBytes),
      ),
      composeExport: false,
    );
    addTearDown(run.controller.dispose);
    await tester.pumpWidget(run.host);
    await _selectSession(tester, run.controller);

    expect(find.byIcon(Icons.save_alt), findsNothing);
  });

  testWidgets('a successful export names where the archive landed', (
    tester,
  ) async {
    final exports = _FakeExportRepository(
      SessionLogExport(
        filename: 'dsh-session-session-1.zip',
        bytes: _archiveBytes,
      ),
    );
    final run = _harness(exports: exports);
    addTearDown(run.controller.dispose);
    await tester.pumpWidget(run.host);
    await _selectSession(tester, run.controller);

    expect(find.byTooltip('Download session log'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.save_alt));
    await tester.pumpAndSettle();

    expect(exports.requested, <String>['session-1']);
    expect(run.saver.calls, hasLength(1));
    expect(run.saver.calls.single.filename, 'dsh-session-session-1.zip');
    expect(run.saver.calls.single.bytes, _archiveBytes);
    expect(
      find.text('Session log saved to Download/dsh-session-session-1.zip'),
      findsOneWidget,
    );
  });

  testWidgets('the seat reports progress while the archive streams', (
    tester,
  ) async {
    final exports = _FakeExportRepository(
      SessionLogExport(
        filename: 'dsh-session-session-1.zip',
        bytes: _archiveBytes,
      ),
    )..gate = Completer<void>();
    final run = _harness(exports: exports);
    addTearDown(run.controller.dispose);
    await tester.pumpWidget(run.host);
    await _selectSession(tester, run.controller);

    await tester.tap(find.byIcon(Icons.save_alt));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.save_alt), findsNothing);

    exports.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text('Session log saved to Download/dsh-session-session-1.zip'),
      findsOneWidget,
    );
  });

  testWidgets('a failed export reports the localized failure', (tester) async {
    final exports = _FakeExportRepository(
      SessionLogExport(filename: 'x.zip', bytes: _archiveBytes),
    )..failure = StateError('HTTP 404 for /api/session.export');
    final saver = _RecordingSaver()..failure = StateError('disk full');
    final run = _harness(exports: exports, saver: saver);
    addTearDown(run.controller.dispose);
    await tester.pumpWidget(run.host);
    await _selectSession(tester, run.controller);

    await tester.tap(find.byIcon(Icons.save_alt));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't export the session log"), findsOneWidget);
    expect(find.textContaining('saved to'), findsNothing);
    // The transport cause stays out of the user-facing line.
    expect(find.textContaining('HTTP 404'), findsNothing);
  });

  testWidgets('a bare /export runs the download instead of the host command', (
    tester,
  ) async {
    final repository = FakeChatRepository(
      initialSessions: const <SessionSummary>[
        SessionSummary(id: 'session-1', title: 'Test session'),
      ],
    );
    final exports = _FakeExportRepository(
      SessionLogExport(
        filename: 'dsh-session-session-1.zip',
        bytes: _archiveBytes,
      ),
    );
    final controller = ChatController(
      repository,
      sessionLogExport: exports,
      saveSessionLog: _RecordingSaver().call,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      l10nApp(
        home: Scaffold(
          body: StreamBuilder<ChatUiState>(
            stream: controller.uiState,
            builder: (context, snapshot) => SessionLogExportAction(
              uiState: snapshot.data ?? const ChatUiState(),
              onAction: controller.onAction,
            ),
          ),
        ),
      ),
    );
    await _selectSession(tester, controller);

    bool? settled;
    controller.onAction(
      SendPrompt('/export', onSettled: (accepted) => settled = accepted),
    );
    await tester.pumpAndSettle();

    expect(settled, isTrue);
    expect(exports.requested, <String>['session-1']);
    // The host's own handler only acknowledges the request, so nothing may
    // ride `commands/execute` for this line.
    expect(repository.commandDispatchImages, isEmpty);
    expect(find.text("Couldn't export the session log"), findsNothing);
  });

  testWidgets('/export with args keeps the roster bare-only rule', (
    tester,
  ) async {
    final repository = FakeChatRepository(
      initialSessions: const <SessionSummary>[
        SessionSummary(id: 'session-1', title: 'Test session'),
      ],
    );
    final exports = _FakeExportRepository(
      SessionLogExport(filename: 'x.zip', bytes: _archiveBytes),
    );
    final controller = ChatController(
      repository,
      sessionLogExport: exports,
      saveSessionLog: _RecordingSaver().call,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      l10nApp(
        home: Scaffold(
          body: StreamBuilder<ChatUiState>(
            stream: controller.uiState,
            builder: (context, snapshot) => SessionLogExportAction(
              uiState: snapshot.data ?? const ChatUiState(),
              onAction: controller.onAction,
            ),
          ),
        ),
      ),
    );
    await _selectSession(tester, controller);

    controller.onAction(const SendPrompt('/export /tmp/out.zip'));
    await tester.pumpAndSettle();

    expect(exports.requested, isEmpty);
    expect(repository.sentMessages, hasLength(1));
    expect(repository.sentMessages.single.text, '/export /tmp/out.zip');
  });

  test('the composer roster advertises the export command', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final command = hostCommands(l10n).firstWhere((c) => c.name == 'export');
    expect(command.description, 'Download this session log as a ZIP archive');
    expect(command.hint, isNull);
    expect(command.acceptsImages, isFalse);
    expect(isBareSessionLogExport('/export'), isTrue);
    expect(isBareSessionLogExport('/export now'), isFalse);
  });
}
