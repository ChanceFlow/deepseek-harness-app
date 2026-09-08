import 'package:app/di/providers.dart';
import 'package:app/ui/settings/settings_screen.dart';
import 'package:app/ui/settings/settings_ui_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

void main() {
  group('Error Logs Settings Entry Tests', () {
    testWidgets(
      'renders Error Logs entry row with badge count in SettingsScreen',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final ErrorLogCollector collector = ErrorLogCollector(maxEntries: 10);
        collector.captureError('Test error 1', level: ErrorLogLevel.error);
        collector.captureError('Test error 2', level: ErrorLogLevel.fatal);

        final controller = ErrorLogsController(collector: collector);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              errorLogCollectorProvider.overrideWithValue(collector),
              errorLogsControllerProvider.overrideWithValue(controller),
            ],
            child: l10nApp(
              locale: const Locale('en'),
              home: SettingsScreen(
                uiState: const SettingsUiState(),
                onAction: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Error Logs'), findsOneWidget);
        expect(
          find.text('View and export application error logs'),
          findsOneWidget,
        );
        expect(find.text('2 errors'), findsOneWidget);

        // Tap on the error logs row to navigate to ErrorLogsRoute
        await tester.tap(find.text('Error Logs'));
        await tester.pumpAndSettle();

        // Asserts that ErrorLogsRoute / ErrorLogsScreen is pushed onto the stack
        expect(find.byType(ErrorLogsScreen), findsOneWidget);
        expect(find.text('System & Build Info'), findsOneWidget);
        expect(find.text('Test error 2'), findsOneWidget);
        expect(find.text('Test error 1'), findsOneWidget);
      },
    );

    testWidgets('renders localized Chinese strings when in zh locale', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final ErrorLogCollector collector = ErrorLogCollector(maxEntries: 10);
      final controller = ErrorLogsController(collector: collector);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            errorLogCollectorProvider.overrideWithValue(collector),
            errorLogsControllerProvider.overrideWithValue(controller),
          ],
          child: l10nApp(
            locale: const Locale('zh'),
            home: SettingsScreen(
              uiState: const SettingsUiState(),
              onAction: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('错误日志'), findsOneWidget);
      expect(find.text('查看并导出应用运行错误记录'), findsOneWidget);
      expect(find.text('0 条错误'), findsOneWidget);
    });
  });
}
