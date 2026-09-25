import 'package:test/test.dart';

import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/subagent.dart';

void main() {
  group('AgentPreset models', () {
    const entry1 = AgentPresetEntry(
      id: 'p-sys',
      isDefault: true,
      name: 'System Default',
      description: 'Default preset',
      broken: null,
    );

    test('displayName uses name when available or falls back to id', () {
      expect(entry1.displayName, 'System Default');

      const noName = AgentPresetEntry(id: 'p-fallback');
      expect(noName.displayName, 'p-fallback');
    });

    test('AgentPresetEntry equality and hashCode', () {
      const copy = AgentPresetEntry(
        id: 'p-sys',
        isDefault: true,
        name: 'System Default',
        description: 'Default preset',
        broken: null,
      );
      const diff = AgentPresetEntry(
        id: 'p-sys',
        isDefault: false,
        name: 'System Default',
      );

      expect(entry1, equals(copy));
      expect(entry1.hashCode, equals(copy.hashCode));
      expect(entry1, isNot(equals(diff)));
    });

    test('AgentPresetRoster equality and defaultEntry resolution', () {
      const rosterA = AgentPresetRoster(entries: [entry1]);
      const rosterB = AgentPresetRoster(
        entries: [
          AgentPresetEntry(
            id: 'p-sys',
            isDefault: true,
            name: 'System Default',
            description: 'Default preset',
            broken: null,
          ),
        ],
      );
      const diff = AgentPresetRoster(entries: []);

      expect(rosterA, equals(rosterB));
      expect(rosterA.hashCode, equals(rosterB.hashCode));
      expect(rosterA.defaultEntry, equals(entry1));
      expect(diff.defaultEntry, isNull);
      expect(rosterA, isNot(equals(diff)));
    });
  });

  group('Subagent models', () {
    const subEntry = SubagentEntry(
      id: 'sub-1',
      mode: SubagentMode.continuable,
      activity: 'running',
      hasChildren: true,
      label: 'Research agent',
    );

    test('isInterruptible returns true only for running continuable child', () {
      expect(subEntry.isInterruptible, isTrue);

      const oneShot = SubagentEntry(
        id: 'sub-3',
        mode: SubagentMode.oneShot,
        activity: 'running',
      );
      expect(oneShot.isInterruptible, isFalse);

      const unknown = SubagentEntry(
        id: 'sub-5',
        mode: SubagentMode.unknown,
        activity: 'running',
      );
      expect(unknown.isInterruptible, isFalse);

      const notRunning = SubagentEntry(
        id: 'sub-4',
        mode: SubagentMode.continuable,
        activity: 'idle',
      );
      expect(notRunning.isInterruptible, isFalse);
    });

    test('SubagentEntry equality and hashCode', () {
      const copy = SubagentEntry(
        id: 'sub-1',
        mode: SubagentMode.continuable,
        activity: 'running',
        hasChildren: true,
        label: 'Research agent',
      );
      const diff = SubagentEntry(
        id: 'sub-1',
        mode: SubagentMode.continuable,
        activity: 'running',
        hasChildren: false,
      );

      expect(subEntry, equals(copy));
      expect(subEntry.hashCode, equals(copy.hashCode));
      expect(subEntry, isNot(equals(diff)));
    });

    test('SubagentCatalog equality with entries collection', () {
      const a = SubagentCatalog(parentSessionId: 'sess-p', entries: [subEntry]);
      const b = SubagentCatalog(
        parentSessionId: 'sess-p',
        entries: [
          SubagentEntry(
            id: 'sub-1',
            mode: SubagentMode.continuable,
            activity: 'running',
            hasChildren: true,
            label: 'Research agent',
          ),
        ],
      );
      const diff = SubagentCatalog(parentSessionId: 'sess-other');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });
  });
}
