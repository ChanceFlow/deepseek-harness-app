/// Standing todo list — the `todos` projection vocabulary
/// (`TodoItem[] | null`): the latest whole `todo/write` list, cleared by
/// the next `turn/start` (a finished checklist stays visible through
/// `turn/end`).
library;

/// One todo entry's status (wire: `pending` / `in_progress` /
/// `completed`).
enum TodoStatus { pending, inProgress, completed }

TodoStatus todoStatusFromWire(String wire) => switch (wire) {
  'pending' => TodoStatus.pending,
  'in_progress' => TodoStatus.inProgress,
  'completed' => TodoStatus.completed,
  _ => throw FormatException('unknown todo status: $wire'),
};

final class TodoItem {
  const TodoItem({required this.content, required this.status});

  final String content;
  final TodoStatus status;

  @override
  bool operator ==(Object other) =>
      other is TodoItem && other.content == content && other.status == status;

  @override
  int get hashCode => Object.hash(content, status);
}
