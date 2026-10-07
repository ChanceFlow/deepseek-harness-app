/// The composer's `@` mention picker, backed by `fileReferences/list`.
///
/// The grammar group mirrors the shared browser-safe token grammar
/// (`reference/deepseek-harness/packages/context/file-reference/src/
/// grammar.ts`); the controller and composer groups drive the real
/// [ChatController] and the real [ChatScreen] over the shared
/// [FakeChatRepository], so the debounce, the sequence guard and the insertion
/// are exercised through their production entry paths.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/chat/chat_controller.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/file_reference_picker.dart';
import 'package:domain/model/file_reference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';
import 'chat_controller_test.dart';
import 'chat_local_state_fake.dart';

const FileReferenceCandidate _srcDirectory = FileReferenceCandidate(
  path: 'src',
  kind: FileReferenceKind.directory,
);
const FileReferenceCandidate _mainFile = FileReferenceCandidate(
  path: 'src/main.dart',
  kind: FileReferenceKind.file,
);

/// [FakeChatRepository] whose `fileReferences/list` answers can be delayed per
/// query, so a superseded answer's arrival order is under test control.
class _RacingRepository extends FakeChatRepository {
  final Map<String, Duration> delays = <String, Duration>{};

  @override
  Future<List<FileReferenceCandidate>> listFileReferences(
    String sessionId,
    String query,
  ) async {
    final delay = delays[query];
    if (delay != null) await Future<void>.delayed(delay);
    return super.listFileReferences(sessionId, query);
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(kUiPublishWindow + const Duration(milliseconds: 16));
  await tester.pump();
}

void main() {
  group('@ token grammar', () {
    test('a plain token runs to the caret', () {
      final token = activeFileReferenceToken('look at @src/ma', 15);
      expect(token, isNotNull);
      expect(token!.prefix, '@src/ma');
      expect(token.query, 'src/ma');
      expect(token.quoted, isFalse);
      expect(token.startAt(15), 8);
    });

    test('an @ inside another token is not a trigger', () {
      expect(activeFileReferenceToken('mail foo@bar', 12), isNull);
      expect(activeFileReferenceToken('nothing here', 12), isNull);
      // A token the reader closed with whitespace stays closed.
      expect(activeFileReferenceToken('see @src main', 13), isNull);
    });

    test('a quoted token keeps its whitespace', () {
      final token = activeFileReferenceToken('see @"my docs/a', 15);
      expect(token, isNotNull);
      expect(token!.prefix, '@"my docs/a');
      expect(token.query, 'my docs/a');
      expect(token.quoted, isTrue);
    });
  });

  group('mention text', () {
    test('a file mention completes, a directory mention stays open', () {
      expect(fileReferenceMention(_mainFile), '@src/main.dart');
      expect(fileReferenceMention(_srcDirectory), '@src/');
    });

    test(
      'whitespace quotes the path, and a directory keeps the quote open',
      () {
        const spacedFile = FileReferenceCandidate(
          path: 'my docs/notes.txt',
          kind: FileReferenceKind.file,
        );
        const spacedDirectory = FileReferenceCandidate(
          path: 'my docs',
          kind: FileReferenceKind.directory,
        );
        expect(fileReferenceMention(spacedFile), '@"my docs/notes.txt"');
        expect(fileReferenceMention(spacedDirectory), '@"my docs/');
        // An explicitly opened quote is preserved even when unnecessary.
        expect(
          fileReferenceMention(_mainFile, preserveQuote: true),
          '@"src/main.dart"',
        );
      },
    );

    test('a path the grammar cannot represent has no mention', () {
      const unsafe = FileReferenceCandidate(
        path: 'a"b',
        kind: FileReferenceKind.file,
      );
      expect(fileReferenceMention(unsafe), isNull);
    });

    test(
      'a pick replaces the live token and separates a completed mention',
      () {
        final token = activeFileReferenceToken('look at @src/ma', 15)!;
        final applied = applyFileReferencePick(
          draft: 'look at @src/ma',
          cursor: 15,
          token: token,
          candidate: _mainFile,
        );
        expect(applied, isNotNull);
        expect(applied!.text, 'look at @src/main.dart ');
        expect(applied.caret, 'look at @src/main.dart '.length);
      },
    );

    test('an existing separator is not doubled', () {
      final token = activeFileReferenceToken('@src/ma and more', 7)!;
      final applied = applyFileReferencePick(
        draft: '@src/ma and more',
        cursor: 7,
        token: token,
        candidate: _mainFile,
      );
      expect(applied!.text, '@src/main.dart and more');
    });

    test('a directory pick leaves the token open for the next level', () {
      final token = activeFileReferenceToken('@s', 2)!;
      final applied = applyFileReferencePick(
        draft: '@s',
        cursor: 2,
        token: token,
        candidate: _srcDirectory,
      );
      expect(applied!.text, '@src/');
      expect(applied.caret, 5);
    });
  });

  group('controller @ queries', () {
    test('a keystroke burst collapses into one pull', () async {
      final repository = FakeChatRepository()
        ..fileReferenceRoster = <String, List<FileReferenceCandidate>>{
          'src': const <FileReferenceCandidate>[_mainFile],
        };
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await pumpEventQueue();
      controller.onAction(const SelectSession('session-1'));
      await pumpEventQueue();

      controller.onAction(const UpdateFileReferences('s'));
      controller.onAction(const UpdateFileReferences('sr'));
      controller.onAction(const UpdateFileReferences('src'));
      await Future<void>.delayed(
        kFileReferenceDebounce + const Duration(milliseconds: 40),
      );

      expect(repository.fileReferenceCalls, <(String, String)>[
        ('session-1', 'src'),
      ]);
      expect(controller.state.fileReferences?.query, 'src');
      expect(
        controller.state.fileReferences?.candidates,
        const <FileReferenceCandidate>[_mainFile],
      );
    });

    test('closing the token cancels a pending query', () async {
      final repository = FakeChatRepository()
        ..fileReferenceRoster = <String, List<FileReferenceCandidate>>{
          'src': const <FileReferenceCandidate>[_mainFile],
        };
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await pumpEventQueue();
      controller.onAction(const SelectSession('session-1'));
      await pumpEventQueue();

      controller.onAction(const UpdateFileReferences('src'));
      controller.onAction(const UpdateFileReferences(null));
      await Future<void>.delayed(
        kFileReferenceDebounce + const Duration(milliseconds: 40),
      );

      expect(repository.fileReferenceCalls, isEmpty);
      expect(controller.state.fileReferences, isNull);
    });

    test('a superseded answer never publishes', () async {
      final repository = _RacingRepository()
        ..delays['sr'] = const Duration(milliseconds: 300)
        ..fileReferenceRoster = <String, List<FileReferenceCandidate>>{
          'sr': const <FileReferenceCandidate>[_srcDirectory],
          'src': const <FileReferenceCandidate>[_mainFile],
        };
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await pumpEventQueue();
      controller.onAction(const SelectSession('session-1'));
      await pumpEventQueue();

      controller.onAction(const UpdateFileReferences('sr'));
      // The reader keeps typing before the slow answer lands: the newer
      // query's answer is the only one that may stand.
      await Future<void>.delayed(const Duration(milliseconds: 220));
      controller.onAction(const UpdateFileReferences('src'));
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(controller.state.fileReferences?.query, 'src');
      expect(
        controller.state.fileReferences?.candidates,
        const <FileReferenceCandidate>[_mainFile],
      );
    });

    test('a refused pull closes the menu instead of failing loud', () async {
      // An empty roster: every query answers `fileReferences/list unavailable`.
      final repository = FakeChatRepository();
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await pumpEventQueue();
      controller.onAction(const SelectSession('session-1'));
      await pumpEventQueue();

      controller.onAction(const UpdateFileReferences('src'));
      await Future<void>.delayed(
        kFileReferenceDebounce + const Duration(milliseconds: 40),
      );

      expect(controller.state.fileReferences?.query, 'src');
      expect(controller.state.fileReferences?.candidates, isEmpty);
      expect(controller.state.errorMessage, isNull);
    });
  });

  group('composer picker', () {
    late FakeChatRepository repository;
    late ChatController controller;

    Future<void> pump(WidgetTester tester) async {
      repository = FakeChatRepository()
        ..fileReferenceRoster = <String, List<FileReferenceCandidate>>{
          '': const <FileReferenceCandidate>[_srcDirectory],
          's': const <FileReferenceCandidate>[_srcDirectory],
          'src/': const <FileReferenceCandidate>[_mainFile],
          'src/ma': const <FileReferenceCandidate>[_mainFile],
        };
      controller = ChatController(repository);
      addTearDown(controller.dispose);
      // One local-state instance for the whole run: a fresh instance per
      // rebuild would read as a session-state swap and re-restore the draft.
      final localState = FakeChatLocalState();
      await tester.pumpWidget(
        ProviderScope(
          child: l10nApp(
            home: StreamBuilder<ChatUiState>(
              stream: controller.uiState,
              builder: (context, snapshot) => ChatScreen(
                uiState: snapshot.data ?? const ChatUiState(),
                onAction: controller.onAction,
                localState: localState,
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
      await _settle(tester);
    }

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
      await tester.pump(
        kFileReferenceDebounce + const Duration(milliseconds: 16),
      );
      await _settle(tester);
    }

    testWidgets('typing @ offers the file candidates and picking inserts one', (
      tester,
    ) async {
      await pump(tester);
      final l10n = lookupAppLocalizations(const Locale('en'));

      await type(tester, '@');
      // The group label and both candidates: a directory row keeps its
      // trailing slash, a file names its parent.
      expect(find.text(l10n.fileReferenceSectionTitle), findsOneWidget);
      expect(find.text('src/'), findsOneWidget);

      await type(tester, '@src/ma');
      expect(find.text('main.dart'), findsOneWidget);
      expect(find.text('src'), findsOneWidget);

      await tester.tap(find.text('main.dart'));
      await tester.pump();

      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        '@src/main.dart ',
      );
      // A completed mention closes the menu.
      expect(find.text('main.dart'), findsNothing);
    });

    testWidgets('picking a directory stays open on the level it entered', (
      tester,
    ) async {
      await pump(tester);

      await type(tester, '@');
      await tester.tap(find.text('src/'));
      await tester.pump();
      await tester.pump(
        kFileReferenceDebounce + const Duration(milliseconds: 16),
      );
      await _settle(tester);

      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        '@src/',
      );
      // The menu shows the directory just entered, not the one picked.
      expect(find.text('main.dart'), findsOneWidget);
      expect(repository.fileReferenceCalls.last, ('session-1', 'src/'));
    });

    testWidgets('a keystroke burst asks the host once', (tester) async {
      await pump(tester);

      for (final draft in <String>['@', '@s', '@sr', '@src/']) {
        await tester.enterText(find.byType(TextField), draft);
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(
        kFileReferenceDebounce + const Duration(milliseconds: 16),
      );
      await _settle(tester);

      expect(repository.fileReferenceCalls, <(String, String)>[
        ('session-1', 'src/'),
      ]);
    });

    testWidgets('a draft without a token asks nothing', (tester) async {
      await pump(tester);

      await type(tester, 'mail foo@bar');

      expect(repository.fileReferenceCalls, isEmpty);
      expect(find.text('src/'), findsNothing);
    });
  });
}
