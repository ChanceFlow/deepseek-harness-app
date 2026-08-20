/// TodoPanel + todo_write row tests — the web `TodoPanel.tsx` /
/// `todo-row.tsx` port rules.
library;

import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/todo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/todo_panel.dart';
import 'package:app/ui/chat/tool_row_model.dart';

void main() {
  testWidgets('empty list renders nothing; counts and items disclose', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TodoPanel(todos: [])),
      ),
    );
    expect(find.text('To-dos'), findsNothing);

    const todos = <TodoItem>[
      TodoItem(content: 'ship the fix', status: TodoStatus.inProgress),
      TodoItem(content: 'write tests', status: TodoStatus.completed),
      TodoItem(content: 'review', status: TodoStatus.pending),
    ];
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TodoPanel(todos: todos)),
      ),
    );

    // Web progressLabel: zero-count segments drop out.
    expect(find.text('1 completed · 1 active · 1 pending'), findsOneWidget);
    // The checklist stays behind the disclosure until tapped.
    expect(find.text('ship the fix'), findsNothing);

    await tester.tap(find.text('To-dos'));
    await tester.pumpAndSettle();
    expect(find.text('ship the fix'), findsOneWidget);
    expect(find.text('write tests'), findsOneWidget);
    expect(find.text('review'), findsOneWidget);
  });

  test('todo_write rows carry the plan summary and parallel suffix', () {
    final model = deriveToolRowModel(
      const TimelineToolCall(
        id: 'c1',
        name: 'todo_write',
        arguments:
            '{"todos":[{"content":"ship","status":"completed"},'
            '{"content":"audit A","status":"in_progress"},'
            '{"content":"audit B","status":"in_progress"},'
            '{"content":"review","status":"pending"}]}',
        result: 'Todos written',
        status: ToolRunStatus.completed,
      ),
    );
    expect(model.title, 'Update to-do list');
    expect(model.leading, Icons.checklist);
    expect(model.summary, '1/4 completed · audit A');
    expect(model.summarySuffix, '+1');
    // The receipt stays in the expanded output only.
    expect(model.output, 'Todos written');
  });

  test('a malformed todos arg falls back to the generic summary', () {
    final model = deriveToolRowModel(
      const TimelineToolCall(
        id: 'c2',
        name: 'todo_write',
        arguments: 'not json',
        status: ToolRunStatus.completed,
      ),
    );
    expect(model.title, 'Update to-do list');
    // Web TodoRow fallback = the generic row summary (others variant:
    // tool name · raw args).
    expect(model.summary, 'todo_write · not json');
    expect(model.summarySuffix, isNull);
  });

  testWidgets('the collapsed todo row shows the plan line only', (
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
              id: 'c3',
              name: 'todo_write',
              arguments:
                  '{"todos":[{"content":"ship","status":"completed"},'
                  '{"content":"audit","status":"in_progress"}]}',
              result: 'Todos written',
              status: ToolRunStatus.completed,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Update to-do list'), findsOneWidget);
    expect(find.text('1/2 completed · audit'), findsOneWidget);
    expect(find.text('+1'), findsNothing);
    expect(find.text('Todos written'), findsNothing);

    await tester.tap(find.text('Update to-do list'));
    await tester.pumpAndSettle();
    expect(find.text('Todos written'), findsOneWidget);
  });
}
