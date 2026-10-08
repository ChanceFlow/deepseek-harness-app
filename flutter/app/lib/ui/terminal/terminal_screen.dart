/// Agent terminal page: the session's persistent shells, one attached screen
/// at a time, with the control the host allows.
///
/// Rendering is a bounded plain-text screen: the host publishes an ANSI screen
/// plus ordered output, this client consumes the escape sequences that change
/// which text exists, and states that colors and cursor addressing are not
/// rendered ([TerminalScreenBuffer] carries why there is no full emulator).
/// Everything the wire cannot describe stays out: no ZMODEM, no multi-pane
/// window holds (the stream hold is used only to keep a tab alive), and a
/// reconnect replays a fresh snapshot rather than resuming a byte offset.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/terminal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/state_dot.dart';
import '../theme/theme.dart';
import 'terminal_controller.dart';
import 'terminal_screen_buffer.dart';

/// The pushed terminal surface for one conversation.
class TerminalRoute extends ConsumerWidget {
  const TerminalRoute({
    required this.backendId,
    required this.sessionId,
    super.key,
  });

  final String backendId;
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(
      terminalControllerProvider((backendId, sessionId)),
    );
    return StreamBuilder<TerminalUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder: (context, snapshot) {
        final state = snapshot.data ?? const TerminalUiState();
        return TerminalPage(controller: controller, state: state);
      },
    );
  }
}

/// The page: a tab strip over one attached screen.
class TerminalPage extends StatefulWidget {
  const TerminalPage({
    required this.controller,
    required this.state,
    super.key,
  });

  final TerminalSurface controller;
  final TerminalUiState state;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  Timer? _resizeDebounce;
  int _lastCols = 0;
  int _lastRows = 0;
  final TextEditingController _input = TextEditingController();

  /// The size to report, derived from the box the screen actually occupies:
  /// without a real emulator the cell count has to come from the layout.
  void _onLayout(BoxConstraints constraints) {
    // 12pt monospace is about 7.2 points wide and 15 tall.
    final cols = (constraints.maxWidth / 7.2).floor();
    final rows = (constraints.maxHeight / 15).floor();
    _onResize(cols, rows);
  }

  void _sendLine(String value) {
    if (value.isEmpty) {
      // An empty line is still a keystroke: the shell wants its newline.
      widget.controller.write('\r');
      return;
    }
    widget.controller.write('$value\r');
    _input.clear();
  }

  @override
  void dispose() {
    _resizeDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = widget.state;
    final attachment = widget.controller.selectedAttachment;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.terminalTitle),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.terminalNew,
            icon: const Icon(Icons.add),
            onPressed: state.unavailable
                ? null
                : () => unawaited(_pickShell(context)),
          ),
          if (state.selected case final info?)
            PopupMenuButton<String>(
              tooltip: l10n.terminalActions,
              onSelected: (String action) {
                switch (action) {
                  case 'rename':
                    unawaited(_rename(context, info));
                  case 'control':
                    unawaited(widget.controller.attach(info.id));
                  case 'close':
                    unawaited(widget.controller.close(info.id));
                }
              },
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'rename',
                  child: Text(l10n.terminalRename),
                ),
                if (attachment != null && !attachment.writable)
                  PopupMenuItem<String>(
                    value: 'control',
                    child: Text(l10n.terminalTakeControl),
                  ),
                PopupMenuItem<String>(
                  value: 'close',
                  child: Text(l10n.terminalClose),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (state.terminals.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: <Widget>[
                  for (final info in state.terminals)
                    _Tab(
                      info: info,
                      selected: info.id == state.selectedTerminalId,
                      onTap: () => widget.controller.select(info.id),
                    ),
                ],
              ),
            ),
          if (state.isLoading && state.terminals.isEmpty)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (state.unavailable)
            Expanded(child: _Notice(text: l10n.terminalUnavailable))
          else if (state.failed)
            Expanded(
              child: Center(
                child: TextButton(
                  onPressed: widget.controller.refresh,
                  child: Text(l10n.retry),
                ),
              ),
            )
          else if (attachment == null)
            Expanded(child: _Notice(text: l10n.terminalNoTerminal))
          else ...<Widget>[
            Container(
              width: double.infinity,
              color: scheme.surfaceContainer,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: <Widget>[
                  StateDot(state: _dotState(state, attachment), size: 8),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      terminalStatusLabel(state, l10n),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (state.notice case final notice?)
                    Text(
                      terminalNoticeLabel(notice, l10n),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.warning,
                      ),
                    ),
                  if (!attachment.writable &&
                      (attachment.info?.isRunning ?? false))
                    TextButton(
                      onPressed: () => unawaited(
                        widget.controller.attach(attachment.terminalId),
                      ),
                      child: Text(l10n.terminalTakeControl),
                    ),
                  if (attachment.phase == TerminalPhase.disconnected)
                    TextButton(
                      onPressed: () => unawaited(
                        widget.controller.attach(attachment.terminalId),
                      ),
                      child: Text(l10n.terminalReconnect),
                    ),
                  if (attachment.info case final info? when !info.isRunning)
                    TextButton(
                      onPressed: () => unawaited(_pickShell(context)),
                      child: Text(l10n.terminalNew),
                    ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _onLayout(constraints);
                  return Container(
                    color: scheme.terminalBackground,
                    width: double.infinity,
                    child: SingleChildScrollView(
                      reverse: false,
                      padding: const EdgeInsets.all(8),
                      child: SelectableText(
                        attachment.text,
                        style: TextStyle(
                          fontFamily: kCodeFontFamily,
                          fontFamilyFallback: kCodeFontFamilyFallback,
                          fontSize: 12,
                          height: 1.25,
                          color: scheme.terminalForeground,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (attachment.writable)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _input,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _sendLine,
                        decoration: InputDecoration(
                          hintText: l10n.terminalInputHint,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.send,
                      icon: const Icon(Icons.keyboard_return),
                      onPressed: () => _sendLine(_input.text),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  StateDotState _dotState(
    TerminalUiState state,
    TerminalAttachment attachment,
  ) => switch (attachment.info?.state) {
    TerminalState.running =>
      attachment.phase == TerminalPhase.connected
          ? StateDotState.ongoing
          : StateDotState.warning,
    TerminalState.exited => StateDotState.done,
    TerminalState.failed => StateDotState.error,
    null => StateDotState.disabled,
  };

  /// The fit is driven by the emulator's own proposal, clamped by the
  /// controller to the host's maximum and debounced so a rotation sends one
  /// resize instead of a burst.
  void _onResize(int cols, int rows) {
    if (cols == _lastCols && rows == _lastRows) return;
    _lastCols = cols;
    _lastRows = rows;
    _resizeDebounce?.cancel();
    _resizeDebounce = Timer(const Duration(milliseconds: 150), () {
      unawaited(widget.controller.resize(cols, rows));
    });
  }

  Future<void> _pickShell(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final shells = widget.state.shells;
    if (shells.isEmpty) {
      await widget.controller.createTerminal();
      return;
    }
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.terminalPickShell,
                style: Theme.of(sheetContext).textTheme.titleSmall,
              ),
            ),
            for (final shell in shells)
              ListTile(
                title: Text(shell.name),
                subtitle: Text(shell.path),
                onTap: () => Navigator.of(sheetContext).pop(shell.path),
              ),
          ],
        ),
      ),
    );
    // A dismissed picker creates nothing: choosing a shell is the action.
    if (chosen == null) return;
    await widget.controller.createTerminal(shellPath: chosen);
  }

  Future<void> _rename(BuildContext context, TerminalInfo info) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: info.title);
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.terminalRename),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null) return;
    await widget.controller.rename(info.id, title);
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.info, required this.selected, required this.onTap});

  final TerminalInfo info;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        selected: selected,
        onSelected: (_) => onTap(),
        avatar: Icon(
          Icons.terminal,
          size: 14,
          color: selected ? scheme.onSecondaryContainer : scheme.outline,
        ),
        label: Text(
          info.title.isEmpty ? info.shell.name : info.title,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// The status line for one terminal, localized (see the controller).
String terminalNoticeLabel(String notice, AppLocalizations l10n) {
  if (notice.startsWith('limit:')) {
    final limit = int.tryParse(notice.substring('limit:'.length));
    return l10n.terminalLimitReached(limit ?? 0);
  }
  return switch (notice) {
    'unavailable' => l10n.terminalUnavailable,
    'output gap' => l10n.terminalOutputGap,
    'input limit' => l10n.terminalInputTooLong,
    'invalid title' => l10n.terminalInvalidTitle,
    'close failed' => l10n.terminalCloseFailed,
    'read-only' => l10n.terminalReadOnly,
    'not-running' => l10n.terminalNotRunning,
    _ => notice,
  };
}
