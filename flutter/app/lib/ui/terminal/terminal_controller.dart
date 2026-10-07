/// Agent-terminal controller: the session's persistent user shells, one
/// attachment per open terminal, and the screen each attachment feeds.
///
/// Reference: `reference/deepseek-harness/packages/api/terminal-controller/
/// src/client/model.ts` (the browser's React-free terminal model) and
/// `.../client/ui-sidebar-terminal/src/client/terminal.tsx`. Three host facts
/// shape this port:
///
///  - a terminal outlives its attachment: collapsing, switching, or losing the
///    transport detaches, and only `terminal/close` (or host disposal) ends the
///    process. Reconnect therefore re-attaches with a **fresh** attachment id
///    and replays the new snapshot;
///  - there is no resume offset. Output missed while detached is only visible
///    if it is still inside the host's bounded scrollback, so a reconnect
///    resets the emulator rather than patching it;
///  - `terminal/create` allocates a shell with the host's own system-user
///    permissions, independent of the Agent's sandbox and approval policy.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/connection_state.dart';
import 'package:domain/model/terminal.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../state_stream.dart';
import 'terminal_screen_buffer.dart';

/// Where one terminal attachment is.
enum TerminalPhase {
  /// Listed but not attached: a restored tab before it opens.
  detached,
  attaching,
  connected,
  disconnected,
  closed,
  unavailable,
}

/// One terminal's client-side state: its emulator, its attachment, and what
/// the host last said about the process.
///
/// The frame rules live here rather than in the widget because they are the
/// wire contract: a generation opens with a snapshot whose `sequence` is the
/// anchor, every `output` must be exactly `anchor + 1`, and anything else is a
/// gap the surface recovers from by re-attaching (there is no resume offset).
final class TerminalAttachment {
  TerminalAttachment({required this.terminalId});

  final String terminalId;

  /// The visible screen: a bounded text render of the wire's ANSI stream.
  final TerminalScreenBuffer screen = TerminalScreenBuffer();

  /// The text the surface renders.
  String get text => screen.text;

  String? attachmentId;
  TerminalInfo? info;
  TerminalPhase phase = TerminalPhase.detached;

  /// The sequence the next `output` frame must carry.
  int? expectedSequence;

  /// True when a frame arrived out of order, which only a fresh snapshot can
  /// repair.
  bool sawGap = false;

  /// Whether a snapshot has been applied: the emulator holds a real screen.
  bool hasScreen = false;

  /// Whether this attachment holds input control.
  bool get writable =>
      phase == TerminalPhase.connected &&
      info?.isRunning == true &&
      info?.controllerId != null &&
      info?.controllerId == attachmentId;

  /// Applies one frame. Returns false when the frame was rejected as out of
  /// order — the caller must re-attach instead of writing it.
  bool applyTerminalFrame(TerminalFrame frame) {
    switch (frame) {
      case TerminalSnapshot(:final sequence, :final screen, :final info):
        this.info = info;
        // There is no resume: the snapshot is the whole screen, so the
        // emulator is cleared and replayed rather than patched. `\u001bc` is
        // RIS, which xterm.dart does not honor as a buffer reset, so the
        // scrollback and the display are erased explicitly.
        this.screen.reset(screen);
        expectedSequence = sequence;
        sawGap = false;
        hasScreen = true;
        phase = TerminalPhase.connected;
        return true;
      case TerminalOutput(:final sequence, :final data):
        if (expectedSequence != null && sequence != expectedSequence! + 1) {
          // Every generation numbers strictly from its snapshot; a jump means
          // frames were lost, and only a new snapshot can be trusted.
          sawGap = true;
          phase = TerminalPhase.disconnected;
          return false;
        }
        expectedSequence = sequence;
        screen.append(data);
        return true;
      case TerminalStateChange(:final info):
        this.info = info;
        return true;
    }
  }

  /// The dimensions to ask for, clamped to the host's own maximum and never
  /// below one row and two columns.
  static (int, int) clampDimensions(
    int cols,
    int rows,
    TerminalEnvironment? environment,
  ) {
    final maxCols = environment?.maxCols ?? cols;
    final maxRows = environment?.maxRows ?? rows;
    return (
      cols.clamp(2, maxCols < 2 ? 2 : maxCols),
      rows.clamp(1, maxRows < 1 ? 1 : maxRows),
    );
  }
}

/// What the terminal page needs from its owner.
///
/// The page is presentation over this seam, so its states are testable without
/// a repository double, and the controller stays the only thing that talks to
/// the wire.
abstract interface class TerminalSurface {
  /// The attachment the page renders, if a terminal is selected.
  TerminalAttachment? get selectedAttachment;

  void refresh();

  /// Sends input to the attached terminal, if this attachment owns control.
  void write(String data);
  Future<void> attach(String terminalId);
  Future<void> createTerminal({String? shellPath});
  Future<void> close(String terminalId);
  Future<void> rename(String terminalId, String title);
  Future<void> resize(int cols, int rows);
  void select(String terminalId);
}

/// The screen's state.
final class TerminalUiState {
  const TerminalUiState({
    this.isLoading = false,
    this.failed = false,
    this.unavailable = false,
    this.environment,
    this.shells = const <TerminalShell>[],
    this.terminals = const <TerminalInfo>[],
    this.selectedTerminalId,
    this.phase = TerminalPhase.detached,
    this.notice,
  });

  final bool isLoading;
  final bool failed;

  /// The host serves no `terminal` namespace: the pinned Web bundle mounts it,
  /// a headless or SDK profile does not.
  final bool unavailable;

  final TerminalEnvironment? environment;
  final List<TerminalShell> shells;
  final List<TerminalInfo> terminals;
  final String? selectedTerminalId;
  final TerminalPhase phase;

  /// A one-line condition the surface states: a limit, a lost attachment, or
  /// a cleanup failure.
  final String? notice;

  TerminalInfo? get selected {
    final id = selectedTerminalId;
    if (id == null) return null;
    for (final terminal in terminals) {
      if (terminal.id == id) return terminal;
    }
    return null;
  }
}

/// The session's terminals.
class TerminalController implements TerminalSurface {
  TerminalController(this._repository, {required this.sessionId}) {
    _connectionSub = _repository.observeConnectionState().listen((state) {
      if (state.phase == ConnectionPhase.connected) {
        unawaited(_reattachAfterReconnect());
      }
    });
    unawaited(load());
  }

  final ChatRepository _repository;
  final String sessionId;
  final AppStateStream<TerminalUiState> _state =
      AppStateStream<TerminalUiState>(const TerminalUiState());

  /// One attachment per open terminal, keyed by terminal id. The emulator
  /// survives a detach: its scrollback is the only record of output the host
  /// may have dropped.
  final Map<String, TerminalAttachment> attachments =
      <String, TerminalAttachment>{};

  StreamSubscription<void>? _framesSub;
  StreamSubscription<void>? _connectionSub;
  StreamSubscription<void>? _retainSub;
  bool _isLoading = false;
  bool _failed = false;
  bool _unavailable = false;
  TerminalEnvironment? _environment;
  List<TerminalShell> _shells = const <TerminalShell>[];
  List<TerminalInfo> _terminals = const <TerminalInfo>[];
  String? _selectedTerminalId;
  String? _notice;
  bool _inFlightWrite = false;
  final List<String> _queuedInput = <String>[];

  TerminalUiState get state => _state.value;
  Stream<TerminalUiState> get uiState => _state.stream;
  @override
  TerminalAttachment? get selectedAttachment {
    final id = _selectedTerminalId;
    return id == null ? null : attachments[id];
  }

  Future<void> dispose() async {
    await _framesSub?.cancel();
    await _connectionSub?.cancel();
    await _retainSub?.cancel();
  }

  @override
  void refresh() => unawaited(load());

  Future<void> load() async {
    _isLoading = true;
    _publish();
    try {
      final environment = await _repository.terminalEnvironment(sessionId);
      final shells = await _repository.terminalShells(sessionId);
      final terminals = await _repository.listTerminals(sessionId);
      _environment = environment;
      _shells = shells;
      _terminals = terminals;
      _unavailable = false;
      _failed = false;
    } on DshBusinessException catch (error, stackTrace) {
      _unavailable = error.code == 'gateway/invocation-unavailable';
      _failed = !_unavailable;
      if (!_unavailable) {
        _log(error, stackTrace, 'load');
      }
    } catch (error, stackTrace) {
      _failed = true;
      _unavailable = false;
      _log(error, stackTrace, 'load');
    } finally {
      _isLoading = false;
      _publish();
    }
  }

  /// Allocates one terminal for a caller-minted identity and attaches to it.
  @override
  Future<void> createTerminal({String? shellPath}) async {
    final environment = _environment;
    final cols = TerminalAttachment.clampDimensions(80, 24, environment).$1;
    final rows = TerminalAttachment.clampDimensions(80, 24, environment).$2;
    final id = 'term-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final info = await _repository.createTerminal(
        sessionId,
        id: id,
        cols: cols,
        rows: rows,
        shellPath: shellPath,
      );
      _terminals = <TerminalInfo>[
        ..._terminals.where((terminal) => terminal.id != info.id),
        info,
      ];
      _notice = null;
      await attach(info.id);
    } on DshBusinessException catch (error, stackTrace) {
      _notice = switch (error.code) {
        'terminal/limit-reached' => _limitNotice(error),
        // A terminal this identity no longer holds, or one the host began
        // cleaning up: re-attaching is the next step, not a retry of this.
        'terminal/unavailable' => 'unavailable',
        _ => error.message,
      };
      _log(error, stackTrace, 'create');
    } catch (error, stackTrace) {
      _notice = error.toString();
      _log(error, stackTrace, 'create');
    }
    _publish();
  }

  /// Attaches to one terminal with a fresh attachment id.
  ///
  /// A new attachment is the only way to recover: the previous one may be
  /// read-only (another window owns control) and the sequence anchor only
  /// exists per generation.
  @override
  Future<void> attach(String terminalId) async {
    final attachment = attachments.putIfAbsent(
      terminalId,
      () => TerminalAttachment(terminalId: terminalId),
    );
    _selectedTerminalId = terminalId;
    attachment.phase = TerminalPhase.attaching;
    _publish();

    await _framesSub?.cancel();
    // A window hold keeps this terminal alive while the tab is open, and it
    // works for a dormant session, which `follow` does not.
    await _retainSub?.cancel();
    _retainSub = _repository
        .retainTerminal(sessionId, terminalId)
        .listen((_) {}, onError: (Object _) {});

    final attachmentId =
        'att-${DateTime.now().microsecondsSinceEpoch}-${attachment.hashCode}';
    attachment.attachmentId = attachmentId;
    attachment.expectedSequence = null;
    _framesSub = _repository
        .observeTerminal(sessionId, terminalId, attachmentId)
        .listen(
          (frame) {
            final accepted = attachment.applyTerminalFrame(frame);
            if (!accepted) {
              _notice = 'output gap';
              unawaited(attach(terminalId));
              return;
            }
            _publish();
          },
          onError: (Object error, StackTrace stackTrace) {
            attachment.phase = TerminalPhase.disconnected;
            _notice = error.toString();
            _log(error, stackTrace, 'follow');
            _publish();
          },
          onDone: () {
            attachment.phase = TerminalPhase.disconnected;
            _publish();
          },
        );
    _publish();
  }

  Future<void> _reattachAfterReconnect() async {
    final id = _selectedTerminalId;
    if (id == null) return;
    final attachment = attachments[id];
    if (attachment == null) return;
    // The generation is gone; a fresh attachment re-establishes the screen
    // from a new snapshot rather than pretending the old one still streams.
    attachment.phase = TerminalPhase.disconnected;
    await attach(id);
  }

  /// Sends input to the attached terminal, serialized so keystrokes cannot
  /// overtake one another.
  @override
  void write(String data) {
    final attachment = selectedAttachment;
    if (attachment == null || !attachment.writable) return;
    final limit = _environment?.maxInputBytes ?? 65536;
    _queuedInput.add(data);
    unawaited(_drainInput(attachment, limit));
  }

  Future<void> _drainInput(TerminalAttachment attachment, int limit) async {
    if (_inFlightWrite) return;
    _inFlightWrite = true;
    try {
      while (_queuedInput.isNotEmpty) {
        final data = _queuedInput.removeAt(0);
        if (data.isEmpty) continue;
        if (data.length > limit) {
          // The host refuses an oversized write outright, so it never leaves
          // this client as one keystroke.
          _notice = 'input limit';
          continue;
        }
        final attachmentId = attachment.attachmentId;
        if (attachmentId == null) continue;
        try {
          await _repository.writeTerminal(
            sessionId,
            attachment.terminalId,
            attachmentId,
            data,
          );
        } on DshBusinessException catch (error, stackTrace) {
          // Losing control is not a transport failure: the terminal stays
          // attached and read-only until it is taken again.
          attachment.phase = TerminalPhase.connected;
          _notice = error.code;
          _log(error, stackTrace, 'write');
          _publish();
        } catch (error, stackTrace) {
          _log(error, stackTrace, 'write');
        }
      }
    } finally {
      _inFlightWrite = false;
    }
  }

  /// Resizes the terminal, clamped to the host's own maximum.
  @override
  Future<void> resize(int cols, int rows) async {
    final attachment = selectedAttachment;
    final attachmentId = attachment?.attachmentId;
    if (attachment == null || attachmentId == null || !attachment.writable) {
      return;
    }
    final (clampedCols, clampedRows) = TerminalAttachment.clampDimensions(
      cols,
      rows,
      _environment,
    );
    final info = attachment.info;
    if (info != null && info.cols == clampedCols && info.rows == clampedRows) {
      return;
    }
    try {
      await _repository.resizeTerminal(
        sessionId,
        attachment.terminalId,
        attachmentId,
        clampedCols,
        clampedRows,
      );
    } catch (error, stackTrace) {
      _log(error, stackTrace, 'resize');
    }
  }

  @override
  Future<void> rename(String terminalId, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed.length > 120) {
      _notice = 'invalid title';
      _publish();
      return;
    }
    try {
      await _repository.renameTerminal(sessionId, terminalId, trimmed);
      _terminals = _terminals
          .map(
            (terminal) => terminal.id == terminalId
                ? TerminalInfo(
                    id: terminal.id,
                    title: trimmed,
                    shell: terminal.shell,
                    cwd: terminal.cwd,
                    cols: terminal.cols,
                    rows: terminal.rows,
                    state: terminal.state,
                    exitCode: terminal.exitCode,
                    error: terminal.error,
                    controllerId: terminal.controllerId,
                  )
                : terminal,
          )
          .toList();
    } catch (error, stackTrace) {
      _notice = error.toString();
      _log(error, stackTrace, 'rename');
    }
    _publish();
  }

  /// Closes one terminal and its process.
  ///
  /// The row is removed from the view immediately, as the reference does, and
  /// a cleanup failure is stated with a retry rather than left silent.
  @override
  Future<void> close(String terminalId) async {
    _terminals = _terminals
        .where((terminal) => terminal.id != terminalId)
        .toList();
    if (_selectedTerminalId == terminalId) {
      _selectedTerminalId = _terminals.isEmpty ? null : _terminals.first.id;
    }
    final attachment = attachments.remove(terminalId);
    if (attachment != null) await _framesSub?.cancel();
    _publish();
    try {
      await _repository.closeTerminal(sessionId, terminalId);
      _notice = null;
    } catch (error, stackTrace) {
      // The host keeps the terminal for a retry; put it back so the surface
      // does not claim a cleanup that did not happen.
      final removedInfo = attachment?.info;
      _terminals = <TerminalInfo>[
        ..._terminals,
        if (removedInfo != null) removedInfo,
      ];
      _notice = 'close failed';
      _log(error, stackTrace, 'close');
    }
    _publish();
  }

  @override
  void select(String terminalId) {
    if (_selectedTerminalId == terminalId) return;
    _selectedTerminalId = terminalId;
    final attachment = attachments[terminalId];
    if (attachment == null || !attachment.hasScreen) {
      unawaited(attach(terminalId));
      return;
    }
    _publish();
  }

  String? _limitNotice(DshBusinessException error) {
    final limit = error.details?['limit'];
    return limit is int ? 'limit:$limit' : error.message;
  }

  void _log(Object error, StackTrace stackTrace, String action) {
    ErrorLogCollector.instance.captureError(
      error,
      stackTrace: stackTrace,
      context: <String, Object?>{
        'controller': 'TerminalController',
        'action': action,
        'sessionId': sessionId,
      },
    );
  }

  void _publish() {
    _state.value = TerminalUiState(
      isLoading: _isLoading,
      failed: _failed,
      unavailable: _unavailable,
      environment: _environment,
      shells: _shells,
      terminals: _terminals,
      selectedTerminalId: _selectedTerminalId,
      phase: selectedAttachment?.phase ?? TerminalPhase.detached,
      notice: _notice,
    );
  }
}

/// One controller per session, disposed with the terminal surface.
final terminalControllerProvider = Provider.family
    .autoDispose<TerminalController, (String, String)>((ref, key) {
      final controller = TerminalController(
        ref.watch(chatRepositoryProvider(key.$1)),
        sessionId: key.$2,
      );
      ref.onDispose(() => unawaited(controller.dispose()));
      return controller;
    });

/// The status line above a terminal's screen.
String terminalStatusLabel(TerminalUiState state, AppLocalizations l10n) {
  final info = state.selected;
  if (info == null) return l10n.terminalStatusDetached;
  return switch (info.state) {
    TerminalState.running => switch (state.phase) {
      TerminalPhase.attaching => l10n.terminalStatusConnecting,
      TerminalPhase.connected => l10n.terminalStatusRunning,
      TerminalPhase.disconnected => l10n.terminalStatusDisconnected,
      _ => l10n.terminalStatusDetached,
    },
    TerminalState.exited => l10n.terminalStatusExited(info.exitCode ?? 0),
    TerminalState.failed => l10n.terminalStatusFailed,
  };
}
