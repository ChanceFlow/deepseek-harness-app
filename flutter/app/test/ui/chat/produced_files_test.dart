/// Produced-file derivation tests — the phone port of the reference
/// turn-deliverables fold.
///
/// The vocabulary is the durable tool-call family, so every case drives the
/// real `TimelineToolCall` values the adapter publishes rather than a
/// parallel fixture vocabulary.
library;

import 'dart:convert';

import 'package:app/ui/chat/produced_files.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter_test/flutter_test.dart';

int _nextId = 0;

TimelineToolCall _call(
  String name,
  Map<String, Object?> args, {
  ToolRunStatus status = ToolRunStatus.completed,
  bool isError = false,
  List<TimelineToolCall> children = const <TimelineToolCall>[],
  String? rawArguments,
}) {
  _nextId += 1;
  return TimelineToolCall(
    id: 'call-$_nextId',
    name: name,
    arguments: rawArguments ?? jsonEncode(args),
    status: status,
    isError: isError,
    children: children,
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
  group('producedMutationPath', () {
    test('a successful write contributes its path', () {
      expect(
        producedMutationPath(
          _call('write', <String, Object?>{
            'file_path': 'lib/a.dart',
            'content': 'void main() {}',
          }),
        ),
        'lib/a.dart',
      );
    });

    test('a write without string content contributes nothing', () {
      expect(
        producedMutationPath(
          _call('write', <String, Object?>{'file_path': 'lib/a.dart'}),
        ),
        isNull,
      );
    });

    test('a blank path contributes nothing', () {
      expect(
        producedMutationPath(
          _call('write', <String, Object?>{'file_path': '   ', 'content': 'x'}),
        ),
        isNull,
      );
    });

    test('a failed or running call contributes nothing', () {
      expect(
        producedMutationPath(
          _call(
            'write',
            <String, Object?>{'file_path': 'lib/a.dart', 'content': 'x'},
            status: ToolRunStatus.failed,
            isError: true,
          ),
        ),
        isNull,
      );
      expect(
        producedMutationPath(
          _call('write', <String, Object?>{
            'file_path': 'lib/a.dart',
            'content': 'x',
          }, status: ToolRunStatus.running),
        ),
        isNull,
      );
    });

    test('a read contributes nothing', () {
      expect(
        producedMutationPath(
          _call('read', <String, Object?>{'file_path': 'lib/a.dart'}),
        ),
        isNull,
      );
    });

    test('an edit requires a real replacement', () {
      expect(
        producedMutationPath(
          _call('edit', <String, Object?>{
            'file_path': 'lib/a.dart',
            'old_string': 'one',
            'new_string': 'two',
          }),
        ),
        'lib/a.dart',
      );
      // Same replacement text is a no-op, not a mutation.
      expect(
        producedMutationPath(
          _call('edit', <String, Object?>{
            'file_path': 'lib/a.dart',
            'old_string': 'one',
            'new_string': 'one',
          }),
        ),
        isNull,
      );
      // A missing old_string is not an executable edit.
      expect(
        producedMutationPath(
          _call('edit', <String, Object?>{
            'file_path': 'lib/a.dart',
            'new_string': 'two',
          }),
        ),
        isNull,
      );
      expect(
        producedMutationPath(
          _call('edit', <String, Object?>{
            'file_path': 'lib/a.dart',
            'old_string': 'one',
            'new_string': 'two',
            'replace_all': 'yes',
          }),
        ),
        isNull,
      );
    });

    test('str_replace_editor only counts complete mutating commands', () {
      expect(
        producedMutationPath(
          _call('str_replace_editor', <String, Object?>{
            'command': 'create',
            'path': 'lib/a.dart',
            'file_text': 'x',
          }),
        ),
        'lib/a.dart',
      );
      expect(
        producedMutationPath(
          _call('str_replace_editor', <String, Object?>{
            'command': 'str_replace',
            'path': 'lib/a.dart',
            'old_str': 'one',
            'new_str': 'two',
          }),
        ),
        'lib/a.dart',
      );
      expect(
        producedMutationPath(
          _call('str_replace_editor', <String, Object?>{
            'command': 'insert',
            'path': 'lib/a.dart',
            'insert_line': 0,
            'new_str': 'x',
          }),
        ),
        'lib/a.dart',
      );
      // A view command is not a mutation.
      expect(
        producedMutationPath(
          _call('str_replace_editor', <String, Object?>{
            'command': 'view',
            'path': 'lib/a.dart',
          }),
        ),
        isNull,
      );
      // A str_replace with an empty old_str is incomplete.
      expect(
        producedMutationPath(
          _call('str_replace_editor', <String, Object?>{
            'command': 'str_replace',
            'path': 'lib/a.dart',
            'old_str': '',
            'new_str': 'two',
          }),
        ),
        isNull,
      );
    });

    test('malformed arguments contribute nothing', () {
      expect(
        producedMutationPath(
          _call('write', const <String, Object?>{}, rawArguments: '{"file_'),
        ),
        isNull,
      );
    });

    test('the basename handles either separator', () {
      expect(producedFileBasename('/tmp/lib/a.dart'), 'a.dart');
      expect(producedFileBasename(r'C:\work\a.dart'), 'a.dart');
      expect(producedFileBasename('a.dart'), 'a.dart');
    });
  });

  group('producedFilesByClosingMessage', () {
    test('paths come from successful mutations in first-seen order', () {
      final items = <TimelineItem>[
        const TimelineTurnBoundary(1),
        _call('write', <String, Object?>{
          'file_path': 'a.dart',
          'content': 'x',
        }),
        _call('read', <String, Object?>{'file_path': 'b.dart'}),
        _call('write', <String, Object?>{
          'file_path': 'b.dart',
          'content': 'x',
        }),
        _call('edit', <String, Object?>{
          'file_path': 'a.dart',
          'old_string': 'x',
          'new_string': 'y',
        }),
        _assistant('m1'),
      ];
      expect(producedFilesByClosingMessage(items, latestTurnClosed: true), {
        'm1': <String>['a.dart', 'b.dart'],
      });
    });

    test('failed calls and unsupported tools contribute nothing', () {
      final items = <TimelineItem>[
        const TimelineTurnBoundary(1),
        _call(
          'write',
          <String, Object?>{'file_path': 'a.dart', 'content': 'x'},
          status: ToolRunStatus.failed,
          isError: true,
        ),
        _call('grep', <String, Object?>{'pattern': 'a'}),
        _assistant('m1'),
      ];
      expect(
        producedFilesByClosingMessage(items, latestTurnClosed: true),
        isEmpty,
      );
    });

    test('nested dispatch children are not counted independently', () {
      final nested = _call('write', <String, Object?>{
        'file_path': 'nested.dart',
        'content': 'x',
      });
      final parent = _call(
        'run_code',
        <String, Object?>{'code': 'x'},
        children: <TimelineToolCall>[nested],
      );
      final items = <TimelineItem>[
        const TimelineTurnBoundary(1),
        parent,
        _assistant('m1'),
      ];
      expect(
        producedFilesByClosingMessage(items, latestTurnClosed: true),
        isEmpty,
      );
    });

    test('calls after the closing reply are excluded from its row', () {
      final items = <TimelineItem>[
        const TimelineTurnBoundary(1),
        _call('write', <String, Object?>{
          'file_path': 'a.dart',
          'content': 'x',
        }),
        _assistant('m1'),
        _call('write', <String, Object?>{
          'file_path': 'late.dart',
          'content': 'x',
        }),
      ];
      expect(producedFilesByClosingMessage(items, latestTurnClosed: true), {
        'm1': <String>['a.dart'],
      });
    });

    test(
      'an open newest turn keeps no row while earlier turns keep theirs',
      () {
        final items = <TimelineItem>[
          const TimelineTurnBoundary(1),
          _call('write', <String, Object?>{
            'file_path': 'a.dart',
            'content': 'x',
          }),
          _assistant('m1'),
          const TimelineTurnBoundary(2),
          _call('write', <String, Object?>{
            'file_path': 'b.dart',
            'content': 'x',
          }),
          _assistant('m2'),
        ];
        expect(producedFilesByClosingMessage(items, latestTurnClosed: false), {
          'm1': <String>['a.dart'],
        });
        expect(producedFilesByClosingMessage(items, latestTurnClosed: true), {
          'm1': <String>['a.dart'],
          'm2': <String>['b.dart'],
        });
      },
    );

    test('a turn with no closing text assistant attaches no row', () {
      final items = <TimelineItem>[
        const TimelineTurnBoundary(1),
        _call('write', <String, Object?>{
          'file_path': 'a.dart',
          'content': 'x',
        }),
      ];
      expect(
        producedFilesByClosingMessage(items, latestTurnClosed: true),
        isEmpty,
      );
    });
  });
}
