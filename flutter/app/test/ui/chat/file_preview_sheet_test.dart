/// File-preview sheet tests: the chat surface's Preview action reads a
/// workspace file through the repository seam and renders it; a read
/// failure, a binary file, and a host-truncated window each get their own
/// localized state.
library;

import 'dart:async';

import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/workspace_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/file_preview_sheet.dart';

import '../../l10n_app.dart';

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

class _NeverSocket implements DshEventSocket {
  final StreamController<ServerRequest> _frames =
      StreamController<ServerRequest>.broadcast();

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    onOpen?.call();
    return _frames.stream;
  }
}

const _writeCall = TimelineToolCall(
  id: 'c-file',
  name: 'write',
  arguments: '{"path":"lib/main.dart","content":"print(1);"}',
  result: 'Wrote 10 bytes',
  status: ToolRunStatus.completed,
);

ChatUiState _state() => const ChatUiState(
  sessions: [SessionSummary(id: 's1', title: 'Alpha', blank: false)],
  selectedSessionId: 's1',
  timeline: [_writeCall],
);

Future<void> _pump(
  WidgetTester tester, {
  required WorkspaceFileReader readWorkspaceFile,
}) async {
  tester.view.physicalSize = const Size(800, 1280);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dshRpcClientProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_FakeRpc()),
        dshEventSocketProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_NeverSocket()),
      ],
      child: l10nApp(
        home: ChatScreen(
          uiState: _state(),
          onAction: (_) {},
          readWorkspaceFile: readWorkspaceFile,
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Expands the file tool row and taps its Preview action.
Future<void> _openPreview(WidgetTester tester) async {
  await tester.tap(find.text('Write'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Preview'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('preview reads the row path and renders the file content', (
    tester,
  ) async {
    String? requestedSession;
    String? requestedPath;
    await _pump(
      tester,
      readWorkspaceFile: (String sessionId, String path) async {
        requestedSession = sessionId;
        requestedPath = path;
        return const WorkspaceFileContent(
          absolutePath: '/workspace/lib/main.dart',
          version: 'v1',
          text: 'PREVIEWED FILE BODY',
          offset: 1,
          lines: 1,
          eof: true,
        );
      },
    );

    await _openPreview(tester);

    expect(requestedSession, 's1');
    expect(requestedPath, 'lib/main.dart');
    // The fenced code surface carries the file text; the args body in the
    // row never says this sentence.
    expect(find.textContaining('PREVIEWED FILE BODY'), findsOneWidget);
    expect(find.byTooltip('Copy content'), findsOneWidget);
  });

  testWidgets('a read failure shows the localized preview error', (
    tester,
  ) async {
    await _pump(
      tester,
      readWorkspaceFile: (String sessionId, String path) async {
        throw Exception('workspaceFiles/read failed');
      },
    );

    await _openPreview(tester);

    expect(find.text('Failed to load file preview'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a truncated window reports the paged line count', (
    tester,
  ) async {
    await _pump(
      tester,
      readWorkspaceFile: (String sessionId, String path) async =>
          const WorkspaceFileContent(
            absolutePath: '/workspace/lib/main.dart',
            version: 'v1',
            text: 'partial body',
            offset: 1,
            lines: 40,
            eof: false,
          ),
    );

    await _openPreview(tester);

    expect(find.text('Previewing first 40 lines'), findsOneWidget);
  });

  testWidgets('a binary file is announced instead of rendered', (tester) async {
    await _pump(
      tester,
      readWorkspaceFile: (String sessionId, String path) async =>
          const WorkspaceFileContent(
            absolutePath: '/workspace/blob.bin',
            version: 'v1',
            text: 'abc\u0000def',
            offset: 1,
            lines: 1,
            eof: true,
          ),
    );

    await _openPreview(tester);

    expect(
      find.text("This file isn't text, so it can't be previewed."),
      findsOneWidget,
    );
    expect(find.byTooltip('Copy content'), findsNothing);
  });
}
