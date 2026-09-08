import 'package:app/logging/error_log_collector.dart';
import 'package:app/logging/error_log_entry.dart';
import 'package:app/ui/settings/error_logs/error_logs_controller.dart';
import 'package:app/ui/settings/error_logs/error_logs_ui_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ErrorLogCollector collector;
  late ErrorLogsController controller;

  setUp(() {
    collector = ErrorLogCollector(maxEntries: 50);
    controller = ErrorLogsController(
      collector: collector,
      activeBackendUrl: 'http://127.0.0.1:3080',
    );
  });

  tearDown(() {
    controller.dispose();
  });

  group('ErrorLogsController', () {
    test('initial state reflects collector and activeBackendUrl', () {
      expect(controller.state.entries, isEmpty);
      expect(controller.state.totalCount, 0);
      expect(controller.state.activeBackendUrl, 'http://127.0.0.1:3080');
    });

    test('state updates when collector captures errors', () async {
      collector.captureError(
        'Critical rendering failure',
        level: ErrorLogLevel.fatal,
        type: 'RenderException',
      );
      collector.captureError(
        'Network unreachable',
        level: ErrorLogLevel.error,
        type: 'SocketException',
      );

      // Allow microtask stream propagation
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.totalCount, 2);
      expect(controller.state.fatalCount, 1);
      expect(controller.state.errorCount, 1);
      expect(controller.state.warnCount, 0);
      expect(controller.state.filteredEntries, hasLength(2));
    });

    test('SetFilterLevelAction filters entries correctly', () async {
      collector.captureError('Fatal 1', level: ErrorLogLevel.fatal);
      collector.captureError('Error 1', level: ErrorLogLevel.error);
      collector.captureError('Warn 1', level: ErrorLogLevel.warning);
      await Future<void>.delayed(Duration.zero);

      controller.onAction(const SetFilterLevelAction(ErrorLogLevel.fatal));
      expect(controller.state.filterLevel, ErrorLogLevel.fatal);
      expect(controller.state.filteredEntries, hasLength(1));
      expect(controller.state.filteredEntries.first.message, 'Fatal 1');

      controller.onAction(const SetFilterLevelAction(ErrorLogLevel.warning));
      expect(controller.state.filteredEntries, hasLength(1));
      expect(controller.state.filteredEntries.first.message, 'Warn 1');

      controller.onAction(const SetFilterLevelAction(null));
      expect(controller.state.filterLevel, isNull);
      expect(controller.state.filteredEntries, hasLength(3));
    });

    test('SetSearchQueryAction filters by message, type, or stack', () async {
      collector.captureError(
        'RenderFlex overflowed by 20 pixels',
        type: 'FlutterError',
        level: ErrorLogLevel.fatal,
      );
      collector.captureError(
        'Connection refused',
        type: 'SocketException',
        level: ErrorLogLevel.error,
      );
      await Future<void>.delayed(Duration.zero);

      controller.onAction(const SetSearchQueryAction('overflowed'));
      expect(controller.state.filteredEntries, hasLength(1));
      expect(controller.state.filteredEntries.first.type, 'FlutterError');

      controller.onAction(const SetSearchQueryAction('socket'));
      expect(controller.state.filteredEntries, hasLength(1));
      expect(
        controller.state.filteredEntries.first.message,
        'Connection refused',
      );

      controller.onAction(const SetSearchQueryAction('nonexistent'));
      expect(controller.state.filteredEntries, isEmpty);

      controller.onAction(const SetSearchQueryAction(''));
      expect(controller.state.filteredEntries, hasLength(2));
    });

    test('ToggleExpandAction toggles card expansion state', () {
      controller.onAction(const ToggleExpandAction('err_1'));
      expect(controller.state.isExpanded('err_1'), isTrue);

      controller.onAction(const ToggleExpandAction('err_1'));
      expect(controller.state.isExpanded('err_1'), isFalse);
    });

    test(
      'ExpandAllAction and CollapseAllAction work across filtered entries',
      () async {
        collector.captureError('Err 1');
        collector.captureError('Err 2');
        await Future<void>.delayed(Duration.zero);

        controller.onAction(const ExpandAllAction());
        expect(controller.state.expandedIds, hasLength(2));

        controller.onAction(const CollapseAllAction());
        expect(controller.state.expandedIds, isEmpty);
      },
    );

    test('ClearLogsAction clears collector and controller state', () async {
      collector.captureError('To be deleted');
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.totalCount, 1);

      controller.onAction(const ClearLogsAction());
      expect(controller.state.totalCount, 0);
      expect(collector.entries, isEmpty);
    });

    test('copy methods export markdown and place text on clipboard', () async {
      collector.captureError(
        'Test error for copy',
        type: 'CustomException',
        level: ErrorLogLevel.error,
      );
      await Future<void>.delayed(Duration.zero);

      final String allReport = await controller.copyAllToClipboard();
      expect(allReport, contains('# DSH Mobile Error & Diagnostic Report'));
      expect(allReport, contains('Test error for copy'));

      final ErrorLogEntry entry = controller.state.entries.first;
      final String entryText = await controller.copyEntryToClipboard(entry);
      expect(entryText, contains('### [ERROR] CustomException'));
      expect(entryText, contains('Test error for copy'));

      final String sysInfo = await controller.copySystemInfoToClipboard();
      expect(sysInfo, contains('## System Information'));
    });
  });
}
