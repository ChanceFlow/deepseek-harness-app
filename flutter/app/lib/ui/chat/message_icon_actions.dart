/// Message icon actions — port of the web MessageIconActions chrome:
/// copy (with the post-copy check swap) and the HH:mm clock. Branch is
/// omitted: the wire fork has no per-message anchor yet (§8.1 deviation).
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/deepsuite_extension.dart';

class MessageIconActions extends StatefulWidget {
  const MessageIconActions({
    super.key,
    required this.text,
    required this.timeEpochMs,
    required this.clockAtStart,
  });

  final String text;
  final int timeEpochMs;

  /// Clock before the icons (user messages) or after them (assistant).
  final bool clockAtStart;

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
    final ds = dsOf(context);
    final l10n = AppLocalizations.of(context)!;
    final clock = Text(
      _clock,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: ds.labelTertiary),
    );
    final copy = IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 14,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      tooltip: _copied ? l10n.copiedTooltip : l10n.copyTooltip,
      onPressed: _copy,
      icon: Icon(
        _copied ? Icons.check_outlined : Icons.copy_outlined,
        color: ds.labelTertiary,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.clockAtStart) ...[clock, const SizedBox(width: 6)],
        copy,
        if (!widget.clockAtStart) ...[const SizedBox(width: 6), clock],
      ],
    );
  }
}
