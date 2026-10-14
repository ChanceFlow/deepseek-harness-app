/// File-preview sheet tests: the chat surface's Preview action dispatches a
/// workspace path to the renderer its file type selects — a page of text, an
/// image from the bytes, or a plain statement for a format the app cannot
/// draw. A read the host refuses shows the state the host's code names — not
/// text, over its byte cap, a vanished path — with Retry only where the same
/// read can plausibly succeed later, and the refusal reaches the error log
/// with its code and path.
library;

import 'dart:async';
import 'dart:convert';

import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/workspace_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/config.dart';
// Also re-exports the error-log seam asserted below.
import 'package:app/di/providers.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/platform/pdf_page_renderer.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/file_preview_sheet.dart';
import 'package:app/ui/chat/preview/document_frame.dart';
import 'package:app/ui/chat/tool_row_model.dart'
    show DiffLineKind, EditDiffModel, ToolDiffLine;
import 'package:app/ui/theme/theme.dart';

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

/// A real 1×1 PNG: the signature the sheet sniffs and bytes the decoder reads.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ'
  '/pLvAAAAAElFTkSuQmCC',
);

ChatUiState _state({String path = 'lib/main.dart'}) => ChatUiState(
  sessions: const [SessionSummary(id: 's1', title: 'Alpha', blank: false)],
  selectedSessionId: 's1',
  timeline: [
    TimelineToolCall(
      id: 'c-file',
      name: 'write',
      arguments: '{"path":"$path","content":"print(1);"}',
      result: 'Wrote 10 bytes',
      status: ToolRunStatus.completed,
    ),
  ],
);

/// The shape the repository seam hands the sheet when the host refuses a
/// read: `DshBusinessException` carries the machine code on the wire. Generic
/// in the result so the same carrier serves the text and byte readers.
Future<T> Function(String sessionId, String path) _refusing<T>(String code) {
  return (String sessionId, String path) async {
    throw DshBusinessException(code: code, message: '"$path" refused');
  };
}

/// The byte reader a text-only scenario runs with: the production default,
/// which fails when a test reaches it without wiring a real one.
Future<WorkspaceFileBytes> _noWorkspaceFileBytes(
  String sessionId,
  String path,
) async {
  throw UnsupportedError('workspaceFiles/readBytes is not wired');
}

/// A byte reply carrying [data] for any path, counting its calls through
/// [onCall].
WorkspaceFileBytesReader _bytes(Uint8List data, {void Function()? onCall}) {
  return (String sessionId, String path) async {
    onCall?.call();
    return WorkspaceFileBytes(
      absolutePath: '/workspace/$path',
      version: 'v1',
      offset: 0,
      data: data,
      eof: true,
    );
  };
}

Future<void> _pump(
  WidgetTester tester, {
  required WorkspaceFileReader readWorkspaceFile,
  WorkspaceFileBytesReader? readWorkspaceFileBytes,
  DocumentFrameBuilder? frameBuilder,
  PdfPageRenderer? pdfPageRenderer,
  String path = 'lib/main.dart',
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
          uiState: _state(path: path),
          onAction: (_) {},
          readWorkspaceFile: readWorkspaceFile,
          readWorkspaceFileBytes:
              readWorkspaceFileBytes ?? _noWorkspaceFileBytes,
          documentFrameBuilder: frameBuilder ?? _noDocumentFrame,
          pdfPageRenderer: pdfPageRenderer,
        ),
      ),
    ),
  );
  await tester.pump();
}

/// A pump whose frame is asked for without wiring one: a preview that reached
/// a document without a stand-in says so instead of loading a platform view.
Widget _noDocumentFrame(BuildContext context, PreviewDocument document) =>
    const Text('NO DOCUMENT FRAME WIRED');

/// A PDF renderer stand-in: the platform side a widget test owns none of.
class _FakePdfRenderer extends PdfPageRenderer {
  _FakePdfRenderer({this.pageCount = 2, this.failure});

  final int pageCount;

  /// The reason `open` refuses, or null when it opens the document.
  final PdfRenderFailure? failure;

  int opens = 0;
  int closes = 0;
  final List<int> rendered = <int>[];
  int? lastTargetWidth;

  @override
  PdfRenderFailure? get lastOpenFailure => failure;

  @override
  Future<PdfDocument?> open(Uint8List bytes) async {
    opens += 1;
    if (failure != null) return null;
    return _FakePdfDocument(this);
  }
}

class _FakePdfDocument implements PdfDocument {
  _FakePdfDocument(this._owner);

  final _FakePdfRenderer _owner;

  @override
  int get pageCount => _owner.pageCount;

  @override
  Future<PdfPageImage?> renderPage(
    int index, {
    required int targetWidth,
    required int maxPixels,
  }) async {
    if (index < 0 || index >= pageCount) return null;
    _owner.rendered.add(index);
    _owner.lastTargetWidth = targetWidth;
    return PdfPageImage(bytes: _png, width: 1, height: 1);
  }

  @override
  Future<void> close() async => _owner.closes += 1;
}

/// Expands the file tool row and taps its Preview action.
Future<void> _openPreview(WidgetTester tester) async {
  await tester.tap(find.text('Write'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Preview'));
  await tester.pumpAndSettle();
}

/// The image the sheet itself renders, with the chat surface behind it
/// excluded.
Finder _sheetImage() => find.descendant(
  of: find.byType(FilePreviewSheet),
  matching: find.byType(Image),
);

/// A widget inside the sheet itself: the chat surface behind it renders its
/// own copy-path action on the produced-file row of the same tool call.
Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(FilePreviewSheet), matching: finder);

void main() {
  setUp(() => ErrorLogCollector.instance.clear());

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

  testWidgets('a failure with no host code keeps the generic retryable state', (
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

  testWidgets('a transport failure keeps the generic retryable state', (
    tester,
  ) async {
    await _pump(
      tester,
      readWorkspaceFile: (String sessionId, String path) async {
        throw DshTransportException('socket closed');
      },
    );

    await _openPreview(tester);

    expect(find.text('Failed to load file preview'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a not-text refusal is announced with the path to copy', (
    tester,
  ) async {
    await _pump(
      tester,
      readWorkspaceFile: _refusing('workspace-file/not-text'),
      // The byte fallback finds no image, so the refusal stands.
      readWorkspaceFileBytes: _bytes(Uint8List.fromList(<int>[0x01, 0x02])),
    );

    await _openPreview(tester);

    expect(
      find.text("This file isn't text, so it can't be previewed."),
      findsOneWidget,
    );
    // A binary file never becomes text, so Retry would be a lie; the path is
    // the recourse the reader has left.
    expect(find.text('Retry'), findsNothing);
    expect(_inSheet(find.text('Copy path')), findsOneWidget);
    expect(find.byTooltip('Copy content'), findsNothing);
    expect(_sheetImage(), findsNothing);
  });

  testWidgets('an image path renders the bytes without a text read', (
    tester,
  ) async {
    var textReads = 0;
    var byteReads = 0;
    await _pump(
      tester,
      path: 'assets/logo.png',
      readWorkspaceFile: (String sessionId, String path) async {
        textReads += 1;
        throw UnsupportedError('an image takes no text read');
      },
      readWorkspaceFileBytes: _bytes(_png, onCall: () => byteReads += 1),
    );

    await _openPreview(tester);

    expect(textReads, 0);
    expect(byteReads, 1);
    final Image image = tester.widget<Image>(_sheetImage());
    expect((image.image as MemoryImage).bytes, _png);
    expect(
      find.text("This file type can't be previewed in the app."),
      findsNothing,
    );
  });

  // A renderer-less container and a bare compiled blob: both are declared
  // unrenderable, so neither spends a read.
  for (final String filePath in <String>['bundle.zip', 'firmware.bin']) {
    testWidgets('an unrenderable suffix ($filePath) states it plainly', (
      tester,
    ) async {
      var textReads = 0;
      var byteReads = 0;
      await _pump(
        tester,
        path: filePath,
        readWorkspaceFile: (String sessionId, String path) async {
          textReads += 1;
          throw UnsupportedError('$filePath takes no text read');
        },
        readWorkspaceFileBytes: _bytes(_png, onCall: () => byteReads += 1),
      );

      await _openPreview(tester);

      expect(
        find.text("This file type can't be previewed in the app."),
        findsOneWidget,
      );
      expect(_inSheet(find.text('Copy path')), findsOneWidget);
      // The format cannot change under a read, so neither reader runs.
      expect(find.text('Retry'), findsNothing);
      expect(textReads, 0);
      expect(byteReads, 0);
      expect(_sheetImage(), findsNothing);
    });
  }

  testWidgets('Copy path copies the path the header shows', (tester) async {
    final List<String> copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
        }
        return null;
      },
    );
    await _pump(
      tester,
      path: 'bundle.zip',
      readWorkspaceFile: _refusing('workspace-file/not-found'),
      readWorkspaceFileBytes: _bytes(_png),
    );

    await _openPreview(tester);
    await tester.tap(_inSheet(find.text('Copy path')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(copied, <String>['bundle.zip']);
    expect(find.text('Copied to clipboard'), findsOneWidget);
  });

  testWidgets('a not-text refusal whose bytes are an image renders it', (
    tester,
  ) async {
    await _pump(
      tester,
      path: 'photo',
      readWorkspaceFile: _refusing('workspace-file/not-text'),
      readWorkspaceFileBytes: _bytes(_png),
    );

    await _openPreview(tester);

    // The suffix settled no type, so the host's own facts did: the refusal
    // proved the page is not text, and the bytes name a PNG.
    expect(_sheetImage(), findsOneWidget);
    expect(
      find.text("This file isn't text, so it can't be previewed."),
      findsNothing,
    );
  });

  testWidgets('image bytes with no image signature state it plainly', (
    tester,
  ) async {
    await _pump(
      tester,
      path: 'assets/logo.png',
      readWorkspaceFile: _refusing('workspace-file/not-found'),
      readWorkspaceFileBytes: _bytes(
        Uint8List.fromList(utf8.encode('not an image')),
      ),
    );

    await _openPreview(tester);

    expect(
      find.text("This file type can't be previewed in the app."),
      findsOneWidget,
    );
    expect(_inSheet(find.text('Copy path')), findsOneWidget);
    expect(_sheetImage(), findsNothing);
  });

  testWidgets('an image byte read the host refuses shows its state', (
    tester,
  ) async {
    await _pump(
      tester,
      path: 'assets/logo.png',
      readWorkspaceFile: _refusing('workspace-file/not-found'),
      readWorkspaceFileBytes: _refusing('workspace-file/too-large'),
    );

    await _openPreview(tester);

    expect(find.text('This file is too large to preview.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(_sheetImage(), findsNothing);
  });

  testWidgets('a too-large refusal is announced without Retry', (tester) async {
    await _pump(
      tester,
      readWorkspaceFile: _refusing('workspace-file/too-large'),
    );

    await _openPreview(tester);

    expect(find.text('This file is too large to preview.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('a not-found refusal is announced without Retry', (tester) async {
    await _pump(
      tester,
      readWorkspaceFile: _refusing('workspace-file/not-found'),
    );

    await _openPreview(tester);

    expect(find.text('This file is no longer there.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('a host refusal with no dedicated state still drops Retry', (
    tester,
  ) async {
    // `workspace-file/not-regular-file` (a directory or link) is a refusal the
    // same read repeats, so it must not offer the action that cannot succeed.
    await _pump(
      tester,
      readWorkspaceFile: _refusing('workspace-file/not-regular-file'),
    );

    await _openPreview(tester);

    expect(find.text('Failed to load file preview'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  // The gateway refuses these before any read dispatch: the workspace scope
  // resolves to no Session, the lookup provider is absent, or it disagrees
  // with its strict definition. None can change under an identical retry.
  for (final String code in <String>[
    'gateway/lookup-not-found',
    'gateway/lookup-unavailable',
    'gateway/provider-mismatch',
  ]) {
    testWidgets('a pre-dispatch gateway refusal ($code) drops Retry', (
      tester,
    ) async {
      await _pump(tester, readWorkspaceFile: _refusing(code));

      await _openPreview(tester);

      expect(find.text('Failed to load file preview'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });
  }

  testWidgets('a code this build does not read keeps Retry', (tester) async {
    // A newer host may refuse for a reason this build has no state for; the
    // failure is not known to be final, so the retry stays.
    await _pump(
      tester,
      readWorkspaceFile: _refusing('workspace-file/too-many-lines'),
    );

    await _openPreview(tester);

    expect(find.text('Failed to load file preview'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
    'a refused read records its host code and path in the error log',
    (tester) async {
      await _pump(
        tester,
        readWorkspaceFile: _refusing('workspace-file/too-large'),
      );

      await _openPreview(tester);

      final ErrorLogEntry entry = ErrorLogCollector.instance.entries
          .singleWhere(
            (ErrorLogEntry entry) =>
                entry.context?['component'] == 'filePreview',
          );
      expect(entry.context?['code'], 'workspace-file/too-large');
      expect(entry.context?['path'], 'lib/main.dart');
      expect(entry.context?['sessionId'], 's1');
      // The app can explain this refusal, so it is not an app error.
      expect(entry.level, ErrorLogLevel.warning);
    },
  );

  testWidgets('an unexplained read failure records at error level', (
    tester,
  ) async {
    await _pump(
      tester,
      readWorkspaceFile: (String sessionId, String path) async {
        throw Exception('workspaceFiles/read failed');
      },
    );

    await _openPreview(tester);

    final ErrorLogEntry entry = ErrorLogCollector.instance.entries.singleWhere(
      (ErrorLogEntry entry) => entry.context?['component'] == 'filePreview',
    );
    expect(entry.context?['code'], 'none');
    expect(entry.context?['path'], 'lib/main.dart');
    expect(entry.level, ErrorLogLevel.error);
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

    // The notice is the pin's in-preview panel, not a Material chip:
    // `bg-layer-2`, `border: 0`, `--dsw-radius-lg` and
    // `--dsw-elevation-prominent` (`office/FontNotice.module.css` `.panel`,
    // :14-31).
    final scheme = Theme.of(tester.element(find.byType(FilePreviewSheet)))
        .colorScheme;
    final notice = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('Previewing first 40 lines'),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = notice.decoration! as BoxDecoration;
    expect(decoration.color, scheme.bgLayer2);
    expect(decoration.borderRadius, BorderRadius.circular(kRadiusLg));
    expect(decoration.boxShadow, DshElevation.prominent(scheme));
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
    expect(find.text('Retry'), findsNothing);
    expect(find.byTooltip('Copy content'), findsNothing);
  });

  testWidgets(
    'renders diff and full file segmented tabs when initialDiff is provided',
    (tester) async {
      const diff = EditDiffModel(
        filePath: 'lib/diff_file.dart',
        oldString: 'old = 1;',
        newString: 'new = 2;',
        lines: [
          ToolDiffLine(kind: DiffLineKind.delete, text: 'old = 1;'),
          ToolDiffLine(kind: DiffLineKind.insert, text: 'new = 2;'),
        ],
      );

      await tester.pumpWidget(
        l10nApp(
          home: Scaffold(
            body: FilePreviewSheet(
              sessionId: 's1',
              path: 'lib/diff_file.dart',
              initialDiff: diff,
              readFile: (sessionId, path) async => const WorkspaceFileContent(
                absolutePath: '/workspace/lib/diff_file.dart',
                version: 'v1',
                text: 'final fullFile = true;',
                offset: 1,
                lines: 1,
                eof: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Renders the segmented buttons
      expect(find.text('Diff'), findsOneWidget);
      expect(find.text('Full file'), findsOneWidget);

      // Initial tab is Diff
      expect(find.text('old = 1;'), findsOneWidget);
      expect(find.text('new = 2;'), findsOneWidget);
      expect(find.text('final fullFile = true;'), findsNothing);

      // Tap 'Full file' tab
      await tester.tap(find.text('Full file'));
      await tester.pumpAndSettle();

      expect(find.text('final fullFile = true;'), findsOneWidget);
    },
  );

  group('document renderers', () {
    testWidgets('an HTML path renders a static document, not its source', (
      tester,
    ) async {
      final frames = <PreviewDocument>[];
      var textReads = 0;
      await _pump(
        tester,
        path: 'docs/report.html',
        readWorkspaceFile: (sessionId, path) async {
          textReads += 1;
          return const WorkspaceFileContent(
            absolutePath: '/workspace/docs/report.html',
            version: 'v1',
            text: '<h1>SOURCE ONLY</h1>',
            offset: 1,
            lines: 1,
            eof: true,
          );
        },
        readWorkspaceFileBytes: _bytes(
          Uint8List.fromList(
            utf8.encode(
              '<!doctype html><html><head><title>t</title></head><body>'
              '<h1>RENDERED</h1><script>alert(1)</script>'
              '<a href="https://example.com">link</a></body></html>',
            ),
          ),
        ),
        frameBuilder: (context, document) {
          frames.add(document);
          return const Text('DOCUMENT FRAME');
        },
      );

      await _openPreview(tester);

      expect(find.text('DOCUMENT FRAME'), findsOneWidget);
      expect(find.textContaining('SOURCE ONLY'), findsNothing);
      expect(textReads, 0);
      final html = frames.single.html;
      // The static mode: the policy travels with the document, and what could
      // run or load is gone.
      expect(html, contains('Content-Security-Policy'));
      expect(html, contains("default-src 'none'"));
      expect(html, contains('RENDERED'));
      expect(html, isNot(contains('alert(1)')));
      expect(html, isNot(contains('example.com')));
      expect(frames.single.semanticLabel, 'HTML document preview');
    });

    testWidgets('the viewer chooser switches a rendered HTML file to source', (
      tester,
    ) async {
      final frames = <PreviewDocument>[];
      var textReads = 0;
      await _pump(
        tester,
        path: 'docs/report.html',
        readWorkspaceFile: (sessionId, path) async {
          textReads += 1;
          return const WorkspaceFileContent(
            absolutePath: '/workspace/docs/report.html',
            version: 'v1',
            text: 'SOURCE ONLY',
            offset: 1,
            lines: 1,
            eof: true,
          );
        },
        readWorkspaceFileBytes: _bytes(
          Uint8List.fromList(utf8.encode('<html><body>RENDERED</body></html>')),
        ),
        frameBuilder: (context, document) {
          frames.add(document);
          return const Text('DOCUMENT FRAME');
        },
      );

      await _openPreview(tester);

      // Two implementations claim the path, which is what offers the chooser:
      // the HTML renderer, and the plain-text viewer the reference keeps as
      // its fallback band.
      expect(find.text('HTML'), findsOneWidget);
      expect(find.text('Source'), findsOneWidget);

      await tester.tap(find.text('Source'));
      await tester.pumpAndSettle();

      expect(find.text('DOCUMENT FRAME'), findsNothing);
      expect(textReads, 1);
      expect(find.textContaining('SOURCE ONLY'), findsOneWidget);
    });

    testWidgets('an SVG path renders through the frame as an image document', (
      tester,
    ) async {
      final frames = <PreviewDocument>[];
      await _pump(
        tester,
        path: 'assets/logo.svg',
        readWorkspaceFile: (sessionId, path) async {
          throw DshBusinessException(
            code: 'workspace-file/not-text',
            message: 'refused',
          );
        },
        readWorkspaceFileBytes: _bytes(
          Uint8List.fromList(
            utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"></svg>'),
          ),
        ),
        frameBuilder: (context, document) {
          frames.add(document);
          return const Text('DOCUMENT FRAME');
        },
      );

      await _openPreview(tester);

      expect(find.text('DOCUMENT FRAME'), findsOneWidget);
      expect(frames.single.html, contains('data:image/svg+xml;base64,'));
      expect(frames.single.semanticLabel, 'Image preview: assets/logo.svg');
      // An SVG keeps its source view: the reference does not declare it
      // binary, because its XML is readable text.
      expect(find.text('Source'), findsOneWidget);
    });

    testWidgets('HTML bytes that are not UTF-8 state it plainly', (
      tester,
    ) async {
      await _pump(
        tester,
        path: 'docs/report.html',
        readWorkspaceFile: (sessionId, path) async {
          throw StateError('the text lane must not be read for an HTML file');
        },
        readWorkspaceFileBytes: _bytes(
          Uint8List.fromList(<int>[0xFF, 0xFE, 0x3C, 0x68, 0x74]),
        ),
        frameBuilder: (context, document) => const Text('DOCUMENT FRAME'),
      );

      await _openPreview(tester);

      expect(
        find.text('This HTML document could not be previewed.'),
        findsOneWidget,
      );
      expect(find.text('DOCUMENT FRAME'), findsNothing);
      // The bytes are not valid UTF-8 whatever happens next, so no Retry.
      expect(find.text('Retry'), findsNothing);
    });
  });

  group('spreadsheet renderers', () {
    testWidgets('a CSV path renders a grid and keeps its source view', (
      tester,
    ) async {
      var textReads = 0;
      await _pump(
        tester,
        path: 'reports/data.csv',
        readWorkspaceFile: (sessionId, path) async {
          textReads += 1;
          return const WorkspaceFileContent(
            absolutePath: '/workspace/reports/data.csv',
            version: 'v1',
            text: 'name,count',
            offset: 1,
            lines: 1,
            eof: true,
          );
        },
        readWorkspaceFileBytes: _bytes(
          Uint8List.fromList(utf8.encode('name,count\nalpha,two\n')),
        ),
      );

      await _openPreview(tester);

      // The grid: the column letters, the row numbers and the cells.
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('count'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      // A delimited file is readable text, so the chooser offers both.
      expect(find.text('Spreadsheet'), findsOneWidget);
      expect(find.text('Source'), findsOneWidget);
      expect(textReads, 0);

      await tester.tap(find.text('Source'));
      await tester.pumpAndSettle();

      expect(textReads, 1);
      expect(find.text('alpha'), findsNothing);
    });

    testWidgets('bytes that are not a workbook state it with Retry', (
      tester,
    ) async {
      var byteReads = 0;
      await _pump(
        tester,
        path: 'reports/book.xlsx',
        readWorkspaceFile: (sessionId, path) async {
          throw StateError('a workbook is never read as text');
        },
        readWorkspaceFileBytes: (sessionId, path) async {
          byteReads += 1;
          return WorkspaceFileBytes(
            absolutePath: '/workspace/reports/book.xlsx',
            version: 'v1',
            offset: 0,
            data: Uint8List.fromList(utf8.encode('not a zip')),
            eof: true,
          );
        },
      );

      await _openPreview(tester);

      expect(
        find.text(
          'This spreadsheet could not be opened. Check its format, contents, or password protection.',
        ),
        findsOneWidget,
      );
      // The file may have been rewritten on the host since the read, which is
      // why the reference keeps its Retry here.
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(byteReads, 2);
    });
  });

  group('pdf renderer', () {
    testWidgets('a PDF path draws its pages through the injected renderer', (
      tester,
    ) async {
      final renderer = _FakePdfRenderer(pageCount: 2);
      await _pump(
        tester,
        path: 'docs/report.pdf',
        readWorkspaceFile: (sessionId, path) async {
          throw StateError('a PDF is never read as text');
        },
        readWorkspaceFileBytes: _bytes(_png),
        pdfPageRenderer: renderer,
      );

      await _openPreview(tester);

      expect(renderer.opens, 1);
      // The list asks for the pages it builds, in order, and asks at the width
      // the reader will see rather than the page's 72 dpi size.
      expect(renderer.rendered, orderedEquals(<int>[0, 1]));
      expect(renderer.lastTargetWidth, isNotNull);
      expect(renderer.lastTargetWidth! > 0, isTrue);
      // Both pages fit the sheet, so both are drawn.
      expect(_sheetImage(), findsNWidgets(2));
      // A PDF is declared binary, so it has no source alternative.
      expect(find.text('Source'), findsNothing);
    });

    testWidgets('a long document draws the pages it shows, not all of them', (
      tester,
    ) async {
      final renderer = _FakePdfRenderer(pageCount: 12);
      await _pump(
        tester,
        path: 'docs/long.pdf',
        readWorkspaceFile: (sessionId, path) async {
          throw StateError('a PDF is never read as text');
        },
        readWorkspaceFileBytes: _bytes(_png),
        pdfPageRenderer: renderer,
      );

      await _openPreview(tester);

      expect(renderer.rendered, isNotEmpty);
      expect(renderer.rendered.length < 12, isTrue);
    });

    testWidgets('an encrypted PDF says so and can be retried', (tester) async {
      final renderer = _FakePdfRenderer(failure: PdfRenderFailure.password);
      await _pump(
        tester,
        path: 'docs/locked.pdf',
        readWorkspaceFile: (sessionId, path) async {
          throw StateError('a PDF is never read as text');
        },
        readWorkspaceFileBytes: _bytes(_png),
        pdfPageRenderer: renderer,
      );

      await _openPreview(tester);

      expect(
        find.text('This PDF requires a password; previews are not supported.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(renderer.opens, 2);
    });

    testWidgets('a document the renderer cannot open states it plainly', (
      tester,
    ) async {
      await _pump(
        tester,
        path: 'docs/broken.pdf',
        readWorkspaceFile: (sessionId, path) async {
          throw StateError('a PDF is never read as text');
        },
        readWorkspaceFileBytes: _bytes(_png),
        pdfPageRenderer: _FakePdfRenderer(failure: PdfRenderFailure.invalid),
      );

      await _openPreview(tester);

      expect(find.text('This PDF could not be displayed.'), findsOneWidget);
    });
  });
}
