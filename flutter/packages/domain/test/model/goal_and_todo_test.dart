import 'package:test/test.dart';

import 'package:domain/model/goal.dart';
import 'package:domain/model/todo.dart';

void main() {
  group('Goal models', () {
    test('GoalRef equality and hashCode', () {
      const a = GoalRef(id: 'g-1', revision: 2);
      const b = GoalRef(id: 'g-1', revision: 2);
      const diff = GoalRef(id: 'g-1', revision: 3);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    const snapshot = GoalSnapshot(
      id: 'g-1',
      revision: 2,
      objective: 'Write tests',
      phase: GoalPhase.active,
      maxGoalRounds: 5,
      blockedReason: null,
    );

    test('GoalSnapshot equality and hashCode', () {
      const copy = GoalSnapshot(
        id: 'g-1',
        revision: 2,
        objective: 'Write tests',
        phase: GoalPhase.active,
        maxGoalRounds: 5,
        blockedReason: null,
      );
      const diff = GoalSnapshot(
        id: 'g-1',
        revision: 2,
        objective: 'Write tests',
        phase: GoalPhase.blocked,
        maxGoalRounds: 5,
        blockedReason: 'network down',
      );

      expect(snapshot, equals(copy));
      expect(snapshot.hashCode, equals(copy.hashCode));
      expect(snapshot, isNot(equals(diff)));
    });

    test('GoalProjection equality and hashCode', () {
      const a = GoalProjection(
        goal: snapshot,
        roundsStarted: 1,
        createdAt: 100,
        updatedAt: 200,
      );
      const b = GoalProjection(
        goal: snapshot,
        roundsStarted: 1,
        createdAt: 100,
        updatedAt: 200,
      );
      const diff = GoalProjection(
        goal: snapshot,
        roundsStarted: 2,
        createdAt: 100,
        updatedAt: 200,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });
  });

  group('Todo models', () {
    test('TodoItem equality and hashCode', () {
      const a = TodoItem(content: 'test', status: TodoStatus.pending);
      const b = TodoItem(content: 'test', status: TodoStatus.pending);
      const diff = TodoItem(content: 'test', status: TodoStatus.completed);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    test('todoStatusFromWire parses valid values and throws on unknown', () {
      expect(todoStatusFromWire('pending'), equals(TodoStatus.pending));
      expect(todoStatusFromWire('in_progress'), equals(TodoStatus.inProgress));
      expect(todoStatusFromWire('completed'), equals(TodoStatus.completed));

      expect(
        () => todoStatusFromWire('unknown_status'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
