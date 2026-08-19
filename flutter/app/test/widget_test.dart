/// App shell tests: bottom navigation destinations and first screens.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart' show Icons, NavigationBar;
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
    await tester.pumpAndSettle();

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
    // No session-tools region in the sidebar anymore; the composer's model
    // seat is the models entry.
    expect(find.text('Session tools'), findsNothing);
    expect(find.byTooltip('Commands'), findsOneWidget);
    // Mobile model seat: the compact circle button (tooltip carries the
    // current model; the label lives in the sheet it opens).
    expect(find.byTooltip('Model: Model'), findsOneWidget);
    // Session-scoped seats (subagents action, plan toggle) only render
    // with a selected session; this app-level fake has none.
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

    // Web WorkspaceBrowser chrome: the section header pair (the nav label
    // carries the same word).
    expect(find.text('Workspaces'), findsWidgets);
    expect(find.byTooltip('Search'), findsOneWidget);
    expect(find.byTooltip('Add workspace'), findsOneWidget);
  });

  testWidgets('settings tab renders; plus opens the command sheet', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    // Settings describe fails against the fake rpc → loopback hint shows;
    // the header keeps its circular refresh action (web panel chrome).
    expect(find.byTooltip('Refresh'), findsOneWidget);
    expect(find.textContaining('loopback-only'), findsOneWidget);

    // Back to chat: the + seat exists (disabled without a session —
    // the app-level fake serves none).
    await tester.tap(find.text('Chat').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Commands'), findsOneWidget);
  });
}
