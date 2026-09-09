import 'package:test/test.dart';

// Import ONLY the domain barrel file.
import 'package:domain/domain.dart';

void main() {
  test('domain.dart barrel exports all primary models', () {
    // 1. context_pressure.dart
    const pressure = ContextPressure(pressureTokens: 10);
    expect(pressure.pressureTokens, 10);
    const breakdown = ContextBreakdown(systemTokens: 5);
    expect(breakdown.systemTokens, 5);

    // 2. session_window_stats.dart
    const stats = SessionWindowStats(turns: 2);
    expect(stats.turns, 2);

    // 3. agent_preset.dart
    const preset = AgentPresetEntry(id: 'p1', trust: AgentPresetTrust.system);
    expect(preset.id, 'p1');
    const roster = AgentPresetRoster(entries: [preset]);
    expect(roster.entries, hasLength(1));

    // 4. permission_select.dart
    const permOption = PermissionPresetOption(value: 'full', name: 'Full');
    const permSelect = PermissionSelect(
      options: [permOption],
      currentValue: 'full',
    );
    expect(permSelect.currentOption?.value, 'full');

    // 5. timeline_window.dart
    const window = TimelineWindow(hasMoreOlder: true);
    expect(window.hasMoreOlder, isTrue);

    // 6. QuestionEvidence in chat_repository.dart
    const evidence = QuestionEvidence(sessionId: 's1', answers: []);
    expect(evidence.sessionId, 's1');
  });
}
