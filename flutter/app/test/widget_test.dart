/// App shell tests: bottom navigation destinations and first screens.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart' show Icons, NavigationBar, Size;
import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter_test/flutter_test.dart';
import 'package:app/di/providers.dart';
import 'package:app/main.dart';

class _FakeRpc implements DshRpcClient {
  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload,
  ) async {
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

Future<void> _pumpApp(WidgetTester tester) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        dshRpcClientProvider.overrideWithValue(_FakeRpc()),
        dshEventSocketProvider.overrideWithValue(_NeverSocket()),
      ],
      child: const DshApp(),
    ),
  );
}

void main() {
  testWidgets('three place destinations render and chat is the initial tab', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.pump();

    // Places only: session-scoped tools no longer ride the bottom bar.
    for (final label in ['Chat', 'Workspaces', 'Settings']) {
      expect(find.text(label), findsWidgets);
    }
    // No tool destinations on the bar (they live in the sidebar region).
    Finder navLabel(String label) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );
    expect(navLabel('Models'), findsNothing);
    expect(navLabel('Subagents'), findsNothing);
    expect(navLabel('Goals'), findsNothing);
    // The wide sidebar hosts the session-tools region instead.
    expect(find.text('Session tools'), findsOneWidget);
    // Real icons, not the former first-letter placeholders.
    Finder navIcon(IconData icon) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byIcon(icon),
    );
    expect(navIcon(Icons.chat_bubble_outline), findsOneWidget);
    expect(navIcon(Icons.folder_outlined), findsOneWidget);
    expect(navIcon(Icons.settings_outlined), findsOneWidget);

    // Initial tab is chat: session panel surface.
    expect(find.text('New session'), findsOneWidget);
    expect(find.text('Search sessions'), findsOneWidget);
  });

  testWidgets('workspaces tab lists its management surface', (tester) async {
    await _pumpApp(tester);
    await tester.pump();

    await tester.tap(find.text('Workspaces').last);
    await tester.pumpAndSettle();

    expect(find.text('Existing directory path'), findsOneWidget);
    expect(find.text('Browse'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
  });

  testWidgets('settings tab renders; session tools live in the chat drawer', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.pump();

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    // Settings describe fails against the fake rpc → loopback hint shows.
    expect(find.text('Refresh'), findsOneWidget);

    // Back to chat on a phone-scale surface: the tools live in the drawer.
    tester.view.physicalSize = const Size(600, 1280);
    tester.view.devicePixelRatio = 1.0;
    await tester.tap(find.text('Chat').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.text('Session tools'), findsOneWidget);

    // Pushing a tool page shows its surface with a back affordance.
    await tester.tap(find.text('Models'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Providers'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
  });
}
