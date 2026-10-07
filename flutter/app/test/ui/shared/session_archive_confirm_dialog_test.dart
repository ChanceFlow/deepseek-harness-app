/// Stop-and-archive confirmation tests: the reference's dialog that answers a
/// Host refusal over a session's running work — the work list it names, the
/// in-flight state that closes the dialog to dismissal, the inline error that
/// keeps it open, and the settlement that closes it.
library;

import 'dart:async';

import 'package:app/notifications/session_notice.dart';
import 'package:app/ui/shared/session_archive_confirm_dialog.dart';
import 'package:domain/model/session_archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

const _request = SessionArchiveRequest(
  backendId: 'b1',
  sessionId: 's1',
  displayTitle: 'Refactor the parser',
  activity: <SessionActivityEntry>[
    SessionActivityEntry(kind: SessionActivityKind.turn, rawKind: 'turn'),
    SessionActivityEntry(
      kind: SessionActivityKind.job,
      rawKind: 'job',
      items: <SessionActivityItem>[
        SessionActivityItem(id: 'job-1', label: 'build'),
        SessionActivityItem(id: 'job-2'),
      ],
    ),
    SessionActivityEntry(
      kind: SessionActivityKind.other,
      rawKind: 'workflow',
      items: <SessionActivityItem>[SessionActivityItem(id: 'wf-1')],
    ),
  ],
);

/// Opens the dialog from a real button press so it rides a real route (the
/// dialog pops itself on success, which a bare `home:` mount cannot do).
Future<void> _open(
  WidgetTester tester, {
  required Future<void> Function() onConfirm,
  VoidCallback? onArchived,
}) async {
  await tester.pumpWidget(
    l10nApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => SessionArchiveConfirmDialog(
                request: _request,
                onConfirm: onConfirm,
                onArchived: onArchived ?? () {},
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('names the session and every reported family with its items', (
    tester,
  ) async {
    await _open(tester, onConfirm: () async {});

    expect(find.text('Stop and archive this session?'), findsOneWidget);
    expect(
      find.textContaining('Refactor the parser'),
      findsOneWidget,
      reason: 'the body names the row the user tried to archive',
    );
    expect(find.text('Work that will be stopped'), findsOneWidget);
    expect(find.text('The turn in progress'), findsOneWidget);
    expect(find.text('2 background jobs: build, job-2'), findsOneWidget);
    expect(
      find.text('1 other item of work (workflow)'),
      findsOneWidget,
      reason: 'a family this program did not compile keeps its wire spelling',
    );
  });

  testWidgets('confirming archives, reports the outcome, and closes', (
    tester,
  ) async {
    var confirmed = 0;
    var archived = 0;
    await _open(
      tester,
      onConfirm: () async => confirmed++,
      onArchived: () => archived++,
    );

    await tester.tap(find.text('Stop and archive'));
    await tester.pumpAndSettle();

    expect(confirmed, 1);
    expect(archived, 1);
    expect(find.text('Stop and archive this session?'), findsNothing);
  });

  testWidgets('a call in flight shows the pending line and refuses to close', (
    tester,
  ) async {
    final gate = Completer<void>();
    await _open(tester, onConfirm: () => gate.future);

    await tester.tap(find.text('Stop and archive'));
    await tester.pump();

    expect(find.text('Stopping and archiving…'), findsOneWidget);
    // Cancel and the back gesture are inert while the Host may already be
    // stopping work.
    final cancel = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Cancel'),
    );
    expect(cancel.onPressed, isNull);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Stop and archive this session?'), findsNothing);
  });

  testWidgets('a rejection stays in the dialog and keeps it open', (
    tester,
  ) async {
    await _open(
      tester,
      onConfirm: () async => throw StateError('host refused again'),
    );

    await tester.tap(find.text('Stop and archive'));
    await tester.pumpAndSettle();

    expect(find.text('Stop and archive this session?'), findsOneWidget);
    expect(find.textContaining('host refused again'), findsOneWidget);
    expect(
      find.text('Stopping and archiving…'),
      findsNothing,
      reason: 'a settled failure leaves the pending state',
    );
  });

  testWidgets('cancel closes without asking the Host', (tester) async {
    var confirmed = 0;
    await _open(tester, onConfirm: () async => confirmed++);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(confirmed, 0);
    expect(find.text('Stop and archive this session?'), findsNothing);
  });
}
