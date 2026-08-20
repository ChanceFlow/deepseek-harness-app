/// Multi-backend sidebar tests: the ChatScreen sidebar groups sessions
/// under per-backend headers, taps on another backend's rows route
/// through the backend-aware callbacks, and the app-bar subtitle names
/// the active backend. The registry-level switch rides ChatRoute with
/// the real providers (store, registry, per-backend controllers).
library;

import 'dart:async';
import 'dart:io';

import 'package:domain/model/backend.dart';
import 'package:domain/model/connection_state.dart';
import 'package:domain/model/session.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/backends/backend_store.dart';
import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';

import '../../l10n_app.dart';

class _FakeRpc implements DshRpcClient {
  _FakeRpc({this.sessions = const <Object?>[]});

  /// session.list items this host serves (per-backend rosters).
  final List<Object?> sessions;

  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload,
  ) async {
    if (endpoint == 'session.list') {
      return RpcResult(ok: true, value: <String, Object?>{'items': sessions});
    }
    if (endpoint == 'host.describe') {
      return RpcResult(
        ok: true,
        value: <String, Object?>{
          'version': 'test',
          'cwd': '/tmp',
          'provider': 'deepseek',
          'model': 'test-model',
          'attachedSessions': 0,
          'canOpenPath': true,
        },
      );
    }
    return RpcResult(ok: true, value: <String, Object?>{});
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

class _QuietSocket implements DshEventSocket {
  final StreamController<ServerRequest> _frames =
      StreamController<ServerRequest>.broadcast();

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    onOpen?.call();
    return _frames.stream;
  }
}

BackendStore _testStore({String? document}) {
  final dir = Directory.systemTemp.createTempSync('sidebar_backends_test');
  // Retry like the settings suite: an unawaited registry persist can
  // race the recursive delete (errno 39).
  addTearDown(() async {
    for (var i = 0; i < 50; i++) {
      try {
        dir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  });
  final file = File('${dir.path}/backends.json');
  if (document != null) file.writeAsStringSync(document);
  return BackendStore(file, seedBaseUrl: kDshBaseUrl);
}

ChatUiState _state({
  List<SessionSummary> sessions = const <SessionSummary>[],
  String? selectedSessionId,
}) {
  return ChatUiState(
    connection: const ConnectionState(
      phase: ConnectionPhase.connected,
      hostDescription: HostDescription(version: '1.2.3', cwd: '/tmp'),
    ),
    sessions: sessions,
    selectedSessionId: selectedSessionId,
  );
}

final _laptop = BackendConfig(
  id: 'default',
  label: 'Laptop',
  baseUri: Uri.parse('http://10.0.2.2:3080'),
);

final _buildBox = BackendConfig(
  id: 'b1',
  label: 'Build box',
  baseUri: Uri.parse('http://10.0.2.2:3081'),
);

final _twoSlices = <BackendSessionSlice>[
  BackendSessionSlice(
    backend: _laptop,
    active: true,
    sessions: const [
      SessionSummary(id: 's1', title: 'Alpha on laptop', blank: false),
    ],
    workspaces: const [],
  ),
  BackendSessionSlice(
    backend: _buildBox,
    active: false,
    sessions: const [
      SessionSummary(id: 'sB1', title: 'Beta on buildbox', blank: false),
    ],
    workspaces: const [],
  ),
];

/// Wide layout (the sidebar pane, not the drawer) with the slices and
/// recording callbacks.
Future<void> _pumpSlices(
  WidgetTester tester, {
  required ChatUiState uiState,
  required List<ChatAction> actions,
  required List<String> backendSelections,
  required List<(String, String)> backendSessionSelections,
  List<BackendSessionSlice>? slices,
}) async {
  tester.view.physicalSize = const Size(800, 1280);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendStoreProvider.overrideWith((ref) async => _testStore()),
        dshRpcClientProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_FakeRpc()),
        dshEventSocketProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_QuietSocket()),
      ],
      child: l10nApp(
        home: ChatScreen(
          uiState: uiState,
          onAction: actions.add,
          backendId: 'default',
          backendSlices: slices ?? _twoSlices,
          onSelectBackend: backendSelections.add,
          onSelectBackendSession: (backendId, sessionId) =>
              backendSessionSelections.add((backendId, sessionId)),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('the sidebar groups sessions under backend headers', (
    tester,
  ) async {
    await _pumpSlices(
      tester,
      uiState: _state(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha on laptop', blank: false),
        ],
      ),
      actions: [],
      backendSelections: [],
      backendSessionSelections: [],
    );

    // Both backends' headers with the live-host line and the markers.
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Build box'), findsOneWidget);
    expect(find.text('10.0.2.2:3080'), findsOneWidget);
    expect(find.text('10.0.2.2:3081'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Standby'), findsOneWidget);

    // Both slices' workspace groups render (default collapsed — only
    // group headers, no session rows yet).
    expect(find.text('Ungrouped'), findsNWidgets(2));
    expect(find.text('Alpha on laptop'), findsNothing);
    expect(find.text('Beta on buildbox'), findsNothing);
  });

  testWidgets('tapping another backend header selects it', (tester) async {
    final selections = <String>[];
    await _pumpSlices(
      tester,
      uiState: _state(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha on laptop', blank: false),
        ],
      ),
      actions: [],
      backendSelections: selections,
      backendSessionSelections: [],
    );

    await tester.tap(find.text('Build box'));
    await tester.pump();
    expect(selections, <String>['b1']);

    // The active backend's header is not a switch control.
    await tester.tap(find.text('Laptop'));
    await tester.pump();
    expect(selections, <String>['b1']);
  });

  testWidgets(
    "a session under another backend routes through the backend-aware callback",
    (tester) async {
      final backendSessions = <(String, String)>[];
      final actions = <ChatAction>[];
      await _pumpSlices(
        tester,
        uiState: _state(
          sessions: const [
            SessionSummary(id: 's1', title: 'Alpha on laptop', blank: false),
          ],
        ),
        actions: actions,
        backendSelections: [],
        backendSessionSelections: backendSessions,
      );

      // Expand the standby backend's Ungrouped group (second 'Ungrouped'
      // header — the sections render in registry order), then tap its row.
      await tester.tap(find.text('Ungrouped').at(1));
      await tester.pump();
      expect(find.text('Beta on buildbox'), findsOneWidget);
      await tester.tap(find.text('Beta on buildbox'));
      await tester.pump();

      expect(backendSessions, <(String, String)>[('b1', 'sB1')]);
      // The direct path never fired for another backend's row.
      expect(actions.whereType<SelectSession>(), isEmpty);
    },
  );

  testWidgets('active-backend rows keep the direct selection path', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    final backendSessions = <(String, String)>[];
    await _pumpSlices(
      tester,
      uiState: _state(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha on laptop', blank: false),
          SessionSummary(id: 's2', title: 'Second on laptop', blank: false),
        ],
        selectedSessionId: 's1',
      ),
      actions: actions,
      backendSelections: [],
      backendSessionSelections: backendSessions,
      slices: [
        BackendSessionSlice(
          backend: _laptop,
          active: true,
          sessions: const [
            SessionSummary(id: 's1', title: 'Alpha on laptop', blank: false),
            SessionSummary(id: 's2', title: 'Second on laptop', blank: false),
          ],
          workspaces: const [],
        ),
        BackendSessionSlice(
          backend: _buildBox,
          active: false,
          sessions: const [
            SessionSummary(id: 'sB1', title: 'Beta on buildbox', blank: false),
          ],
          workspaces: const [],
        ),
      ],
    );

    // The selected session's group auto-expands (web current-group rule).
    expect(
      find.descendant(
        of: find.byType(SessionPanel),
        matching: find.text('Second on laptop'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(SessionPanel),
        matching: find.text('Second on laptop'),
      ),
    );
    await tester.pump();
    expect(
      actions.whereType<SelectSession>(),
      contains(const SelectSession('s2')),
    );
    expect(backendSessions, isEmpty);
  });

  testWidgets('the app-bar subtitle names the active backend', (tester) async {
    await _pumpSlices(
      tester,
      uiState: _state(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha on laptop', blank: false),
        ],
      ),
      actions: [],
      backendSelections: [],
      backendSessionSelections: [],
    );
    expect(find.text('Laptop · connected 1.2.3'), findsOneWidget);
  });

  testWidgets('a single backend keeps the bare connection subtitle', (
    tester,
  ) async {
    await _pumpSlices(
      tester,
      uiState: _state(
        sessions: const [
          SessionSummary(id: 's1', title: 'Alpha on laptop', blank: false),
        ],
      ),
      actions: [],
      backendSelections: [],
      backendSessionSelections: [],
      slices: [
        BackendSessionSlice(
          backend: _laptop,
          active: true,
          sessions: const [
            SessionSummary(id: 's1', title: 'Alpha on laptop', blank: false),
          ],
          workspaces: const [],
        ),
      ],
    );
    expect(find.text('connected 1.2.3'), findsOneWidget);
    // No backend headers in single-backend form.
    expect(find.text('Active'), findsNothing);
    expect(find.text('Standby'), findsNothing);
  });

  testWidgets('tapping another backend\'s session switches the active backend', (
    tester,
  ) async {
    // The real wiring: store → registry → per-backend controllers, with
    // each host's fake serving its own session roster.
    const document =
        '{"backends": ['
        '{"id": "default", "label": "Laptop", "baseUrl": "http://10.0.2.2:3080"},'
        '{"id": "b1", "label": "Build box", "baseUrl": "http://10.0.2.2:3081"}'
        '], "activeId": "default"}';
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendStoreProvider.overrideWith(
            (ref) async => _testStore(document: document),
          ),
          dshRpcClientProvider(Uri.parse('http://10.0.2.2:3080'))
              .overrideWithValue(
                _FakeRpc(
                  sessions: <Object?>[
                    <String, Object?>{
                      'sessionId': 's1',
                      'updatedAt': 5,
                      'running': false,
                      'blank': false,
                      'cwd': '/tmp/laptop',
                      'projections': <String, Object?>{
                        'values': <String, Object?>{'title': 'Alpha on laptop'},
                      },
                    },
                  ],
                ),
              ),
          dshRpcClientProvider(
            Uri.parse('http://10.0.2.2:3081'),
          ).overrideWithValue(
            _FakeRpc(
              sessions: <Object?>[
                <String, Object?>{
                  'sessionId': 'sB1',
                  'updatedAt': 6,
                  'running': false,
                  'blank': false,
                  'cwd': '/tmp/box',
                  'projections': <String, Object?>{
                    'values': <String, Object?>{'title': 'Beta on buildbox'},
                  },
                },
              ],
            ),
          ),
          dshEventSocketProvider(Uri.parse('http://10.0.2.2:3080'))
              .overrideWithValue(_QuietSocket()),
          dshEventSocketProvider(Uri.parse('http://10.0.2.2:3081'))
              .overrideWithValue(_QuietSocket()),
        ],
        child: l10nApp(home: const ChatRoute()),
      ),
    );
    // Let the registry load and both backends' controllers pull their
    // rosters (each real dart:io turn needs a runAsync round + pump).
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // Both backends' slices render with their live rosters.
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Build box'), findsOneWidget);
    expect(find.text('Laptop · connected test'), findsOneWidget);

    // Expand the standby backend's Ungrouped group and tap its session.
    await tester.tap(find.text('Ungrouped').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta on buildbox'));
    await tester.pumpAndSettle();

    // The chat surface followed the registry switch: the app-bar names
    // the now-active backend, and its session is the selected one.
    expect(find.text('Build box · connected test'), findsOneWidget);
    expect(find.text('Laptop · connected test'), findsNothing);
  });
}
