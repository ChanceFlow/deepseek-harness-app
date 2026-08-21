/// Message icon actions — the reply's footer: copy (with the post-copy
/// check swap), fork, and the HH:mm clock. Fork cuts a new session at
/// this message's log position (`session.fork` `atSeq`), which the host
/// resolves to the end of the turn containing it.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MessageIconActions extends StatefulWidget {
  const MessageIconActions({
    super.key,
    required this.text,
    required this.timeEpochMs,
    required this.clockAtStart,
    this.onFork,
  });

  final String text;
  final int timeEpochMs;

  /// Clock before the icons (user messages) or after them (assistant).
  final bool clockAtStart;

  /// Cuts a new session at this message; null hides the seat, which is
  /// what a message with no logged position gets.
  final VoidCallback? onFork;

  @override
  State<MessageIconActions> createState() => _MessageIconActionsState();
}

class _MessageIconActionsState extends State<MessageIconActions> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  String get _clock {
    final local = DateTime.fromMillisecondsSinceEpoch(widget.timeEpochMs);
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final clock = Text(
      _clock,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: scheme.onSurfaceVariant),
    );
    // The glyph keeps a 32px seat: small enough that the footer reads as
    // a caption on the message rather than a control bar, large enough to
    // hit. The row hugs the text it belongs to — a 16px gap above would
    // orphan it between two messages.
    final copy = IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      tooltip: _copied ? l10n.copiedTooltip : l10n.copyTooltip,
      onPressed: _copy,
      icon: Icon(
        _copied ? Icons.check_outlined : Icons.copy_outlined,
        color: scheme.onSurfaceVariant,
      ),
    );
    final fork = widget.onFork == null
        ? null
        : IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            tooltip: l10n.forkFromHere,
            onPressed: widget.onFork,
            icon: Icon(Icons.alt_route, color: scheme.onSurfaceVariant),
          );
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.clockAtStart) ...[clock, const SizedBox(width: 4)],
          copy,
          if (fork != null) fork,
          if (!widget.clockAtStart) ...[const SizedBox(width: 4), clock],
        ],
      ),
    );
  }
}
