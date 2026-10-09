/// The refused attachment: a Host business rule becomes an explained state,
/// and only a real fault keeps the warning breadcrumb.
library;

import 'dart:typed_data';

import 'package:app/ui/chat/attachment_read.dart';
import 'package:app/ui/chat/chat_controller.dart';
import 'package:domain/model/attachment.dart';
import 'package:domain/model/repository_failure.dart';
import 'package:app/ui/chat/chat_screen.dart' show AttachmentImageRow;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

import 'chat_controller_test.dart' show FakeChatRepository;

/// A repository whose one durable-image read answers however the case needs.
class _AttachmentRepository extends FakeChatRepository {
  _AttachmentRepository(this.answer);

  final Future<AttachmentData> Function() answer;

  @override
  Future<AttachmentData> readAttachment(
    String sessionId,
    String attachmentId,
  ) => answer();
}

const AttachmentRef _ref = AttachmentRef(
  attachmentId: 'sha256:abc',
  mediaType: 'image/png',
  bytes: 69,
  width: 8,
  height: 8,
);

void main() {
  test('the Host\'s refusal is the explained state, not a fault', () async {
    final controller = ChatController(
      _AttachmentRepository(
        () async => throw const RepositoryFailure(
          kAttachmentInvalidCode,
          'Image is not referenced by this session (ATTACHMENT_NOT_REFERENCED)',
        ),
      ),
    );
    addTearDown(controller.dispose);
    await pumpEventQueue();

    final read = await controller.loadAttachmentBytes('s1', _ref);

    expect(read.hasBytes, isFalse);
    expect(read.failure, AttachmentReadFailure.notReferenced);
  });

  test('a transport failure stays an unexplained failure', () async {
    final controller = ChatController(
      _AttachmentRepository(
        () async =>
            throw const RepositoryFailure('gateway/internal', 'socket closed'),
      ),
    );
    addTearDown(controller.dispose);
    await pumpEventQueue();

    final read = await controller.loadAttachmentBytes('s1', _ref);

    expect(read.hasBytes, isFalse);
    expect(read.failure, AttachmentReadFailure.unavailable);
  });

  test('a non-business throw is the same unexplained failure', () async {
    final controller = ChatController(
      _AttachmentRepository(() async => throw StateError('decoded poorly')),
    );
    addTearDown(controller.dispose);
    await pumpEventQueue();

    final read = await controller.loadAttachmentBytes('s1', _ref);

    expect(read.failure, AttachmentReadFailure.unavailable);
  });

  test('bytes come back ready', () async {
    final controller = ChatController(
      _AttachmentRepository(
        () async => AttachmentData(
          ref: _ref,
          data: Uint8List.fromList(const <int>[1, 2, 3]),
        ),
      ),
    );
    addTearDown(controller.dispose);
    await pumpEventQueue();

    final read = await controller.loadAttachmentBytes('s1', _ref);

    expect(read.hasBytes, isTrue);
    expect(read.failure, isNull);
    expect(read.bytes, const <int>[1, 2, 3]);
  });

  testWidgets('a refused attachment explains itself instead of a gap', (
    tester,
  ) async {
    await tester.pumpWidget(
      l10nApp(
        home: Scaffold(
          body: AttachmentImageRow(
            sessionId: 's1',
            ref: _ref,
            loadAttachment: (_, _) async => const AttachmentRead.failed(
              AttachmentReadFailure.notReferenced,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The reader is told why, in the app's own words.
    expect(
      find.text('This image is no longer part of the session'),
      findsOneWidget,
    );
  });

  testWidgets('a transport failure keeps the plain placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      l10nApp(
        home: Scaffold(
          body: AttachmentImageRow(
            sessionId: 's1',
            ref: _ref,
            loadAttachment: (_, _) async =>
                const AttachmentRead.failed(AttachmentReadFailure.unavailable),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('This image is no longer part of the session'),
      findsNothing,
    );
  });
}
