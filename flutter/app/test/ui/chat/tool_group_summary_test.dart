import 'dart:ui';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/chat/tool_group_summary.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10nEn = lookupAppLocalizations(const Locale('en'));
  final l10nZh = lookupAppLocalizations(const Locale('zh'));

  group('ToolGroupSummary', () {
    test('summarizes explored files and searches in English and Chinese', () {
      final calls = [
        const TimelineToolCall(
          id: '1',
          name: 'read',
          arguments: '{"file_path":"AGENTS.md"}',
          status: ToolRunStatus.completed,
        ),
        const TimelineToolCall(
          id: '2',
          name: 'read',
          arguments: '{"file_path":"README.md"}',
          status: ToolRunStatus.completed,
        ),
        const TimelineToolCall(
          id: '3',
          name: 'read',
          arguments: '{"file_path":"pubspec.yaml"}',
          status: ToolRunStatus.completed,
        ),
        const TimelineToolCall(
          id: '4',
          name: 'grep',
          arguments: '{"pattern":"TimelineToolCall"}',
          status: ToolRunStatus.completed,
        ),
        const TimelineToolCall(
          id: '5',
          name: 'glob',
          arguments: '{"pattern":"*.dart"}',
          status: ToolRunStatus.completed,
        ),
      ];

      final en = deriveToolGroupSummary(calls, l10nEn);
      expect(en.filesExplored, 3);
      expect(en.searches, 2);
      expect(en.title, 'Explored 3 files, 2 searches');
      expect(en.semanticTitle, 'Explored 3 files, 2 searches');
      expect(en.toolBreakdown, 'glob 1 · grep 1 · read 3');
      expect(en.isRunning, isFalse);

      final zh = deriveToolGroupSummary(calls, l10nZh);
      expect(zh.title, '浏览了 3 个文件，2 次搜索');
    });

    test('summarizes files only and singular forms', () {
      final singleCall = [
        const TimelineToolCall(
          id: '1',
          name: 'read',
          arguments: '{"file_path":"AGENTS.md"}',
          status: ToolRunStatus.completed,
        ),
      ];

      final enSingle = deriveToolGroupSummary(singleCall, l10nEn);
      expect(enSingle.title, 'Explored 1 file');

      final zhSingle = deriveToolGroupSummary(singleCall, l10nZh);
      expect(zhSingle.title, '浏览了 1 个文件');

      final multipleCalls = [
        const TimelineToolCall(
          id: '1',
          name: 'read',
          status: ToolRunStatus.completed,
        ),
        const TimelineToolCall(
          id: '2',
          name: 'read',
          status: ToolRunStatus.completed,
        ),
      ];

      final enMulti = deriveToolGroupSummary(multipleCalls, l10nEn);
      expect(enMulti.title, 'Explored 2 files');
    });

    test('summarizes searches only', () {
      final calls = [
        const TimelineToolCall(
          id: '1',
          name: 'web_search',
          arguments: '{"query":"flutter"}',
          status: ToolRunStatus.completed,
        ),
      ];

      final en = deriveToolGroupSummary(calls, l10nEn);
      expect(en.title, '1 search');

      final zh = deriveToolGroupSummary(calls, l10nZh);
      expect(zh.title, '1 次搜索');
    });

    test('summarizes file modifications and commands', () {
      final calls = [
        const TimelineToolCall(
          id: '1',
          name: 'write',
          arguments: '{"file_path":"foo.dart"}',
          status: ToolRunStatus.completed,
        ),
        const TimelineToolCall(
          id: '2',
          name: 'edit',
          arguments: '{"file_path":"bar.dart"}',
          status: ToolRunStatus.completed,
        ),
      ];

      final en = deriveToolGroupSummary(calls, l10nEn);
      expect(en.title, 'Modified 2 files');

      final bashCalls = [
        const TimelineToolCall(
          id: '1',
          name: 'bash',
          arguments: '{"command":"cargo test"}',
          status: ToolRunStatus.completed,
        ),
      ];

      final enBash = deriveToolGroupSummary(bashCalls, l10nEn);
      expect(enBash.title, 'Ran 1 command');

      final zhBash = deriveToolGroupSummary(bashCalls, l10nZh);
      expect(zhBash.title, '运行了 1 条命令');
    });

    test('handles running/in-flight states and active actions', () {
      final calls = [
        const TimelineToolCall(
          id: '1',
          name: 'read',
          arguments: '{"file_path":"AGENTS.md"}',
          status: ToolRunStatus.completed,
        ),
        const TimelineToolCall(
          id: '2',
          name: 'bash',
          arguments: '{"command":"flutter test"}',
          status: ToolRunStatus.running,
        ),
      ];

      final en = deriveToolGroupSummary(calls, l10nEn);
      expect(en.isRunning, isTrue);
      expect(en.title, 'Working (2 steps)');
      expect(en.subtitle, contains('Running bash: flutter test'));
      expect(en.activeAction, contains('Running bash: flutter test'));

      final zh = deriveToolGroupSummary(calls, l10nZh);
      expect(zh.title, '执行中 (2 步)');
      expect(zh.subtitle, contains('正在运行 bash: flutter test'));
    });
  });
}
