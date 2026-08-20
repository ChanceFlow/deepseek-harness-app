/// App shell tests: bottom navigation destinations and first screens.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart'
    show Icons, NavigationBar, Size, TextField;
import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter_test/flutter_test.dart';
import 'package:app/backends/backend_store.dart';
import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/main.dart';

class _FakeRpc implements DshRpcClient {
  _FakeRpc([this._sessions = const <Object?>[]]);

  final List<Object?> _sessions;

  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload,
  ) async {
    if (endpoint == 'session.list') {
      return RpcResult(ok: true, value: <String, Object?>{'items': _sessions});
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

/// In-memory-backed store: path_provider has no plugin in tests, so the
/// registry reads a temp file instead of the documents directory.
BackendStore _testStore() {
  final dir = Directory.systemTemp.createTempSync('dsh-backends-test');
  addTearDown(() => dir.deleteSync(recursive: true));
  return BackendStore(
    File('${dir.path}/backends.json'),
    seedBaseUrl: kDshBaseUrl,
  );
}

Future<void> _pumpApp(WidgetTester tester, {DshRpcClient? rpc}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendStoreProvider.overrideWith((ref) async => _testStore()),
        // Family seams keyed by the seed backend's URL (the store seeds
        // from kDshBaseUrl).
        dshRpcClientProvider(Uri.parse(kDshBaseUrl)).overrideWithValue(
          rpc ?? _FakeRpc(),
        ),
        dshEventSocketProvider(Uri.parse(kDshBaseUrl)).overrideWithValue(
          _NeverSocket(),
        ),
      ],
      child: const DshApp(),
    ),
  );
  // Real dart:io (the backend registry's document read) only completes in
  // a real-async zone — give the store load a beat before the fake clock
  // takes over, or the shell stays on its loading spinner forever.
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pump();
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

    // Initial tab is chat: session panel surface (search rides its toggle).
    expect(find.text('New session'), findsOneWidget);
    expect(find.byTooltip('Search sessions'), findsOneWidget);
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

  testWidgets('the composer draft survives tab switches', (tester) async {
    // A selected session keeps the composer enabled; the app-level default
    // fake serves none.
    await _pumpApp(
      tester,
      rpc: _FakeRpc(const <Object?>[
        <String, Object?>{
          'sessionId': 's1',
          'updatedAt': 1,
          'running': false,
          'blank': false,
          'cwd': '/tmp/proj',
        },
      ]),
    );
    // Wide surface docks the session panel (compact hides it in the
    // drawer); the default test surface is phone-narrow.
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    // Select the served session so the composer enables: the Ungrouped
    // bucket only auto-expands for the selected session, so open it first.
    await tester.tap(find.text('Ungrouped'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('proj'));
    await tester.pumpAndSettle();

    final composerField = find.byType(TextField).first;
    await tester.enterText(composerField, 'half-finished thought');
    await tester.pump();

    // Leave and return through both other tabs; the IndexedStack keeps
    // the chat route (and its draft controller) alive.
    await tester.tap(find.text('Workspaces').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chat').last);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(composerField).controller?.text,
      'half-finished thought',
    );
  });
}
