import 'package:test/test.dart';

import 'package:domain/model/workspace.dart';

void main() {
  group('Workspace models', () {
    test('WorkspaceSummary equality and sessionIds collection comparison', () {
      const a = WorkspaceSummary(
        workspaceId: 'ws-1',
        path: '/work/app',
        title: 'Main App',
        sessionIds: ['s1', 's2'],
        createdAt: '2026-01-01',
        updatedAt: '2026-01-02',
      );
      const b = WorkspaceSummary(
        workspaceId: 'ws-1',
        path: '/work/app',
        title: 'Main App',
        sessionIds: ['s1', 's2'],
        createdAt: '2026-01-01',
        updatedAt: '2026-01-02',
      );
      const diffSessions = WorkspaceSummary(
        workspaceId: 'ws-1',
        path: '/work/app',
        title: 'Main App',
        sessionIds: ['s1'],
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diffSessions)));
    });

    test('SessionSearchResult equality and hashCode', () {
      const a = SessionSearchResult(sessionId: 's-1', snippet: 'matched line');
      const b = SessionSearchResult(sessionId: 's-1', snippet: 'matched line');
      const diff = SessionSearchResult(sessionId: 's-1', snippet: 'other line');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });
  });
}
