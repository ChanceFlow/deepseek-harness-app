/// Message-feedback parity tests: the assistant reply footer's Like/Dislike
/// pair, the write and retract paths, the recorded rating's visible state,
/// and the reasons a write can fail without moving the row.
///
/// The strip runs over the production [MessageFeedbackController] and a real
/// `ChatScreen` tree, so what the assertions read is what a reader sees.
library;

import 'dart:async';

import 'package:domain/model/chat_message.dart';
import 'package:domain/model/message_feedback.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/di/providers.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/message_feedback_actions.dart';
import 'package:app/ui/theme/theme.dart';

import '../../l10n_app.dart';
import 'chat_controller_test.dart' show FakeChatRepository;

/// A repository double carrying the three feedback verbs; everything else
/// falls through to the shared fake.
class _FeedbackRepository extends FakeChatRepository {
  _FeedbackRepository({this.stored = const <MessageFeedbackItem>[]});

  /// The list read's answer.
  List<MessageFeedbackItem> stored;

  /// Holds the list read open so the pre-seed state is observable.
  Completer<void>? listGate;

  /// The list read's failure, when the load path is under test.
  Object? listFailure;

  /// The settled outcome of the next put/delete; null makes the write
  /// commit the requested judgment with a fresh version.
  MessageFeedbackWrite? putResult;
  MessageFeedbackWrite? deleteResult;

  /// A write that never reaches a host verdict (a transport failure).
  Object? putThrows;

  int listCalls = 0;
  final List<
    ({
      String sessionId,
      String messageId,
      MessageFeedbackRating rating,
      String? ifVersion,
    })
  >
  puts =
      <
        ({
          String sessionId,
          String messageId,
          MessageFeedbackRating rating,
          String? ifVersion,
        })
      >[];
  final List<({String sessionId, String messageId, String ifVersion})> deletes =
      <({String sessionId, String messageId, String ifVersion})>[];

  @override
  Future<List<MessageFeedbackItem>> listMessageFeedback(
    String sessionId,
  ) async {
    listCalls += 1;
    final Completer<void>? gate = listGate;
    if (gate != null) await gate.future;
    final Object? failure = listFailure;
    if (failure != null) throw failure;
    return stored;
  }

  @override
  Future<MessageFeedbackWrite> putMessageFeedback(
    String sessionId, {
    required String messageId,
    required MessageFeedbackRating rating,
    required String? ifVersion,
    String? note,
    MessageFeedbackCategory? category,
  }) async {
    puts.add((
      sessionId: sessionId,
      messageId: messageId,
      rating: rating,
      ifVersion: ifVersion,
    ));
    final Object? thrown = putThrows;
    if (thrown != null) throw thrown;
    final MessageFeedbackWrite? scripted = putResult;
    if (scripted != null) return scripted;
    return MessageFeedbackCommitted(
      MessageFeedbackItem(
        messageId: messageId,
        rating: rating,
        version: 'v-put-${puts.length}',
        createdAtEpochMs: 1,
        updatedAtEpochMs: 2,
      ),
    );
  }

  @override
  Future<MessageFeedbackWrite> deleteMessageFeedback(
    String sessionId, {
    required String messageId,
    required String ifVersion,
  }) async {
    deletes.add((
      sessionId: sessionId,
      messageId: messageId,
      ifVersion: ifVersion,
    ));
    final MessageFeedbackWrite? scripted = deleteResult;
    if (scripted != null) return scripted;
    return const MessageFeedbackCommitted(null);
  }
}

MessageFeedbackItem _item(
  MessageFeedbackRating rating, {
  String messageId = 'm1',
  String version = 'v-1',
  String? note,
  MessageFeedbackCategory? category,
}) => MessageFeedbackItem(
  messageId: messageId,
  rating: rating,
  version: version,
  createdAtEpochMs: 100,
  updatedAtEpochMs: 200,
  note: note,
  category: category,
);

ChatMessage _message() => const ChatMessage(
  id: 'm1',
  sessionId: 's1',
  role: MessageRole.assistant,
  text: 'copy me',
  createdAtEpochMs: 1723996800000,
  seq: 7,
);

Widget _harness(
  _FeedbackRepository repository, {
  ThemeData? theme,
  String? backendId = 'b1',
  void Function(ChatAction)? onAction,
}) {
  return ProviderScope(
    overrides: [chatRepositoryProvider('b1').overrideWithValue(repository)],
    child: l10nApp(
      theme: theme,
      home: ChatScreen(
        uiState: ChatUiState(
          sessions: const [
            SessionSummary(id: 's1', title: 'Alpha', blank: false),
          ],
          selectedSessionId: 's1',
          timeline: [TimelineMessage(_message())],
        ),
        backendId: backendId,
        onAction: onAction ?? (_) {},
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  _FeedbackRepository repository, {
  ThemeData? theme,
  String? backendId = 'b1',
  void Function(ChatAction)? onAction,
}) async {
  tester.view.physicalSize = const Size(800, 1280);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    _harness(
      repository,
      theme: theme,
      backendId: backendId,
      onAction: onAction,
    ),
  );
  // The seeding list read rides the provider's construction.
  await tester.pump();
  await tester.pump();
}

/// The IconButton seating one thumb glyph.
IconButton _thumbButton(WidgetTester tester, IconData glyph) =>
    tester.widget<IconButton>(
      find.ancestor(of: find.byIcon(glyph), matching: find.byType(IconButton)),
    );

void main() {
  testWidgets('the reply footer seats both thumbs and seeds the stored '
      'judgment', (tester) async {
    final repository = _FeedbackRepository(
      stored: [_item(MessageFeedbackRating.positive)],
    );
    await _pump(tester, repository);

    expect(repository.listCalls, 1);
    // The stored positive judgment reads filled with the retract wording.
    expect(find.byTooltip('Remove rating'), findsOneWidget);
    expect(find.byIcon(Icons.thumb_down_outlined), findsOneWidget);
    expect(find.byIcon(Icons.thumb_up), findsOneWidget);
  });

  testWidgets('a fresh tap records the judgment against the observed '
      'version', (tester) async {
    final repository = _FeedbackRepository();
    await _pump(tester, repository);

    await tester.tap(find.byTooltip('Good response'));
    await tester.pump();
    await tester.pump();

    expect(repository.puts, hasLength(1));
    expect(repository.puts.single.sessionId, 's1');
    expect(repository.puts.single.messageId, 'm1');
    expect(repository.puts.single.rating, MessageFeedbackRating.positive);
    expect(repository.puts.single.ifVersion, isNull);
    expect(repository.deletes, isEmpty);
    // The committed judgment is visible on the row.
    expect(find.byIcon(Icons.thumb_up), findsOneWidget);
    expect(find.byTooltip('Remove rating'), findsOneWidget);
  });

  testWidgets('the recorded judgment fills its glyph with the accent role in '
      'both themes', (tester) async {
    for (final ThemeData theme in [DshTheme.light(), DshTheme.dark()]) {
      final repository = _FeedbackRepository();
      await _pump(tester, repository, theme: theme);
      // The replaced MaterialApp lerps its theme; read the painted color only
      // after that animation settles.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('Good response'));
      await tester.pump();
      await tester.pump();

      final Icon icon = tester.widget<Icon>(find.byIcon(Icons.thumb_up));
      expect(icon.color, theme.colorScheme.primary);
      // The other thumb stays an outline in the inactive ink.
      final Icon idle = tester.widget<Icon>(
        find.byIcon(Icons.thumb_down_outlined),
      );
      expect(idle.color, theme.colorScheme.onSurfaceVariant);
    }
  });

  testWidgets('tapping the recorded judgment retracts it', (tester) async {
    final repository = _FeedbackRepository(
      stored: [_item(MessageFeedbackRating.positive, version: 'v-7')],
    );
    await _pump(tester, repository);

    await tester.tap(find.byTooltip('Remove rating'));
    await tester.pump();
    await tester.pump();

    expect(repository.deletes, hasLength(1));
    expect(repository.deletes.single.ifVersion, 'v-7');
    expect(repository.puts, isEmpty);
    // The row is unrated again.
    expect(find.byTooltip('Good response'), findsOneWidget);
    expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
  });

  testWidgets('the other thumb replaces the stored judgment', (tester) async {
    final repository = _FeedbackRepository(
      stored: [_item(MessageFeedbackRating.positive, version: 'v-7')],
    );
    await _pump(tester, repository);

    await tester.tap(find.byTooltip('Bad response'));
    await tester.pump();
    await tester.pump();

    expect(repository.puts, hasLength(1));
    expect(repository.puts.single.rating, MessageFeedbackRating.negative);
    expect(repository.puts.single.ifVersion, 'v-7');
    expect(repository.deletes, isEmpty);
    expect(find.byIcon(Icons.thumb_down), findsOneWidget);
  });

  testWidgets('a refused write states its reason and leaves the row '
      'unrated', (tester) async {
    final repository = _FeedbackRepository()
      ..putResult = const MessageFeedbackRefused('target-not-found');
    await _pump(tester, repository);

    await tester.tap(find.byTooltip('Good response'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Could not save feedback'), findsOneWidget);
    // The row did not move: the rating stays unrecorded.
    expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
    expect(find.byIcon(Icons.thumb_up), findsNothing);
    expect(find.byTooltip('Good response'), findsOneWidget);
  });

  testWidgets('a version conflict reconciles the row from the refusal and '
      'says so', (tester) async {
    final repository = _FeedbackRepository()
      ..putResult = MessageFeedbackRefused(
        kMessageFeedbackVersionConflict,
        current: _item(MessageFeedbackRating.negative, version: 'v-9'),
      );
    await _pump(tester, repository);

    await tester.tap(find.byTooltip('Good response'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('This feedback changed elsewhere; the latest state is shown'),
      findsOneWidget,
    );
    // The refusal's authoritative value is what the row now shows.
    expect(find.byIcon(Icons.thumb_down), findsOneWidget);
    expect(find.byTooltip('Remove rating'), findsOneWidget);
  });

  testWidgets('a write that never reached the host states a reason too', (
    tester,
  ) async {
    final repository = _FeedbackRepository()
      ..putThrows = Exception('connection aborted');
    await _pump(tester, repository);

    await tester.tap(find.byTooltip('Good response'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Could not save feedback'), findsOneWidget);
    expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
  });

  testWidgets('the thumbs stay inert until the seeding read settles', (
    tester,
  ) async {
    final repository = _FeedbackRepository(
      stored: [_item(MessageFeedbackRating.positive)],
    )..listGate = Completer<void>();
    await _pump(tester, repository);

    expect(_thumbButton(tester, Icons.thumb_up_outlined).onPressed, isNull);
    expect(_thumbButton(tester, Icons.thumb_down_outlined).onPressed, isNull);

    repository.listGate!.complete();
    repository.listGate = null;
    await tester.pump();
    await tester.pump();

    expect(_thumbButton(tester, Icons.thumb_up).onPressed, isNotNull);
    expect(
      _thumbButton(tester, Icons.thumb_down_outlined).onPressed,
      isNotNull,
    );
    // The seed landed: the stored judgment renders, and the untouched tap
    // now retracts rather than records.
    expect(find.byTooltip('Remove rating'), findsOneWidget);
  });

  testWidgets('a failed load is stated and still lets the pair record', (
    tester,
  ) async {
    final repository = _FeedbackRepository()
      ..listFailure = StateError('unreachable host');
    await _pump(tester, repository);

    expect(find.text('Could not load feedback'), findsOneWidget);
    expect(_thumbButton(tester, Icons.thumb_up_outlined).onPressed, isNotNull);

    await tester.tap(find.byTooltip('Good response'));
    await tester.pump();
    await tester.pump();

    expect(repository.puts.single.ifVersion, isNull);
    expect(find.byIcon(Icons.thumb_up), findsOneWidget);
  });

  testWidgets('a backend-less transcript offers no pair', (tester) async {
    final repository = _FeedbackRepository();
    await _pump(tester, repository, backendId: null);

    expect(find.byType(MessageFeedbackActions), findsNothing);
    expect(repository.listCalls, 0);
  });
}
