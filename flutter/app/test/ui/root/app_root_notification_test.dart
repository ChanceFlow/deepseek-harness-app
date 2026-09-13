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
    JsonMap payload, {
    Duration? timeout,
  }) async {
    if (endpoint == 'session/list' || endpoint == 'session.list') {
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

/// The `$events` registration answer the gateway sends over
/// `/api/remote.mux`
/// (`reference/deepseek-harness/packages/api/gateway/src/stream-protocol.ts`
/// `RemoteEventReadyFrame`); it is the connection generation handshake.
ServerRequest _readyFrame() => ServerRequest(
  rpcId: 'remote-events',
  method: 'item',
  payload: <String, Object?>{
    'type': 'ready',
    'clientId': 'client-1',
    'host': <String, Object?>{'home': '/home/tester'},
  },
);

class _NeverSocket implements DshEventSocket {
  final StreamController<ServerRequest> _frames =
      StreamController<ServerRequest>.broadcast();

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    onOpen?.call();
    // A broadcast controller drops events with no listener; the handshake
    // frame therefore lands after this call's listener attaches.
    scheduleMicrotask(() => _frames.add(_readyFrame()));
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
  late StreamController<NotificationTarget> targets;

  setUp(() {
    foreground = StreamController<AppNotificationEvent>.broadcast();
    targets = StreamController<NotificationTarget>.broadcast();
  });

  tearDown(() async {
    await foreground.close();
    await targets.close();
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
            (ref) => targets.stream,
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
  /// tap-to-navigate assertion. The row groups under its inferred workspace
  /// (the pinned host registers no unary workspace list), so its group header
  /// and its row share the `proj` label; the header is found first.
  Future<void> selectSession(WidgetTester tester) async {
    await tester.tap(find.text('proj').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('proj').last);
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

    expect(find.text('New reply in another session'), findsOneWidget);
    expect(find.text('proj'), findsWidgets);

    // The toast auto-dismisses after its hold window.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('New reply in another session'), findsNothing);
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
    expect(find.text('New reply in another session'), findsOneWidget);

    await tester.tap(find.text('New reply in another session'));
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

    expect(find.text('New reply in another session'), findsNothing);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      AppDestination.workspaces.index,
    );
  });

  testWidgets('a repeated notification re-enters the banner', (tester) async {
    // Two completions of the same session produce equal events; the banner
    // is keyed on arrival, not on the event, so the second one visibly
    // arrives instead of updating the first in place.
    await pumpApp(tester);
    await selectSession(tester);

    Key? toastKey() {
      for (final switcher in tester.widgetList<AnimatedSwitcher>(
        find.byType(AnimatedSwitcher),
      )) {
        final child = switcher.child;
        if (child is Align && child.alignment == Alignment.topCenter) {
          return child.key;
        }
      }
      return null;
    }

    foreground.add(_event);
    await tester.pump();
    await tester.pumpAndSettle();
    final first = toastKey();
    expect(first, isNotNull);

    foreground.add(_event);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(toastKey(), isNotNull);
    expect(toastKey(), isNot(first));
  });

  testWidgets('a system-notification tap navigates to the producing session', (
    tester,
  ) async {
    await pumpApp(tester);
    await selectSession(tester);

    await tester.tap(find.text('Workspaces').last);
    await tester.pumpAndSettle();

    targets.add(
      const NotificationTarget(backendId: 'default', sessionId: 's1'),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      AppDestination.chat.index,
    );
  });

  testWidgets('two identical notification taps both navigate', (tester) async {
    // The ongoing row and the completion notice for one session carry the
    // same payload; a tap is an event, so the second one must land too.
    await pumpApp(tester);
    await selectSession(tester);
    const target = NotificationTarget(backendId: 'default', sessionId: 's1');

    for (var tap = 0; tap < 2; tap++) {
      await tester.tap(find.text('Workspaces').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        AppDestination.workspaces.index,
        reason: 'left the chat destination before tap $tap',
      );

      targets.add(target);
      await tester.pumpAndSettle();

      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        AppDestination.chat.index,
        reason: 'tap $tap navigated back to chat',
      );
    }
  });
}
