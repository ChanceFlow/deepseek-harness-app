/// The on-device error-log viewer: the collector's entries and breadcrumbs
/// rendered natively, with the level filter, the clear confirmation and the
/// empty state.
///
/// The collector is injected, so these tests read a fresh instance instead of
/// the process-wide [ErrorLogCollector.instance] the app writes to.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:app/logging/error_log_collector.dart';
import 'package:app/logging/error_log_entry.dart';
import 'package:app/logging/error_log_viewer.dart';
import 'package:app/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _viewer(ErrorLogCollector collector) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: DshTheme.light(),
    home: ErrorLogViewerScreen(collector: collector),
  );
}

void main() {
  testWidgets('an empty collector renders the empty state and no actions', (
    tester,
  ) async {
    final collector = ErrorLogCollector();
    await tester.pumpWidget(_viewer(collector));
    await tester.pumpAndSettle();

    expect(find.text('Error Logs'), findsOneWidget);
    expect(find.text('No Error Logs'), findsOneWidget);
    expect(
      find.text('Application is running smoothly with no errors captured.'),
      findsOneWidget,
    );
    expect(find.text('0 errors'), findsOneWidget);
    expect(find.text('Copy All'), findsNothing);
    expect(find.text('Clear'), findsNothing);
  });

  testWidgets('a captured entry shows its level and type, and the breadcrumb '
      'section lists the collector log', (tester) async {
    final collector = ErrorLogCollector()
      ..addBreadcrumb('opened host editor')
      ..captureError(
        'WebView renderer gone: didCrash=true priority=0',
        level: ErrorLogLevel.warning,
        type: 'webview-renderer-gone',
        context: <String, Object?>{'didCrash': true, 'priority': 0},
      );
    await tester.pumpWidget(_viewer(collector));
    await tester.pumpAndSettle();

    expect(find.text('1 errors'), findsOneWidget);
    expect(find.text('webview-renderer-gone'), findsOneWidget);
    expect(
      find.text('Warning'),
      findsNWidgets(2),
      reason: 'the entry badge and the warn filter seat both say Warning',
    );
    expect(
      find.text(collector.breadcrumbs.single),
      findsOneWidget,
      reason: 'the global breadcrumb section renders the collector ring',
    );
  });

  testWidgets('clear asks for confirmation and then empties the collector', (
    tester,
  ) async {
    final collector = ErrorLogCollector()
      ..captureError(
        'boom',
        level: ErrorLogLevel.error,
        type: 'FlutterError:test',
      );
    await tester.pumpWidget(_viewer(collector));
    await tester.pumpAndSettle();
    expect(find.text('FlutterError:test'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(find.text('Clear Error Logs'), findsOneWidget);
    expect(
      find.text(
        'Are you sure you want to clear all recorded error logs? '
        'This cannot be undone.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();

    expect(collector.entries, isEmpty);
    expect(find.text('FlutterError:test'), findsNothing);
    expect(find.text('No Error Logs'), findsOneWidget);
  });

  testWidgets('a level filter with no match states it instead of the list', (
    tester,
  ) async {
    final collector = ErrorLogCollector()
      ..captureError(
        'boom',
        level: ErrorLogLevel.error,
        type: 'FlutterError:test',
      );
    await tester.pumpWidget(_viewer(collector));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fatal'));
    await tester.pumpAndSettle();

    expect(find.text('No errors match your filter.'), findsOneWidget);
    expect(find.text('FlutterError:test'), findsNothing);
  });
}
