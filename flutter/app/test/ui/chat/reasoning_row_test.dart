/// ReasoningRow parity tests — port of the web Think disclosure.
library;

import 'package:domain/model/chat_message.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';

Future<void> _pump(
  WidgetTester tester,
  ChatUiState uiState,
  List<ChatAction> actions,
) {
  tester.view.physicalSize = const Size(800, 1280);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    MaterialApp(
      home: ChatScreen(uiState: uiState, onAction: actions.add),
    ),
  );
}

ChatMessage _message({String? reasoning, bool streaming = false}) {
  return ChatMessage(
    id: 'm1',
    sessionId: 's1',
    role: MessageRole.assistant,
    text: 'the answer',
    reasoning: reasoning,
    streaming: streaming,
  );
}

void main() {
  testWidgets('collapsed row shows Think with the first-line summary', (
    tester,
  ) async {
    await _pump(
      tester,
      ChatUiState(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha', blank: false),
        ],
        selectedSessionId: 's1',
        timeline: [
          TimelineMessage(
            _message(reasoning: 'consider the options\ncarefully weigh them'),
          ),
        ],
      ),
      [],
    );

    expect(find.text('Think'), findsOneWidget);
    expect(find.text('consider the options'), findsOneWidget);
    expect(find.text('carefully weigh them'), findsNothing);
  });

  testWidgets('tap expands the full body and collapses again', (tester) async {
    await _pump(
      tester,
      ChatUiState(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha', blank: false),
        ],
        selectedSessionId: 's1',
        timeline: [
          TimelineMessage(
            _message(reasoning: 'consider the options\ncarefully weigh them'),
          ),
        ],
      ),
      [],
    );

    await tester.tap(find.text('Think'));
    await tester.pumpAndSettle();
    expect(
      find.text('consider the options\ncarefully weigh them'),
      findsOneWidget,
    );
    expect(find.text('consider the options'), findsNothing);

    await tester.tap(find.text('Think'));
    await tester.pumpAndSettle();
    expect(find.text('consider the options'), findsOneWidget);
    expect(
      find.text('consider the options\ncarefully weigh them'),
      findsNothing,
    );
  });

  testWidgets('streaming tail follows the latest line and marks running', (
    tester,
  ) async {
    await _pump(
      tester,
      ChatUiState(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha', blank: false),
        ],
        selectedSessionId: 's1',
        timeline: [
          TimelineMessage(
            _message(
              reasoning: 'first thought\nsecond thought\nstill going',
              streaming: true,
            ),
          ),
        ],
      ),
      [],
    );

    // Running rows summarize the latest non-empty line.
    expect(find.text('still going'), findsOneWidget);
    expect(find.text('first thought'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('Running', caseSensitive: false)),
      findsOneWidget,
    );
  });

  testWidgets('messages without reasoning render no disclosure', (
    tester,
  ) async {
    await _pump(
      tester,
      ChatUiState(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha', blank: false),
        ],
        selectedSessionId: 's1',
        timeline: [TimelineMessage(_message())],
      ),
      [],
    );
    expect(find.text('Think'), findsNothing);
  });
}
