/// App-root notification toast tests: a foreground notification renders a
/// tappable banner and tapping it navigates to the producing session (back
/// to the chat destination). The notification streams are overridden with
/// test-driven controllers so the fold/routing logic stays out of scope.
library;

import 'dart:async';
import 'dart:io';

import 'package:app/backends/backend_store.dart';
import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/main.dart';
import 'package:app/notifications/notification_events.dart';
import 'package:app/notifications/system_notifier.dart';
import 'package:app/ui/root/app_destination.dart';
import 'package:app/ui/root/app_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRpc implements DshRpcClient {
  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload,
  ) async {
    if (endpoint == 'session.list') {
      return RpcResult(
        ok: true,
        value: <String, Object?>{
          'items': [
            <String, Object?>{
              'sessionId': 's1',
              'updatedAt': 1,
              'running': false,
              'blank': false,
              'cwd': '/tmp/proj',
            },
          ],
        },
      );
    }
    return RpcResult(ok: true, value: <String, Object?>{});
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

class _NeverSocket implements DshEventSocket {
  final StreamController<ServerRequest> _frames =
      StreamController<ServerRequest>.broadcast();

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    onOpen?.call();
    return _frames.stream;
  }
}

BackendStore _testStore() {
  final dir = Directory.systemTemp.createTempSync('dsh-backends-test');
  addTearDown(() => dir.deleteSync(recursive: true));
  return BackendStore(
    File('${dir.path}/backends.json'),
    seedBaseUrl: kDshBaseUrl,
  );
}

const _event = AppNotificationEvent(
  kind: AppNotificationKind.otherTurnComplete,
  backendId: 'default',
  sessionId: 's1',
  sessionTitle: 'proj',
);

void main() {
  late StreamController<AppNotificationEvent> foreground;

  setUp(() {
    foreground = StreamController<AppNotificationEvent>.broadcast();
  });

  tearDown(() async {
    await foreground.close();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendStoreProvider.overrideWith((ref) async => _testStore()),
          dshRpcClientProvider(Uri.parse(kDshBaseUrl))
              .overrideWithValue(_FakeRpc()),
          dshEventSocketProvider(Uri.parse(kDshBaseUrl))
              .overrideWithValue(_NeverSocket()),
          foregroundNotificationEventsProvider.overrideWith(
            (ref) => foreground.stream,
          ),
          systemNotificationTargetsProvider.overrideWith(
            (ref) => const Stream<NotificationTarget>.empty(),
          ),
          systemNotifierProvider.overrideWithValue(SystemNotifier()),
        ],
        child: const DshApp(),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    // Wide surface docks the session panel so the served session is tappable.
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
  }

  /// Selects the served session so the chat controller exists for the
  /// tap-to-navigate assertion.
  Future<void> selectSession(WidgetTester tester) async {
    await tester.tap(find.text('Ungrouped'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('proj'));
    await tester.pumpAndSettle();
  }

  testWidgets('a foreground notification renders a tappable toast', (
    tester,
  ) async {
    await pumpApp(tester);
    await selectSession(tester);

    foreground.add(_event);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('New turn in another session'), findsOneWidget);
    expect(find.text('proj'), findsWidgets);

    // The toast auto-dismisses after its hold window.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('New turn in another session'), findsNothing);
  });

  testWidgets('tapping the toast navigates back to the chat destination', (
    tester,
  ) async {
    await pumpApp(tester);
    await selectSession(tester);

    // Leave the chat destination first.
    await tester.tap(find.text('Workspaces').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      AppDestination.workspaces.index,
    );

    foreground.add(_event);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('New turn in another session'), findsOneWidget);

    await tester.tap(find.text('New turn in another session'));
    await tester.pumpAndSettle();

    // Back on chat, with the notification's session selected.
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      AppDestination.chat.index,
    );
    final controller = tester.element(find.byType(AppRoot));
    final selected = ProviderScope.containerOf(controller)
        .read(chatControllerProvider('default'))
        .state
        .selectedSessionId;
    expect(selected, 's1');
  });

  testWidgets('the dismiss button removes the toast without navigating', (
    tester,
  ) async {
    await pumpApp(tester);
    await selectSession(tester);

    await tester.tap(find.text('Workspaces').last);
    await tester.pumpAndSettle();

    foreground.add(_event);
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Dismiss notification'));
    await tester.pumpAndSettle();

    expect(find.text('New turn in another session'), findsNothing);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      AppDestination.workspaces.index,
    );
  });
}
