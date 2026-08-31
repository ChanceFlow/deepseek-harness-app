/// ApprovalPanel widget & command extraction tests — port of web
/// `ApprovalPanel.tsx` / `commandOf()`.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/chat/approval_panel.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

void main() {
  group('commandOf', () {
    test('extracts command from json arguments with command string', () {
      const call = TimelineToolCall(
        id: 'call-1',
        name: 'bash',
        arguments: '{"command":"rm -rf build"}',
      );
      expect(commandOf(call), 'rm -rf build');
    });

    test('extracts command when arguments has extra fields', () {
      const call = TimelineToolCall(
        id: 'call-2',
        name: 'bash',
        arguments: '{"command":"echo hello","description":"Run greeting","timeout":5000}',
      );
      expect(commandOf(call), 'echo hello');
    });

    test('returns null when tool call is null', () {
      expect(commandOf(null), isNull);
    });

    test('returns null when arguments is null or empty', () {
      const callNull = TimelineToolCall(id: 'c1', name: 'bash');
      const callEmpty = TimelineToolCall(id: 'c2', name: 'bash', arguments: '');
      expect(commandOf(callNull), isNull);
      expect(commandOf(callEmpty), isNull);
    });

    test('returns null for unparseable / non-json raw arguments', () {
      const call = TimelineToolCall(
        id: 'c3',
        name: 'bash',
        arguments: 'ls -la',
      );
      expect(commandOf(call), isNull);
    });

    test('returns null for non-shell tool args without command field', () {
      const call = TimelineToolCall(
        id: 'c4',
        name: 'write',
        arguments: '{"file_path":"test.txt","content":"hello"}',
      );
      expect(commandOf(call), isNull);
    });

    test('returns null for empty or non-string command field', () {
      const callEmpty = TimelineToolCall(
        id: 'c5',
        name: 'bash',
        arguments: '{"command":""}',
      );
      const callNonStr = TimelineToolCall(
        id: 'c6',
        name: 'bash',
        arguments: '{"command":123}',
      );
      expect(commandOf(callEmpty), isNull);
      expect(commandOf(callNonStr), isNull);
    });
  });

  group('ApprovalPanel widget', () {
    const request = TimelineApprovalRequest(
      requestId: 'rpc-100',
      sessionId: 's-1',
      approvalId: 'ap-1',
      toolName: 'bash',
      reason: 'Delete build artifacts',
      callId: 'call-100',
    );

    testWidgets('renders command in monospace SelectableText when provided', (
      tester,
    ) async {
      final actions = <ChatAction>[];
      await tester.pumpWidget(
        l10nApp(
          home: Scaffold(
            body: ApprovalPanel(
              request: request,
              command: 'rm -rf build',
              onAction: actions.add,
            ),
          ),
        ),
      );

      expect(find.text('Waiting for approval'), findsOneWidget);
      expect(find.text('Delete build artifacts'), findsOneWidget);
      expect(
        find.text('Tool bash requests privileged execution'),
        findsOneWidget,
      );
      expect(find.text('rm -rf build'), findsOneWidget);

      final selectable = tester.widget<SelectableText>(
        find.widgetWithText(SelectableText, 'rm -rf build'),
      );
      expect(selectable.style?.fontFamily, 'monospace');
    });

    testWidgets('renders without command when command is null or empty', (
      tester,
    ) async {
      final actions = <ChatAction>[];
      await tester.pumpWidget(
        l10nApp(
          home: Scaffold(
            body: ApprovalPanel(
              request: request,
              command: null,
              onAction: actions.add,
            ),
          ),
        ),
      );

      expect(find.text('Waiting for approval'), findsOneWidget);
      expect(find.text('Delete build artifacts'), findsOneWidget);
      expect(
        find.text('Tool bash requests privileged execution'),
        findsOneWidget,
      );
      expect(find.byType(SelectableText), findsNothing);
    });

    testWidgets('dispatches RespondApproval with allowed true on Allow once', (
      tester,
    ) async {
      final actions = <ChatAction>[];
      await tester.pumpWidget(
        l10nApp(
          home: Scaffold(
            body: ApprovalPanel(
              request: request,
              command: 'cargo build',
              onAction: actions.add,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Allow once'));
      expect(actions, hasLength(1));
      expect(
        actions.single,
        const RespondApproval(
          requestId: 'rpc-100',
          approvalId: 'ap-1',
          allowed: true,
        ),
      );
    });

    testWidgets('dispatches RespondApproval with allowed false on Reject', (
      tester,
    ) async {
      final actions = <ChatAction>[];
      await tester.pumpWidget(
        l10nApp(
          home: Scaffold(
            body: ApprovalPanel(
              request: request,
              command: 'cargo build',
              onAction: actions.add,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Reject'));
      expect(actions, hasLength(1));
      expect(
        actions.single,
        const RespondApproval(
          requestId: 'rpc-100',
          approvalId: 'ap-1',
          allowed: false,
        ),
      );
    });

    testWidgets('renders correctly under Chinese locale', (tester) async {
      final actions = <ChatAction>[];
      await tester.pumpWidget(
        l10nApp(
          locale: const Locale('zh'),
          home: Scaffold(
            body: ApprovalPanel(
              request: const TimelineApprovalRequest(
                requestId: 'rpc-zh',
                sessionId: 's-zh',
                approvalId: 'ap-zh',
                toolName: 'bash',
                callId: 'call-zh',
              ),
              command: 'pnpm test',
              onAction: actions.add,
            ),
          ),
        ),
      );

      final l10nZh = lookupAppLocalizations(const Locale('zh'));
      expect(find.text(l10nZh.waitingForApproval), findsOneWidget);
      expect(find.text(l10nZh.approveToolFallback('bash')), findsOneWidget);
      expect(find.text(l10nZh.toolRequestsPrivileged('bash')), findsOneWidget);
      expect(find.text('pnpm test'), findsOneWidget);
      expect(find.text(l10nZh.allowOnce), findsOneWidget);
      expect(find.text(l10nZh.reject), findsOneWidget);
    });

    testWidgets('renders under light and dark theme using scheme roles', (
      tester,
    ) async {
      for (final theme in [DshTheme.light(), DshTheme.dark()]) {
        await tester.pumpWidget(
          l10nApp(
            theme: theme,
            home: Scaffold(
              body: ApprovalPanel(
                request: request,
                command: 'git status',
                onAction: (_) {},
              ),
            ),
          ),
        );
        expect(find.text('git status'), findsOneWidget);
        expect(find.text('Waiting for approval'), findsOneWidget);
      }
    });
  });
}
