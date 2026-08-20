/// Plan strip above the composer — port of the web `TodoPanel`
/// (`ui-conversation/src/client/skeleton/TodoPanel.tsx`): renders the
/// standing `todo/write` whole-list snapshot (cleared on the next
/// `turn/start`) with per-status counts in the header and the checklist
/// behind a whole-row disclosure.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/todo.dart';
import 'package:flutter/material.dart';

import '../theme/deepsuite_extension.dart';

/// Web `progressLabel`: "·"-joined per-status counts; zero-count segments
/// drop out as noise (a non-empty list keeps at least one).
String todoProgressLabel(List<TodoItem> todos, AppLocalizations l10n) {
  final done = todos
      .where((item) => item.status == TodoStatus.completed)
      .length;
  final active = todos
      .where((item) => item.status == TodoStatus.inProgress)
      .length;
  final pending = todos.length - done - active;
  return [
    if (done > 0) l10n.todoCountDone(done),
    if (active > 0) l10n.todoCountActive(active),
    if (pending > 0) l10n.todoCountPending(pending),
  ].join(' · ');
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
    final ds = dsOf(context);
    final (icon, color) = switch (status) {
      TodoStatus.completed => (Icons.check_circle, ds.accent),
      TodoStatus.inProgress => (
        Icons.radio_button_checked,
        Theme.of(context).colorScheme.onSurface,
      ),
      TodoStatus.pending => (Icons.radio_button_unchecked, ds.labelCaption),
    };
    return SizedBox(
      width: 16,
      height: 16,
      child: Center(child: Icon(icon, size: 14, color: color)),
    );
  }
}

class TodoPanel extends StatefulWidget {
  const TodoPanel({super.key, required this.todos});

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
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: ds.tip,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          border: Border(
            top: BorderSide(color: ds.divider),
            left: BorderSide(color: ds.divider),
            right: BorderSide(color: ds.divider),
          ),
        ),
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
                      Icon(Icons.checklist, size: 14, color: ds.labelSecondary),
                      const SizedBox(width: 6),
                      Text(l10n.todosLabel, style: theme.textTheme.bodySmall),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          todoProgressLabel(widget.todos, l10n),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ds.labelTertiary,
                          ),
                        ),
                      ),
                      Icon(
                        _collapsed
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 14,
                        color: ds.labelSecondary,
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
                                      ? ds.labelTertiary
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
