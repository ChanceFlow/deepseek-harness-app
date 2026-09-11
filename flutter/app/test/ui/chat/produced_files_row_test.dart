/// Produced-files row widget tests — the chip lane a finished turn closes
/// with, driven through the real chat surface.
library;

import 'dart:convert';

import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/file_preview_sheet.dart';
import 'package:app/ui/chat/produced_files_row.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

int _nextId = 0;

TimelineToolCall _write(String path, {bool failed = false}) {
  _nextId += 1;
  return TimelineToolCall(
    id: 'call-$_nextId',
    name: 'write',
    arguments: jsonEncode(<String, Object?>{'file_path': path, 'content': 'x'}),
    status: failed ? ToolRunStatus.failed : ToolRunStatus.completed,
    isError: failed,
  );
}

TimelineMessage _assistant({
  String id = 'm1',
  bool streaming = false,
  String text = 'done',
}) => TimelineMessage(
  ChatMessage(
    id: id,
    sessionId: 's1',
    role: MessageRole.assistant,
    text: text,
    streaming: streaming,
  ),
);

Future<void> _pump(
  WidgetTester tester,
  List<TimelineItem> timeline, {
  bool running = false,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: l10nApp(
        home: ChatScreen(
          uiState: ChatUiState(
            sessions: <SessionSummary>[
              SessionSummary(
                id: 's1',
                title: 'Alpha',
                blank: false,
                running: running,
              ),
            ],
            selectedSessionId: 's1',
            timeline: timeline,
          ),
          onAction: (_) {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a finished turn shows the basenames it produced', (
    tester,
  ) async {
    await _pump(tester, <TimelineItem>[
      const TimelineTurnBoundary(1),
      _write('lib/a.dart'),
      _write('lib/nested/b.dart'),
      _assistant(),
    ]);

    expect(find.byType(ProducedFilesRow), findsOneWidget);
    expect(find.text('Files changed'), findsOneWidget);
    expect(find.text('a.dart'), findsOneWidget);
    expect(find.text('b.dart'), findsOneWidget);
  });

  testWidgets('tapping a chip opens the in-app preview sheet', (tester) async {
    await _pump(tester, <TimelineItem>[
      const TimelineTurnBoundary(1),
      _write('lib/a.dart'),
      _assistant(),
    ]);

    await tester.tap(find.text('a.dart'));
    await tester.pumpAndSettle();

    expect(find.byType(FilePreviewSheet), findsOneWidget);
  });

  testWidgets('more than six files collapse into the localized counter', (
    tester,
  ) async {
    await _pump(tester, <TimelineItem>[
      const TimelineTurnBoundary(1),
      for (int i = 0; i < 8; i++) _write('lib/f$i.dart'),
      _assistant(),
    ]);

    expect(find.byType(ProducedFilesRow), findsOneWidget);
    for (int i = 0; i < ProducedFilesRow.shownLimit; i++) {
      expect(find.text('f$i.dart'), findsOneWidget);
    }
    expect(find.text('f6.dart'), findsNothing);
    expect(find.text('+ 2 files'), findsOneWidget);
  });

  testWidgets('a failed write contributes no row', (tester) async {
    await _pump(tester, <TimelineItem>[
      const TimelineTurnBoundary(1),
      _write('lib/a.dart', failed: true),
      _assistant(),
    ]);

    expect(find.byType(ProducedFilesRow), findsNothing);
  });

  testWidgets('a streaming reply shows no produced row yet', (tester) async {
    await _pump(tester, <TimelineItem>[
      const TimelineTurnBoundary(1),
      _write('lib/a.dart'),
      _assistant(streaming: true),
    ]);

    expect(find.byType(ProducedFilesRow), findsNothing);
  });

  testWidgets('a running session hides only the newest turn row', (
    tester,
  ) async {
    await _pump(tester, <TimelineItem>[
      const TimelineTurnBoundary(1),
      _write('lib/a.dart'),
      _assistant(id: 'm1'),
      const TimelineTurnBoundary(2),
      _write('lib/b.dart'),
      _assistant(id: 'm2'),
    ], running: true);

    // The closed first turn keeps its row; the running turn's row waits for
    // the session to settle.
    expect(find.text('a.dart'), findsOneWidget);
    expect(find.text('b.dart'), findsNothing);
  });
}
