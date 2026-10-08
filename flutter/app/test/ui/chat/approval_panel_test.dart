/// Approval card tests — the one-line row, its decision sheet, and
/// `commandOf()` (port of web `ApprovalPanel.tsx`).
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

  group('ApprovalRow and its decision sheet', () {
    const baseRequest = TimelineApprovalRequest(
      requestId: 'rpc-100',
      sessionId: 's-1',
      approvalId: 'ap-1',
      toolName: 'bash',
      reason: 'Delete build artifacts',
      callId: 'call-100',
    );

    Future<void> pumpRow(
      WidgetTester tester, {
      TimelineApprovalRequest request = baseRequest,
      String? command,
      List<ChatAction>? actions,
      Locale? locale,
      ThemeData? theme,
    }) async {
      await tester.pumpWidget(
        l10nApp(
          locale: locale,
          theme: theme,
          home: Scaffold(
            body: ApprovalRow(
              request: request,
              command: command,
              onAction: (action) => actions?.add(action),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    /// Opens the request's own surface: the card row is one line, the body is
    /// one surface deeper. [title] is the locale's own `waitingForApproval`.
    Future<void> openSheet(
      WidgetTester tester, {
      String title = 'Waiting for approval',
    }) async {
      await tester.tap(find.text(title));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    /// Takes the open sheet down: the next pump may reuse the same Navigator,
    /// and a sheet left up would answer the next iteration's finders.
    Future<void> closeSheet(WidgetTester tester) async {
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('the card is one line and the command opens deeper', (
      tester,
    ) async {
      final actions = <ChatAction>[];
      await pumpRow(tester, command: 'rm -rf build', actions: actions);

      // The row: the wait, the justification's own line, and the primary
      // answer. Neither the command nor Reject is on the transcript.
      expect(find.text('Waiting for approval'), findsOneWidget);
      expect(find.text('Delete build artifacts'), findsOneWidget);
      expect(find.text('Allow once'), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
      expect(find.text('Reject'), findsNothing);
      expect(
        find.text('Tool bash requests privileged execution'),
        findsNothing,
      );

      await openSheet(tester);
      expect(find.text('rm -rf build'), findsOneWidget);
      expect(
        find.text('Tool bash requests privileged execution'),
        findsOneWidget,
      );
      expect(find.text('Reject'), findsOneWidget);
      expect(actions, isEmpty, reason: 'opening the request answers nothing');

      final selectable = tester.widget<SelectableText>(
        find.widgetWithText(SelectableText, 'rm -rf build'),
      );
      expect(selectable.style?.fontFamily, kCodeFontFamily);
      await closeSheet(tester);
    });

    testWidgets('renders without command when command is null or empty', (
      tester,
    ) async {
      await pumpRow(tester, command: null);

      expect(find.text('Waiting for approval'), findsOneWidget);
      expect(find.text('Delete build artifacts'), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);

      await openSheet(tester);
      expect(
        find.text('Tool bash requests privileged execution'),
        findsOneWidget,
      );
      expect(find.byType(SelectableText), findsNothing);
      await closeSheet(tester);
    });

    testWidgets('dispatches RespondApproval with allowed true on Allow once', (
      tester,
    ) async {
      final actions = <ChatAction>[];
      await pumpRow(tester, command: 'cargo build', actions: actions);

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
      await pumpRow(tester, command: 'cargo build', actions: actions);
      await openSheet(tester);

      await tester.tap(find.text('Reject'));
      await tester.pump();
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
      final l10nZh = lookupAppLocalizations(const Locale('zh'));
      // No reason: the row's summary is the fallback ticket the host's missing
      // reason renders through.
      const reasonless = TimelineApprovalRequest(
        requestId: 'rpc-zh',
        sessionId: 's-zh',
        approvalId: 'ap-zh',
        toolName: 'bash',
        callId: 'call-zh',
      );
      await pumpRow(
        tester,
        request: reasonless,
        command: 'pnpm test',
        locale: const Locale('zh'),
      );

      expect(find.text(l10nZh.approveToolFallback('bash')), findsOneWidget);
      expect(find.text(l10nZh.waitingForApproval), findsOneWidget);

      await openSheet(tester, title: l10nZh.waitingForApproval);
      expect(find.text(l10nZh.waitingForApproval), findsWidgets);
      expect(find.text(l10nZh.toolRequestsPrivileged('bash')), findsOneWidget);
      expect(find.text('pnpm test'), findsOneWidget);
      expect(find.text(l10nZh.allowOnce), findsWidgets);
      expect(find.text(l10nZh.reject), findsOneWidget);
    });

    testWidgets('renders under light and dark theme using scheme roles', (
      tester,
    ) async {
      for (final theme in [DshTheme.light(), DshTheme.dark()]) {
        await pumpRow(tester, command: 'git status', theme: theme);
        expect(find.text('git status'), findsNothing);
        expect(find.text('Waiting for approval'), findsOneWidget);

        await openSheet(tester);
        expect(find.text('git status'), findsOneWidget);
        expect(find.text('Waiting for approval'), findsWidgets);

        // The next iteration mounts its tree over the same Navigator.
        await closeSheet(tester);
      }
    });
  });
}
