/// Presented-files row widget tests — the 交付文件 cards a finished turn
/// closes with, driven through the real chat surface.
library;

import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/file_preview_sheet.dart';
import 'package:app/ui/chat/presented_files_row.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

int _nextId = 0;

TimelineToolCall _present(List<PresentedFile> files) {
  _nextId += 1;
  return TimelineToolCall(
    id: 'call-$_nextId',
    name: 'present',
    arguments: '{"files":[]}',
    status: ToolRunStatus.completed,
    presentedFiles: files,
  );
}

TimelineMessage _assistant({String id = 'm1'}) => TimelineMessage(
  ChatMessage(
    id: id,
    sessionId: 's1',
    role: MessageRole.assistant,
    text: 'done',
  ),
);

Future<void> _pump(WidgetTester tester, List<TimelineItem> timeline) async {
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
              const SessionSummary(id: 's1', title: 'Alpha', blank: false),
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
  testWidgets('a finished turn shows one card per declared file', (
    tester,
  ) async {
    await _pump(tester, <TimelineItem>[
      const TimelineTurnBoundary(1),
      _present(const <PresentedFile>[
        PresentedFile(path: 'out/hero.png', description: 'Rendered hero'),
        PresentedFile(path: 'out/report.pdf'),
      ]),
      _assistant(),
    ]);

    expect(find.byType(PresentedFilesRow), findsOneWidget);
    // Twice: the row's caption and the present call's own row title.
    expect(find.text('Present files'), findsWidgets);
    expect(find.text('hero.png'), findsOneWidget);
    expect(find.text('Rendered hero'), findsOneWidget);
    // No description: the uppercased extension stands in.
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
  });

  testWidgets('a declared file with no extension falls back to the file word', (
    tester,
  ) async {
    await _pump(tester, <TimelineItem>[
      const TimelineTurnBoundary(1),
      _present(const <PresentedFile>[PresentedFile(path: 'out/LICENSE')]),
      _assistant(),
    ]);

    expect(find.text('LICENSE'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
  });

  testWidgets('the open seat opens the in-app preview sheet', (tester) async {
    await _pump(tester, <TimelineItem>[
      const TimelineTurnBoundary(1),
      _present(const <PresentedFile>[PresentedFile(path: 'out/hero.png')]),
      _assistant(),
    ]);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(FilePreviewSheet), findsOneWidget);
  });

  testWidgets('tapping the card itself opens the preview too', (tester) async {
    await _pump(tester, <TimelineItem>[
      const TimelineTurnBoundary(1),
      _present(const <PresentedFile>[PresentedFile(path: 'out/hero.png')]),
      _assistant(),
    ]);

    await tester.tap(find.text('hero.png'));
    await tester.pumpAndSettle();

    expect(find.byType(FilePreviewSheet), findsOneWidget);
  });

  testWidgets('more than four files collapse behind the localized toggle', (
    tester,
  ) async {
    await _pump(tester, <TimelineItem>[
      const TimelineTurnBoundary(1),
      _present(<PresentedFile>[
        for (int i = 0; i < 6; i++) PresentedFile(path: 'out/f$i.png'),
      ]),
      _assistant(),
    ]);

    expect(find.byType(PresentedFilesRow), findsOneWidget);
    expect(find.text('f3.png'), findsOneWidget);
    expect(find.text('f4.png'), findsNothing);
    expect(find.text('All 6 files'), findsOneWidget);

    await tester.tap(find.text('All 6 files'));
    await tester.pumpAndSettle();

    expect(find.text('f5.png'), findsOneWidget);
    expect(find.text('Collapse'), findsOneWidget);
  });

  testWidgets('a present call also renders its own transcript row', (
    tester,
  ) async {
    await _pump(tester, <TimelineItem>[
      const TimelineTurnBoundary(1),
      const TimelineToolCall(
        id: 'present-1',
        name: 'present',
        arguments: '{"files":[{"path":"out/hero.png"},{"path":"out/two.png"}]}',
        status: ToolRunStatus.completed,
        presentedFiles: <PresentedFile>[PresentedFile(path: 'out/hero.png')],
      ),
      _assistant(),
    ]);

    // The row's title, and its summary as the declared paths comma-joined.
    expect(find.text('Present files'), findsWidgets);
    expect(find.text('out/hero.png, out/two.png'), findsOneWidget);
  });
}
