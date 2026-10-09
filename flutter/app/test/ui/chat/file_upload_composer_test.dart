/// Composer file attachment: the attach-file pick, the attachment strip's
/// upload states, the send refusal for an unsettled file, and the controller
/// path that stages a receipt for the next prompt.
library;

import 'dart:typed_data';

import 'package:domain/model/attachment.dart';
import 'package:domain/model/file_upload.dart';
import 'package:domain/model/repository_failure.dart';
import 'package:domain/model/skills.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/platform/document_picker.dart';
import 'package:app/ui/chat/chat_controller.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';

import '../../l10n_app.dart';
import 'chat_controller_test.dart' show FakeChatRepository;

Future<void> _settle() async {
  await pumpEventQueue();
  await Future<void>.delayed(
    kUiPublishWindow + const Duration(milliseconds: 16),
  );
  await pumpEventQueue();
}

Future<void> _pumpComposer(
  WidgetTester tester, {
  required List<ChatAction> actions,
  List<String>? sent,
  List<PendingFile> pendingFiles = const <PendingFile>[],
  List<PendingImage> pendingImages = const <PendingImage>[],
  DocumentPicker? onPickFile,
}) {
  tester.view.physicalSize = const Size(800, 1280);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    ProviderScope(
      child: l10nApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: ComposerBar(
            enabled: true,
            isSending: false,
            running: false,
            pendingImages: pendingImages,
            imageLimits: const ImageLimits(),
            pendingFiles: pendingFiles,
            skills: const <SkillEntry>[],
            onPickFile: onPickFile,
            onAction: actions.add,
            onSend: (String text) async {
              sent?.add(text);
              return true;
            },
          ),
        ),
      ),
    ),
  );
}

/// A repository double serving the staged file upload; everything else is the
/// shared chat double.
class _FileUploadRepository extends FakeChatRepository {
  UploadedFile? nextUpload;
  Object? uploadFailure;
  final List<String> uploadedSessionIds = <String>[];

  @override
  Future<UploadedFile> uploadFile({
    required String sessionId,
    required String name,
    required Uint8List bytes,
  }) async {
    uploadedSessionIds.add(sessionId);
    final Object? failure = uploadFailure;
    if (failure != null) throw failure;
    return nextUpload!;
  }
}

void main() {
  testWidgets(
    'the attach-file row hands the picked document to the controller',
    (tester) async {
      final actions = <ChatAction>[];
      final caps = <int>[];
      await _pumpComposer(
        tester,
        actions: actions,
        onPickFile: ({required int maxBytes}) async {
          caps.add(maxBytes);
          return PickedDocument(
            name: 'notes.pdf',
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
          );
        },
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      // The roster carries the pin's 400px height (`MenuView.tsx:26-40`), so
      // the attach row at its tail is reached by scrolling the card.
      await tester.scrollUntilVisible(
        find.text('Attach a file'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Attach a file'), findsOneWidget);
      await tester.tap(find.text('Attach a file'));
      await tester.pumpAndSettle();

      final picked = actions.whereType<FilePicked>().single;
      expect(picked.name, 'notes.pdf');
      expect(picked.bytes, <int>[1, 2, 3]);
      // The pick carries the phone's cap so the platform side refuses an
      // oversized document before reading it.
      expect(caps.single, FileUploadLimits.maxFileBytes);
    },
  );

  testWidgets('an oversized pick states the localized cap on the error path', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pumpComposer(
      tester,
      actions: actions,
      onPickFile: ({required int maxBytes}) async {
        throw const DocumentPickException(
          'document is 9000000 bytes; the limit is 8388608',
          code: 'too_large',
        );
      },
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Attach a file'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Attach a file'));
    await tester.pumpAndSettle();

    expect(actions.whereType<FilePicked>(), isEmpty);
    expect(actions.whereType<FilePickError>().single.message, contains('8 MB'));
  });

  testWidgets('a failed upload states its reason in the attachment strip', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pumpComposer(
      tester,
      actions: actions,
      pendingFiles: const <PendingFile>[
        PendingFile(
          id: 'file-1',
          name: 'notes.pdf',
          byteSize: 2048,
          status: PendingFileStatus.failed,
          failureReason: 'session/attachment-invalid: cannot store files',
        ),
      ],
    );

    expect(find.text('notes.pdf'), findsOneWidget);
    expect(find.text('Upload failed'), findsOneWidget);
    expect(
      find.text('session/attachment-invalid: cannot store files'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Remove notes.pdf'));
    await tester.pump();
    expect(actions.whereType<RemovePendingFile>().single.id, 'file-1');
  });

  testWidgets('an uploading file shows its state and the in-flight bar', (
    tester,
  ) async {
    await _pumpComposer(
      tester,
      actions: <ChatAction>[],
      pendingFiles: const <PendingFile>[
        PendingFile(id: 'file-1', name: 'notes.pdf', byteSize: 2048),
      ],
    );

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Uploading · 2.0 KB'), findsOneWidget);
  });

  testWidgets('a send with an unsettled file is refused, not dropped', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    final sent = <String>[];
    await _pumpComposer(
      tester,
      actions: actions,
      sent: sent,
      pendingFiles: const <PendingFile>[
        PendingFile(
          id: 'file-1',
          name: 'notes.pdf',
          byteSize: 2048,
          status: PendingFileStatus.failed,
          failureReason: 'session/attachment-invalid: refused',
        ),
      ],
    );
    await tester.enterText(find.byType(TextField), 'read this');
    await tester.pump();

    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    // Nothing was submitted, and the composer said which attachment held it.
    expect(sent, isEmpty);
    expect(
      actions.whereType<FilePickError>().single.message,
      contains('notes.pdf'),
    );
  });

  testWidgets('a host command that refuses attachments names the file', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pumpComposer(
      tester,
      actions: actions,
      pendingFiles: const <PendingFile>[
        PendingFile(
          id: 'file-1',
          name: 'notes.pdf',
          byteSize: 2048,
          status: PendingFileStatus.ready,
          upload: UploadedFile(
            receiptId: 'receipt-7',
            attachmentId: 'sha256:file-a',
            name: 'notes.pdf',
            byteSize: 2048,
          ),
        ),
      ],
    );
    await tester.enterText(find.byType(TextField), '/compact');
    await tester.pump();

    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    // The Host's one attachment-acceptance flag governs the receipt too, and
    // the refusal names what the reader actually attached.
    expect(
      actions.whereType<CommandImageRefusal>().single.message,
      contains('/compact does not accept attachments'),
    );
  });

  testWidgets('a ready file does not hold the send', (tester) async {
    final actions = <ChatAction>[];
    final sent = <String>[];
    await _pumpComposer(
      tester,
      actions: actions,
      sent: sent,
      pendingFiles: const <PendingFile>[
        PendingFile(
          id: 'file-1',
          name: 'notes.pdf',
          byteSize: 2048,
          status: PendingFileStatus.ready,
          upload: UploadedFile(
            receiptId: 'receipt-7',
            attachmentId: 'sha256:file-a',
            name: 'notes.pdf',
            byteSize: 2048,
          ),
        ),
      ],
    );

    expect(find.text('Uploaded · 2.0 KB'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'read this');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(sent.single, 'read this');
    expect(actions.whereType<FilePickError>(), isEmpty);
  });

  test('a successful upload lands a ready row with its receipt', () async {
    final repository = _FileUploadRepository()
      ..nextUpload = const UploadedFile(
        receiptId: 'receipt-7',
        attachmentId: 'sha256:file-a',
        name: 'notes.pdf',
        byteSize: 2,
      );
    final controller = ChatController(repository);
    await pumpEventQueue();
    controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
    await _settle();

    controller.onAction(
      FilePicked(name: 'notes.pdf', bytes: Uint8List.fromList(<int>[1, 2])),
    );
    // The row exists before the call settles.
    expect(
      controller.state.pendingFiles.single.status,
      PendingFileStatus.uploading,
    );
    await _settle();

    final row = controller.state.pendingFiles.single;
    expect(row.status, PendingFileStatus.ready);
    expect(row.upload?.receiptId, 'receipt-7');
    expect(repository.uploadedSessionIds, <String>[
      FakeChatRepository.initialSession.id,
    ]);

    // A ready row rides the next prompt as a receipt, then leaves the strip.
    controller.onAction(const SendPrompt('read this'));
    await _settle();
    final sent = repository.sentMessages.single;
    expect(sent.text, 'read this');
    expect(sent.files.single.receiptId, 'receipt-7');
    expect(controller.state.pendingFiles, isEmpty);
  });

  test('a failed upload keeps the row with the host reason', () async {
    final repository = _FileUploadRepository()
      ..uploadFailure = const RepositoryFailure(
        'session/attachment-invalid',
        'The mounted attachment provider cannot store verbatim files.',
      );
    final controller = ChatController(repository);
    await pumpEventQueue();
    controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
    await _settle();

    controller.onAction(
      FilePicked(name: 'notes.pdf', bytes: Uint8List.fromList(<int>[1, 2])),
    );
    await _settle();

    final row = controller.state.pendingFiles.single;
    expect(row.status, PendingFileStatus.failed);
    expect(row.failureReason, contains('session/attachment-invalid'));
    expect(row.failureReason, contains('cannot store verbatim files'));

    // The failure holds the send: the receipt was never staged, so the prompt
    // must not silently drop the attachment.
    var settled = true;
    controller.onAction(
      SendPrompt('read this', onSettled: (bool accepted) => settled = accepted),
    );
    await _settle();
    expect(settled, isFalse);
    expect(repository.sentMessages, isEmpty);
    expect(
      controller.state.pendingFiles.single.status,
      PendingFileStatus.failed,
    );
  });
}
