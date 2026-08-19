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
  testWidgets('six destinations render and chat is the initial tab', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.pump();

    for (final label in [
      'Chat',
      'Workspaces',
      'Models',
      'Subagents',
      'Goals',
      'Settings',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    // Real icons, not the former first-letter placeholders.
    Finder navIcon(IconData icon) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byIcon(icon),
    );
    expect(navIcon(Icons.chat_bubble_outline), findsOneWidget);
    expect(navIcon(Icons.folder_outlined), findsOneWidget);
    expect(navIcon(Icons.tune), findsOneWidget);
    expect(navIcon(Icons.account_tree_outlined), findsOneWidget);
    expect(navIcon(Icons.flag_outlined), findsOneWidget);
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

  testWidgets('models and settings tabs render their live surfaces', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.pump();

    await tester.tap(find.text('Models').last);
    await tester.pumpAndSettle();
    expect(find.text('Models'), findsNWidgets(2)); // title + nav label
    expect(find.text('Session'), findsOneWidget);
    expect(find.text('Providers'), findsOneWidget);

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    // Settings describe fails against the fake rpc → loopback hint shows.
    expect(find.text('Settings'), findsNWidgets(2)); // title + nav label
    expect(find.text('Refresh'), findsOneWidget);
  });
}
