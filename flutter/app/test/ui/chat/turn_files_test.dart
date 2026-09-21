/// Turn-tail file facts tests — the phone port of the reference deliverables
/// fold's two readers.
///
/// Every case drives real `TimelineToolCall` values, the shape the adapter
/// publishes, rather than a parallel fixture vocabulary.
library;

import 'dart:convert';

import 'package:app/ui/chat/turn_files.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter_test/flutter_test.dart';

int _nextId = 0;

TimelineToolCall _call(
  String name,
  Map<String, Object?> args, {
  List<PresentedFile> presentedFiles = const <PresentedFile>[],
}) {
  _nextId += 1;
  return TimelineToolCall(
    id: 'call-$_nextId',
    name: name,
    arguments: jsonEncode(args),
    status: ToolRunStatus.completed,
    presentedFiles: presentedFiles,
  );
}

TimelineMessage _assistant(String id, {String text = 'done'}) =>
    TimelineMessage(
      ChatMessage(
        id: id,
        sessionId: 's1',
        role: MessageRole.assistant,
        text: text,
      ),
    );

void main() {
  group('turnFilesByClosingMessage — presented files', () {
    test('declarations ride the closing assistant message in path order', () {
      final items = <TimelineItem>[
        const TimelineTurnBoundary(1),
        _call(
          'present',
          <String, Object?>{
            'files': <Object?>[
              <String, Object?>{'path': 'out/a.png'},
            ],
          },
          presentedFiles: const <PresentedFile>[
            PresentedFile(path: 'out/a.png', description: 'Hero'),
          ],
        ),
        _assistant('m1'),
      ];
      final files = turnFilesByClosingMessage(
        items,
        latestTurnClosed: true,
      )['m1']!;
      expect(files.produced, isEmpty);
      expect(files.presented, const <PresentedFile>[
        PresentedFile(path: 'out/a.png', description: 'Hero'),
      ]);
    });

    test(
      'a path declared twice keeps its last declaration, first-seen order',
      () {
        final items = <TimelineItem>[
          const TimelineTurnBoundary(1),
          _call(
            'present',
            <String, Object?>{},
            presentedFiles: const <PresentedFile>[
              PresentedFile(path: 'out/a.png', description: 'first'),
              PresentedFile(path: 'out/b.png'),
            ],
          ),
          _call(
            'present',
            <String, Object?>{},
            presentedFiles: const <PresentedFile>[
              PresentedFile(path: 'out/a.png', description: 'second'),
            ],
          ),
          _assistant('m1'),
        ];
        final files = turnFilesByClosingMessage(
          items,
          latestTurnClosed: true,
        )['m1']!;
        expect(files.presented, const <PresentedFile>[
          PresentedFile(path: 'out/a.png', description: 'second'),
          PresentedFile(path: 'out/b.png'),
        ]);
      },
    );

    test('a declaration after the closing reply belongs to no row', () {
      final items = <TimelineItem>[
        const TimelineTurnBoundary(1),
        _assistant('m1'),
        _call(
          'present',
          <String, Object?>{},
          presentedFiles: const <PresentedFile>[
            PresentedFile(path: 'out/late.png'),
          ],
        ),
      ];
      expect(turnFilesByClosingMessage(items, latestTurnClosed: true), isEmpty);
    });

    test('the newest turn keeps no rows until it closes', () {
      final items = <TimelineItem>[
        const TimelineTurnBoundary(1),
        _call(
          'present',
          <String, Object?>{},
          presentedFiles: const <PresentedFile>[
            PresentedFile(path: 'out/a.png'),
          ],
        ),
        _assistant('m1'),
      ];
      expect(
        turnFilesByClosingMessage(items, latestTurnClosed: false),
        isEmpty,
      );
    });
  });

  group('turnFilesByClosingMessage — both facts', () {
    test('a turn that wrote and declared carries both under one message', () {
      final items = <TimelineItem>[
        const TimelineTurnBoundary(1),
        _call('write', <String, Object?>{
          'file_path': 'lib/a.dart',
          'content': 'x',
        }),
        _call(
          'present',
          <String, Object?>{},
          presentedFiles: const <PresentedFile>[
            PresentedFile(path: 'lib/a.dart'),
          ],
        ),
        _assistant('m1'),
      ];
      final files = turnFilesByClosingMessage(
        items,
        latestTurnClosed: true,
      )['m1']!;
      expect(files.produced, <String>['lib/a.dart']);
      expect(files.presented.single.path, 'lib/a.dart');
    });

    test('each turn keeps its own facts', () {
      final items = <TimelineItem>[
        const TimelineTurnBoundary(1),
        _call('write', <String, Object?>{
          'file_path': 'one.dart',
          'content': 'x',
        }),
        _assistant('m1'),
        const TimelineTurnBoundary(2),
        _call(
          'present',
          <String, Object?>{},
          presentedFiles: const <PresentedFile>[PresentedFile(path: 'two.png')],
        ),
        _assistant('m2'),
      ];
      final byMessage = turnFilesByClosingMessage(
        items,
        latestTurnClosed: true,
      );
      expect(byMessage['m1']!.produced, <String>['one.dart']);
      expect(byMessage['m1']!.presented, isEmpty);
      expect(byMessage['m2']!.produced, isEmpty);
      expect(byMessage['m2']!.presented.single.path, 'two.png');
    });
  });
}
