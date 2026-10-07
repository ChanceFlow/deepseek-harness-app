/// The Open workspace verb: the session header's native-desktop opener
/// (dsh `session/canOpenWorkspacePath`, `session/workspacePathApplications`,
/// `session/openWorkspacePath`).
///
/// Every case drives the real [ChatController] over the shared
/// [FakeChatRepository] seam and the real [ChatScreen], and asserts what a
/// user sees: the verb appearing only when the host reports a desktop, the
/// application sheet, and the stated failure.
library;

import 'dart:async';

import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/ui/chat/chat_controller.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:domain/model/open_in_app.dart';
import 'package:domain/model/repository_failure.dart';
import 'package:domain/model/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';
import 'chat_controller_test.dart' show FakeChatRepository;
import 'chat_local_state_fake.dart';

/// Answers every RPC with an empty ok, so the controller's non-session
/// loads settle without a transport.
class _EmptyRpc implements DshRpcClient {
  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async => RpcResult(ok: true, value: <String, Object?>{});

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

/// The repository double with the host's desktop facts scripted.
class _OpenWorkspaceRepository extends FakeChatRepository {
  _OpenWorkspaceRepository()
    : super(
        initialSessions: const <SessionSummary>[
          SessionSummary(
            id: 'session-1',
            title: 'Test session',
            blank: false,
            cwd: '/home/tester/project',
          ),
        ],
      );

  /// What `session/canOpenWorkspacePath` answers.
  bool available = true;

  /// Whether that probe fails instead of answering.
  bool probeThrows = false;

  /// The registered applications `session/workspacePathApplications`
  /// reports.
  List<WorkspacePathApplication> applications =
      const <WorkspacePathApplication>[];

  /// Whether the association query fails instead of answering.
  bool applicationsThrow = false;

  /// Whether `session/openWorkspacePath` is refused by the host.
  bool openThrows = false;

  /// Every open the host was asked for, in order.
  final List<(String path, String? application)> opened = <(String, String?)>[];

  @override
  Future<bool> canOpenWorkspacePath() async {
    if (probeThrows) throw Exception('desktop probe failed');
    return available;
  }

  @override
  Future<List<WorkspacePathApplication>> workspacePathApplications(
    String path,
  ) async {
    if (applicationsThrow) throw Exception('association query failed');
    return applications;
  }

  @override
  Future<void> openWorkspacePath(String path, {String? application}) async {
    opened.add((path, application));
    if (openThrows) {
      throw const RepositoryFailure(
        'gateway/bad-request',
        'Path has no verified Host path',
      );
    }
  }
}

/// The harness: a real controller over [repository], rendered by the real
/// [ChatScreen]. [rendered] always holds the newest published state.
class _Harness {
  _Harness(this.repository, WidgetTester tester, {double width = 400}) {
    controller = ChatController(repository);
    addTearDown(controller.dispose);
    tester.view.physicalSize = Size(width, 1280);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  final _OpenWorkspaceRepository repository;
  late final ChatController controller;
  ChatUiState rendered = const ChatUiState();

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dshRpcClientProvider(Uri.parse(kDshBaseUrl))
              .overrideWithValue(_EmptyRpc()),
          dshEventSocketProvider(Uri.parse(kDshBaseUrl))
              .overrideWithValue(_QuietSocket()),
        ],
        child: l10nApp(
          home: StreamBuilder<ChatUiState>(
            stream: controller.uiState,
            builder: (context, snapshot) {
              rendered = snapshot.data ?? rendered;
              return ChatScreen(
                uiState: rendered,
                onAction: controller.onAction,
                localState: FakeChatLocalState(),
                loadWorkspacePathApplications:
                    controller.workspacePathApplications,
              );
            },
          ),
        ),
      ),
    );
    // The controller's upstream publishes ride a trailing-edge window.
    await tester.pump(const Duration(milliseconds: 60));
    controller.onAction(const SelectSession('session-1'));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Opens the phone bar's session menu and taps the Open workspace verb.
Future<void> _tapOpenWorkspaceVerb(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open workspace'));
  await tester.pumpAndSettle();
}

const WorkspacePathApplication _files = WorkspacePathApplication(
  id: 'org.gnome.Nautilus.desktop',
  name: 'Files',
  isDefault: true,
  icon: null,
);

const WorkspacePathApplication _code = WorkspacePathApplication(
  id: 'code.desktop',
  name: 'Code',
  isDefault: false,
  icon: null,
);

void main() {
  testWidgets('the verb is hidden while the host reports no desktop', (
    tester,
  ) async {
    final repository = _OpenWorkspaceRepository()..available = false;
    final harness = _Harness(repository, tester);
    await harness.pump(tester);

    expect(harness.rendered.canOpenWorkspace, isFalse);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Open workspace'), findsNothing);
  });

  testWidgets('the verb is hidden when the availability probe fails', (
    tester,
  ) async {
    final repository = _OpenWorkspaceRepository()..probeThrows = true;
    final harness = _Harness(repository, tester);
    await harness.pump(tester);

    // An unreachable host reads as no desktop, exactly as the reference
    // client reads its failed probe.
    expect(harness.rendered.canOpenWorkspace, isFalse);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Open workspace'), findsNothing);
  });

  testWidgets('the phone menu offers the verb and lists the registered '
      'applications', (tester) async {
    final repository = _OpenWorkspaceRepository()
      ..applications = <WorkspacePathApplication>[_files, _code];
    final harness = _Harness(repository, tester);
    await harness.pump(tester);

    expect(harness.rendered.canOpenWorkspace, isTrue);
    await _tapOpenWorkspaceVerb(tester);

    // More than one opener: the sheet lists them rather than guessing.
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Code'), findsOneWidget);
    expect(repository.opened, isEmpty);

    await tester.tap(find.text('Code'));
    await tester.pumpAndSettle();
    expect(repository.opened, <(String, String?)>[
      ('/home/tester/project', 'code.desktop'),
    ]);
  });

  testWidgets('one registered application opens without asking', (
    tester,
  ) async {
    final repository = _OpenWorkspaceRepository()
      ..applications = <WorkspacePathApplication>[_files];
    final harness = _Harness(repository, tester);
    await harness.pump(tester);

    await _tapOpenWorkspaceVerb(tester);

    expect(find.text('Files'), findsNothing);
    expect(repository.opened, <(String, String?)>[
      ('/home/tester/project', 'org.gnome.Nautilus.desktop'),
    ]);
  });

  testWidgets('no registered application opens the system default', (
    tester,
  ) async {
    final repository = _OpenWorkspaceRepository();
    final harness = _Harness(repository, tester);
    await harness.pump(tester);

    await _tapOpenWorkspaceVerb(tester);

    // An omitted application is the request's "keep the OS association".
    expect(repository.opened, <(String, String?)>[
      ('/home/tester/project', null),
    ]);
  });

  testWidgets('a failed association query falls back to the default open', (
    tester,
  ) async {
    final repository = _OpenWorkspaceRepository()..applicationsThrow = true;
    final harness = _Harness(repository, tester);
    await harness.pump(tester);

    await _tapOpenWorkspaceVerb(tester);

    expect(repository.opened, <(String, String?)>[
      ('/home/tester/project', null),
    ]);
  });

  testWidgets('a failed open is stated instead of failing silently', (
    tester,
  ) async {
    final repository = _OpenWorkspaceRepository()..openThrows = true;
    final harness = _Harness(repository, tester);
    await harness.pump(tester);

    await _tapOpenWorkspaceVerb(tester);

    // The host's own reason reaches the shared error strip.
    expect(
      find.textContaining('Path has no verified Host path'),
      findsOneWidget,
    );
  });

  testWidgets('the wide header carries the verb as its own icon seat', (
    tester,
  ) async {
    final repository = _OpenWorkspaceRepository()
      ..applications = <WorkspacePathApplication>[_files];
    final harness = _Harness(repository, tester, width: 900);
    await harness.pump(tester);

    await tester.tap(find.byTooltip('Open workspace'));
    await tester.pumpAndSettle();

    expect(repository.opened, <(String, String?)>[
      ('/home/tester/project', 'org.gnome.Nautilus.desktop'),
    ]);
  });
}
