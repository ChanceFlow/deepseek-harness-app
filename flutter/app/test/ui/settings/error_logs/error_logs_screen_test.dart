import 'package:app/logging/error_log_entry.dart';
import 'package:app/ui/settings/error_logs/error_logs_screen.dart';
import 'package:app/ui/settings/error_logs/error_logs_ui_state.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../l10n_app.dart';

void main() {
  group('ErrorLogsScreen Widget Tests', () {
    testWidgets('renders empty state when there are no errors', (
      WidgetTester tester,
    ) async {
      const ErrorLogsUiState state = ErrorLogsUiState();

      // Light theme
      await tester.pumpWidget(
        l10nApp(
          theme: DshTheme.light(),
          home: ErrorLogsScreen(uiState: state, onAction: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Error Logs'), findsOneWidget);
      expect(find.text('No Error Logs'), findsOneWidget);
      expect(find.text('System & Build Info'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

      // Dark theme
      await tester.pumpWidget(
        l10nApp(
          theme: DshTheme.dark(),
          home: ErrorLogsScreen(uiState: state, onAction: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No Error Logs'), findsOneWidget);
    });

    testWidgets('renders error cards with severity pills and system info', (
      WidgetTester tester,
    ) async {
      final List<ErrorLogEntry> entries = <ErrorLogEntry>[
        ErrorLogEntry(
          id: 'err_1',
          timestamp: DateTime(2026, 8, 20, 14, 0, 0),
          level: ErrorLogLevel.fatal,
          type: 'FlutterError:RenderFlex',
          message: 'RenderFlex overflowed by 24 pixels on right',
          stackTrace: '#0 RenderFlex.performLayout',
          context: <String, Object?>{'screen': 'Chat'},
          breadcrumbs: <String>['14:00:00 [INFO] opened chat'],
        ),
        ErrorLogEntry(
          id: 'err_2',
          timestamp: DateTime(2026, 8, 20, 13, 50, 0),
          level: ErrorLogLevel.error,
          type: 'SocketException',
          message: 'Connection timed out',
        ),
      ];

      final ErrorLogsUiState state = ErrorLogsUiState(
        entries: entries,
        activeBackendUrl: 'http://127.0.0.1:3080',
      );

      await tester.pumpWidget(
        l10nApp(
          theme: DshTheme.light(),
          home: ErrorLogsScreen(uiState: state, onAction: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      // Check system info
      expect(find.text('System & Build Info'), findsOneWidget);
      expect(find.text('http://127.0.0.1:3080'), findsOneWidget);
      expect(find.text('All: 2'), findsOneWidget);
      expect(find.text('Fatal: 1'), findsOneWidget);
      expect(find.text('Error: 1'), findsOneWidget);

      // Check card 1
      expect(find.text('FATAL'), findsOneWidget);
      expect(find.text('FlutterError:RenderFlex'), findsOneWidget);
      expect(
        find.text('RenderFlex overflowed by 24 pixels on right'),
        findsOneWidget,
      );

      // Check card 2
      expect(find.text('ERROR'), findsOneWidget);
      expect(find.text('SocketException'), findsOneWidget);
      expect(find.text('Connection timed out'), findsOneWidget);

      // Copy all button in AppBar
      expect(find.text('Copy All'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('expanding card discloses stack trace and breadcrumbs', (
      WidgetTester tester,
    ) async {
      final ErrorLogEntry entry = ErrorLogEntry(
        id: 'err_expand',
        timestamp: DateTime(2026, 8, 20, 14, 0, 0),
        level: ErrorLogLevel.fatal,
        type: 'FatalCrash',
        message: 'Stack trace test message',
        stackTrace: '#0 framework.dart:100\n#1 app.dart:200',
        breadcrumbs: <String>['14:00:00 [INFO] initialized'],
      );

      final ErrorLogsUiState expandedState = ErrorLogsUiState(
        entries: <ErrorLogEntry>[entry],
        expandedIds: const <String>{'err_expand'},
      );

      await tester.pumpWidget(
        l10nApp(
          theme: DshTheme.light(),
          home: ErrorLogsScreen(uiState: expandedState, onAction: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Stack Trace'), findsOneWidget);
      expect(find.textContaining('#0 framework.dart:100'), findsOneWidget);
      expect(find.text('Related Logs'), findsOneWidget);
      expect(find.text('14:00:00 [INFO] initialized'), findsOneWidget);
    });

    testWidgets('filter chips and search field dispatch actions', (
      WidgetTester tester,
    ) async {
      ErrorLogsAction? dispatched;
      final ErrorLogsUiState state = ErrorLogsUiState(
        entries: <ErrorLogEntry>[
          ErrorLogEntry(
            id: 'e1',
            timestamp: DateTime.now(),
            level: ErrorLogLevel.fatal,
            type: 'Crash',
            message: 'Fatal msg',
          ),
        ],
      );

      await tester.pumpWidget(
        l10nApp(
          theme: DshTheme.light(),
          home: ErrorLogsScreen(
            uiState: state,
            onAction: (ErrorLogsAction a) => dispatched = a,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Fatal filter chip
      await tester.tap(find.text('Fatal (1)'));
      await tester.pumpAndSettle();

      expect(dispatched, isA<SetFilterLevelAction>());
      expect((dispatched as SetFilterLevelAction).level, ErrorLogLevel.fatal);

      // Type in search bar
      await tester.enterText(find.byType(TextField), 'Fatal');
      await tester.pumpAndSettle();

      expect(dispatched, isA<SetSearchQueryAction>());
      expect((dispatched as SetSearchQueryAction).query, 'Fatal');
    });

    testWidgets('copy all button triggers onCopyAll and shows SnackBar', (
      WidgetTester tester,
    ) async {
      bool copyAllCalled = false;
      final ErrorLogsUiState state = ErrorLogsUiState(
        entries: <ErrorLogEntry>[
          ErrorLogEntry(
            id: 'e1',
            timestamp: DateTime.now(),
            level: ErrorLogLevel.error,
            type: 'TestError',
            message: 'Error message',
          ),
        ],
      );

      await tester.pumpWidget(
        l10nApp(
          theme: DshTheme.light(),
          home: ErrorLogsScreen(
            uiState: state,
            onAction: (_) {},
            onCopyAll: ({bool filteredOnly = false}) async {
              copyAllCalled = true;
              return 'Report';
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Copy All'));
      await tester.pumpAndSettle();

      expect(copyAllCalled, isTrue);
      expect(find.text('All error logs copied to clipboard'), findsOneWidget);
    });

    testWidgets(
      'clear button shows confirmation dialog and dispatches ClearLogsAction',
      (WidgetTester tester) async {
        ErrorLogsAction? dispatched;
        final ErrorLogsUiState state = ErrorLogsUiState(
          entries: <ErrorLogEntry>[
            ErrorLogEntry(
              id: 'e1',
              timestamp: DateTime.now(),
              level: ErrorLogLevel.error,
              type: 'TestError',
              message: 'Error message',
            ),
          ],
        );

        await tester.pumpWidget(
          l10nApp(
            theme: DshTheme.light(),
            home: ErrorLogsScreen(
              uiState: state,
              onAction: (ErrorLogsAction a) => dispatched = a,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.delete_outline));
        await tester.pumpAndSettle();

        expect(find.text('Clear Error Logs'), findsOneWidget);
        expect(
          find.text(
            'Are you sure you want to clear all recorded error logs? This cannot be undone.',
          ),
          findsOneWidget,
        );

        // Tap Confirm Clear in dialog
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Clear'),
          ),
        );
        await tester.pumpAndSettle();

        expect(dispatched, isA<ClearLogsAction>());
        expect(find.text('Error logs cleared'), findsOneWidget);
      },
    );
  });
}
