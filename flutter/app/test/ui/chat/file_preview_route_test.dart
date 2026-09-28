/// Production-path guard for the preview's byte read.
///
/// The sheet-level tests inject their readers straight into `ChatScreen`, so
/// nothing there observes the hop from `ChatRepository` through
/// `ChatController` and `ChatScreen` into `showFilePreviewSheet`. This test
/// drives that real entry path: the actual `ChatRoute()` builds its controller
/// from `chatRepositoryProvider`, and the delivered-file card's Open action
/// opens the real sheet. It fails if the route stops forwarding
/// `readWorkspaceFileBytes` — a dropped forward shows the generic failure
/// instead of the image.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:domain/model/chat_message.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/workspace_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/backends/backend_store.dart';
import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/file_preview_sheet.dart';

import '../../l10n_app.dart';
import 'chat_controller_test.dart' show FakeChatRepository;

/// The design harness' 16×10 PNG fixture, copied here so this guard does not
/// reach into `test/design/`.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAABAAAAAKCAIAAAAy3EnLAAAAFElEQVR4nGOIqnhGEmIY1TA0NQAA6MQTEJdTNawAAAAASUVORK5CYII=',
);

class _FakeRpc implements DshRpcClient {
  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async {
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

class _QuietSocket implements DshEventSocket {
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
  final dir = Directory.systemTemp.createTempSync('file_preview_route_test');
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
  return BackendStore(
    File('${dir.path}/backends.json'),
    seedBaseUrl: kDshBaseUrl,
  );
}

/// One finished turn that delivered a PNG, served with a real image for its
/// bytes.
class _DeliveredPngRepository extends FakeChatRepository {
  _DeliveredPngRepository()
    : super(
        initialSessions: const <SessionSummary>[
          SessionSummary(id: 's1', title: 'Route session', blank: false),
        ],
        initialTimeline: <TimelineItem>[
          const TimelineTurnBoundary(1),
          const TimelineToolCall(
            id: 'present-1',
            name: 'present',
            arguments: '{"files":[{"path":"out/hero.png"}]}',
            status: ToolRunStatus.completed,
            presentedFiles: <PresentedFile>[
              PresentedFile(path: 'out/hero.png', description: 'Rendered hero'),
            ],
          ),
          const TimelineMessage(
            ChatMessage(
              id: 'm1',
              sessionId: 's1',
              role: MessageRole.assistant,
              text: 'done',
            ),
          ),
        ],
      );

  @override
  Future<void> openSession(String sessionId) async {
    // The base fake replaces the timeline with its offline fixture here; this
    // route serves the delivered-file timeline it was built with.
    openedSessionIds.add(sessionId);
  }

  int byteReads = 0;
  final List<String> readPaths = <String>[];

  @override
  Future<WorkspaceFileBytes> readWorkspaceFileBytes(
    String sessionId,
    String path, {
    int? offset,
    int? length,
    String? baseFile,
  }) async {
    byteReads += 1;
    readPaths.add(path);
    return WorkspaceFileBytes(
      absolutePath: '/workspace/$path',
      version: 'v1',
      offset: 0,
      data: _png,
      eof: true,
    );
  }
}

Finder _sheetImage() => find.descendant(
  of: find.byType(FilePreviewSheet),
  matching: find.byType(Image),
);

void main() {
  testWidgets(
    'the route forwards the byte reader so a delivered image renders',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _DeliveredPngRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendStoreProvider.overrideWith((ref) async => _testStore()),
            chatRepositoryProvider('default').overrideWithValue(repository),
            dshRpcClientProvider(Uri.parse(kDshBaseUrl))
                .overrideWithValue(_FakeRpc()),
            dshEventSocketProvider(Uri.parse(kDshBaseUrl))
                .overrideWithValue(_QuietSocket()),
          ],
          child: l10nApp(home: const ChatRoute()),
        ),
      );
      // The registry load and the roster pull need real dart:io turns.
      for (
        var i = 0;
        i < 30 && find.text('Ungrouped').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
      }

      // The sidebar's workspace group starts collapsed; expanding it reveals
      // the session row, which is the hand-driven way into this preview.
      await tester.tap(find.text('Ungrouped'));
      await tester.pumpAndSettle();
      expect(find.text('Route session'), findsOneWidget);

      await tester.tap(find.text('Route session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // The card's path traveled the real seats down to the sheet's byte read.
      expect(_sheetImage(), findsOneWidget);
      expect(
        find.text("This file type can't be previewed in the app."),
        findsNothing,
      );
      expect(find.text('Failed to load file preview'), findsNothing);
      expect(repository.byteReads, 1);
      expect(repository.readPaths, <String>['out/hero.png']);
    },
  );
}
