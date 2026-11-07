/// Turn-outcome probe tests: one timeline read through a fake
/// [ChatRepository] yields the outcome and reply preview the notification path
/// announces. The fake exposes only `observeTimeline`; every other repository
/// member falls through to `noSuchMethod`, so a probe that reached one fails
/// loudly instead of silently opening a socket.
library;

import 'dart:async';

import 'package:app/notifications/turn_outcome_probe.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Timeline-only [ChatRepository] double.
class TimelineRepositoryFake implements ChatRepository {
  TimelineRepositoryFake(this._timeline);

  final Stream<List<TimelineItem>> _timeline;

  @override
  Stream<List<TimelineItem>> observeTimeline(String sessionId) => _timeline;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TimelineTurnBoundary _turn(String? endReason) =>
    TimelineTurnBoundary(1, endReason: endReason);

TimelineMessage _assistant(String text) => TimelineMessage(
  ChatMessage(
    id: 'm',
    sessionId: 's1',
    role: MessageRole.assistant,
    text: text,
  ),
);

TimelineMessage _user(String text) => TimelineMessage(
  ChatMessage(id: 'u', sessionId: 's1', role: MessageRole.user, text: text),
);

Future<TurnOutcomeFacts?> _probe(List<TimelineItem> items) =>
    RepositoryTurnOutcomeProbe(
      TimelineRepositoryFake(Stream<List<TimelineItem>>.value(items)),
    ).probe('s1');

void main() {
  group('outcome', () {
    test('a completed turn reports completed with the reply preview', () async {
      final facts = await _probe([
        _turn('completed'),
        _assistant('  Fixed the retry loop.  \nThen the tests.'),
      ]);
      expect(
        facts,
        const TurnOutcomeFacts(
          outcome: TurnOutcome.completed,
          replyPreview: 'Fixed the retry loop.',
        ),
      );
    });

    test('an error turn reports failed', () async {
      final facts = await _probe([_turn('error'), _assistant('Partial.')]);
      expect(facts?.outcome, TurnOutcome.failed);
      expect(facts?.replyPreview, 'Partial.');
    });

    test('a max-tokens turn reports failed, not completed', () async {
      final facts = await _probe([_turn('max-tokens')]);
      expect(facts?.outcome, TurnOutcome.failed);
    });

    test('every non-completion terminal kind reports failed', () async {
      for (final kind in [
        'error',
        'max-tokens',
        'interrupted',
        'blocked',
        'forked',
      ]) {
        final facts = await _probe([_turn(kind)]);
        expect(
          facts?.outcome,
          TurnOutcome.failed,
          reason: 'turn/end kind "$kind" must not read as a new reply',
        );
      }
    });

    test('an aborted turn reports stopped', () async {
      final facts = await _probe([_turn('aborted')]);
      expect(facts?.outcome, TurnOutcome.stopped);
    });

    test('the last closed turn decides the outcome', () async {
      expect(
        (await _probe([_turn('error'), _turn('completed')]))?.outcome,
        TurnOutcome.completed,
      );
      expect(
        (await _probe([_turn('completed'), _turn('aborted')]))?.outcome,
        TurnOutcome.stopped,
      );
    });

    test('an open last turn leaves the completion fallback', () async {
      final facts = await _probe([_assistant('Streaming…')]);
      expect(facts?.outcome, TurnOutcome.completed);
    });

    test('a timeline with no turn fact still reports completed', () async {
      final facts = await _probe([_user('Hello?')]);
      expect(facts?.outcome, TurnOutcome.completed);
      expect(facts?.replyPreview, isNull);
    });
  });

  group('reply preview', () {
    test('takes the first line, trimmed', () async {
      final facts = await _probe([
        _turn('completed'),
        _assistant('\n\n   First line.   \nSecond line.'),
      ]);
      expect(facts?.replyPreview, 'First line.');
    });

    test('clips a long line to 80 characters with an ellipsis', () async {
      final facts = await _probe([_turn('completed'), _assistant('a' * 100)]);
      expect(facts?.replyPreview, '${'a' * 79}…');
      expect(facts?.replyPreview, hasLength(80));
    });

    test('strips a trivial enclosing code fence', () async {
      final facts = await _probe([
        _turn('completed'),
        _assistant('```dart\nfinal answer = 42;\n```'),
      ]);
      expect(facts?.replyPreview, 'final answer = 42;');
    });

    test('uses the newest text-bearing assistant message', () async {
      final facts = await _probe([
        _turn('completed'),
        _assistant('Let me check the file.'),
        _assistant('Done.'),
        _assistant('   '),
      ]);
      expect(facts?.replyPreview, 'Done.');
    });

    test('a failed last turn does not borrow the previous reply', () async {
      final facts = await _probe([
        _turn('completed'),
        _assistant('Previous reply.'),
        _turn('error'),
      ]);
      expect(facts?.outcome, TurnOutcome.failed);
      expect(facts?.replyPreview, isNull);
    });

    test('blank assistant text yields no preview', () async {
      expect(
        (await _probe([_turn('completed'), _assistant(' \n\t ')]))
            ?.replyPreview,
        isNull,
      );
    });

    test('no assistant message yields no preview', () async {
      expect(
        (await _probe([_turn('completed'), _user('Do the thing.')]))
            ?.replyPreview,
        isNull,
      );
    });
  });

  group('read lifecycle', () {
    test('an empty timeline yields null', () async {
      expect(await _probe(const <TimelineItem>[]), isNull);
    });

    test('a stream that closes without a snapshot yields null', () async {
      final probe = RepositoryTurnOutcomeProbe(
        TimelineRepositoryFake(const Stream<List<TimelineItem>>.empty()),
      );
      expect(await probe.probe('s1'), isNull);
    });

    test('a stream error yields null instead of throwing', () async {
      final probe = RepositoryTurnOutcomeProbe(
        TimelineRepositoryFake(
          Stream<List<TimelineItem>>.error(StateError('socket down')),
        ),
      );
      expect(await probe.probe('s1'), isNull);
    });

    test('a silent timeline yields null after the timeout', () async {
      final controller = StreamController<List<TimelineItem>>();
      addTearDown(controller.close);
      final probe = RepositoryTurnOutcomeProbe(
        TimelineRepositoryFake(controller.stream),
        timeout: const Duration(milliseconds: 20),
      );
      expect(await probe.probe('s1'), isNull);
    });

    test(
      'cancels the timeline subscription after the first snapshot',
      () async {
        final controller = StreamController<List<TimelineItem>>();
        controller.add([_turn('completed'), _assistant('Done.')]);
        addTearDown(controller.close);
        final probe = RepositoryTurnOutcomeProbe(
          TimelineRepositoryFake(controller.stream),
        );
        final facts = await probe.probe('s1');
        expect(facts?.outcome, TurnOutcome.completed);
        expect(controller.hasListener, isFalse);
      },
    );
  });

  test(
    'the provider defaults to no probe so headless reads open no socket',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(turnOutcomeProbeProvider('b1')), isNull);
    },
  );
}
