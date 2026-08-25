/// Plan strip above the composer — port of the web `TodoPanel`
/// (`ui-conversation/src/client/skeleton/TodoPanel.tsx`): renders the
/// standing `todo/write` whole-list snapshot (cleared on the next
/// `turn/start`) with per-status counts in the header and the checklist
/// behind a whole-row disclosure.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/todo.dart';
import 'package:flutter/material.dart';

/// The collapsed strip's line: the plan-summary rule the `todo_write` tool
/// row already speaks (`plan-summary.ts`) — "done/total completed" plus the
/// running item. Mid-run the open question is which item is being worked,
/// and per-status counts answer a question nobody asked.
String todoPlanLabel(List<TodoItem> todos, AppLocalizations l10n) {
  final done = todos
      .where((item) => item.status == TodoStatus.completed)
      .length;
  final head = l10n.toolTodoPlanCompleted(done, todos.length);
  final active = todos
      .where((item) => item.status == TodoStatus.inProgress)
      .map((item) => item.content.trim())
      .where((content) => content.isNotEmpty);
  return active.isEmpty ? head : '$head · ${active.first}';
}

/// One status glyph: a standard Material icon on the figma 14×14
/// artboard — filled check circle for completed, a business-blue ring
/// for in-progress, an open ring for pending (the web's hand-drawn
/// ring family replaced by native glyphs).
class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph({required this.status});

  final TodoStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (status) {
      TodoStatus.completed => (Icons.check_circle, scheme.primary),
      TodoStatus.inProgress => (
        Icons.radio_button_checked,
        Theme.of(context).colorScheme.onSurface,
      ),
      TodoStatus.pending => (Icons.radio_button_unchecked, scheme.outline),
    };
    return SizedBox(
      width: 16,
      height: 16,
      child: Center(child: Icon(icon, size: 14, color: color)),
    );
  }
}

class TodoPanel extends StatefulWidget {
  const TodoPanel({required this.todos, super.key});

  /// The session's standing plan; an empty list renders nothing (web
  /// rule — no data of its own, hidden while empty).
  final List<TodoItem> todos;

  @override
  State<TodoPanel> createState() => _TodoPanelState();
}

class _TodoPanelState extends State<TodoPanel> {
  bool _collapsed = true;

  @override
  Widget build(BuildContext context) {
    if (widget.todos.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    // A strip of the dock, not a card: the surface and the outer radius
    // belong to the dock, and a hairline is all that separates the plan
    // from the composer under it.
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => setState(() => _collapsed = !_collapsed),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.checklist,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(l10n.todosLabel, style: theme.textTheme.bodySmall),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          todoPlanLabel(widget.todos, l10n),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Icon(
                        _collapsed
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!_collapsed)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final item in widget.todos)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(width: 2),
                            _StatusGlyph(status: item.status),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item.content,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: item.status == TodoStatus.completed
                                      ? scheme.onSurfaceVariant
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
