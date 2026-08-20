/// ToolRowModel tests — the web `toolRowModel` port rules
/// (ui-tool/src/client/tool/models/tool-call-model.ts).
library;

import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/tool_row_model.dart';

void main() {
  test(
    'unknown tools keep the Tool call title; the name rides the summary',
    () {
      // Web rule: variant others + no tool-owned title → summary prefix;
      // the summary takes the FIRST string arg (subagent_id), not the
      // message.
      final model = deriveToolRowModel(
        const TimelineToolCall(
          id: 'c1',
          name: 'send_message',
          arguments:
              '{"subagent_id":"s-9","message":"keep going and check the '
              'build then report back with details"}',
          result: 'message queued as the next turn for subagent s-9',
          status: ToolRunStatus.completed,
        ),
      );
      expect(model.title, 'Tool call');
      expect(model.variant, ToolRowVariant.others);
      // The collapsed summary quotes the ARGS, never the settled result.
      expect(model.summary, 'send_message · s-9');
      expect(model.summary, isNot(contains('queued')));
      // The message and the receipt live only in the expanded sections.
      expect(model.body, contains('keep going'));
      expect(model.output, 'message queued as the next turn for subagent s-9');
      expect(model.errorSummary, isNull);
    },
  );

  test('bash rows take the description then the command', () {
    final model = deriveToolRowModel(
      const TimelineToolCall(
        id: 'c2',
        name: 'bash',
        arguments: '{"command":"ls -la","description":"list the directory"}',
        result: 'total 0',
        status: ToolRunStatus.completed,
      ),
    );
    expect(model.title, 'Bash');
    expect(model.summary, 'list the directory');
    expect(model.body, contains('"command": "ls -la"'));
  });

  test('file tools surface the path and keep it out of the body-only flow', () {
    final model = deriveToolRowModel(
      const TimelineToolCall(
        id: 'c3',
        name: 'read',
        arguments: '{"path":"/ws/src/main.dart"}',
        result: 'void main() {}',
        status: ToolRunStatus.completed,
      ),
    );
    expect(model.title, 'Read');
    expect(model.summary, '/ws/src/main.dart');
    expect(model.filePath, '/ws/src/main.dart');
  });

  test('tool-owned titles refine the variant', () {
    final model = deriveToolRowModel(
      const TimelineToolCall(
        id: 'c4',
        name: 'pwsh',
        arguments: '{"command":"Get-ChildItem"}',
        status: ToolRunStatus.completed,
      ),
    );
    expect(model.title, 'Pwsh');
    expect(model.variant, ToolRowVariant.bash);
    // A tool-owned title suppresses the name prefix on the summary.
    expect(model.summary, 'Get-ChildItem');
  });

  test('error rows surface the failure first line, not the args', () {
    final model = deriveToolRowModel(
      const TimelineToolCall(
        id: 'c5',
        name: 'send_message',
        arguments: '{"subagent_id":"s-9","message":"hello"}',
        result: 'subagent not available\nit may have finished',
        isError: true,
        status: ToolRunStatus.failed,
      ),
    );
    expect(model.state, ToolRowState.error);
    expect(model.errorSummary, 'subagent not available');
  });

  testWidgets('the collapsed row quotes args, expanding reveals the result', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ToolCallRow(
            call: TimelineToolCall(
              id: 'c6',
              name: 'send_message',
              arguments: '{"subagent_id":"s-9","message":"keep going"}',
              result: 'message queued as the next turn for subagent s-9',
              status: ToolRunStatus.completed,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Tool call'), findsOneWidget);
    // Collapsed: the first string arg (subagent id) rides the summary.
    expect(find.text('send_message · s-9'), findsOneWidget);
    // The message and the queued receipt stay hidden until expansion.
    expect(find.textContaining('keep going'), findsNothing);
    expect(find.textContaining('queued as the next turn'), findsNothing);

    await tester.tap(find.text('Tool call'));
    await tester.pumpAndSettle();
    expect(find.textContaining('keep going'), findsOneWidget);
    expect(find.textContaining('queued as the next turn'), findsOneWidget);
  });
}
