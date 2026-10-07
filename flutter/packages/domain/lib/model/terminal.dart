/// Terminal vocabulary: the host's persistent user shells and the screen
/// stream a browser attaches to one.
///
/// Wire shapes come from
/// `reference/deepseek-harness/packages/api/terminal-controller/src/types.ts`.
/// Two facts shape every caller: a terminal outlives its attachment — only
/// `close` (or host disposal, or unattended reclamation) ends the process —
/// and reconnect carries no cursor, so a new attachment always begins with a
/// complete screen snapshot rather than a resumed byte offset.
library;

/// An executable shell the host verified in its execution environment
/// (`TerminalShell`).
final class TerminalShell {
  const TerminalShell({
    required this.path,
    required this.name,
    this.args = const <String>[],
  });

  final String path;
  final List<String> args;
  final String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TerminalShell &&
          other.path == path &&
          other.name == name &&
          _listEquals(other.args, args));

  @override
  int get hashCode => Object.hash(path, name, Object.hashAll(args));
}

/// The working directory and limits shared by new and restored terminals
/// (`TerminalEnvironment`).
///
/// There are no environment variables here: the shell is spawned with the
/// host's own execution environment, so `cwd` and the limits are all the
/// client configures.
final class TerminalEnvironment {
  const TerminalEnvironment({
    required this.cwd,
    required this.maxInputBytes,
    required this.maxCols,
    required this.maxRows,
    required this.scrollback,
  });

  final String cwd;
  final int maxInputBytes;
  final int maxCols;
  final int maxRows;
  final int scrollback;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TerminalEnvironment &&
          other.cwd == cwd &&
          other.maxInputBytes == maxInputBytes &&
          other.maxCols == maxCols &&
          other.maxRows == maxRows &&
          other.scrollback == scrollback);

  @override
  int get hashCode =>
      Object.hash(cwd, maxInputBytes, maxCols, maxRows, scrollback);
}

/// Whether a terminal's process is still alive (`WebTerminalInfo.state`).
enum TerminalState { running, exited, failed }

/// One host terminal (`WebTerminalInfo`).
///
/// [cwd] is the *initial* working directory: a shell's own `cd` never updates
/// it. [controllerId] names the attachment that currently owns input; when it
/// is not this client's, the terminal renders read-only with a control-taking
/// affordance.
final class TerminalInfo {
  const TerminalInfo({
    required this.id,
    required this.title,
    required this.shell,
    required this.cwd,
    required this.cols,
    required this.rows,
    required this.state,
    this.exitCode,
    this.error,
    this.controllerId,
  });

  final String id;
  final String title;
  final TerminalShell shell;
  final String cwd;
  final int cols;
  final int rows;
  final TerminalState state;

  /// The process exit code; null while running or when the host never saw one.
  final int? exitCode;
  final String? error;

  /// The attachment allowed to write and resize, when one holds control.
  final String? controllerId;

  /// Whether the process is still alive.
  bool get isRunning => state == TerminalState.running;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TerminalInfo &&
          other.id == id &&
          other.title == title &&
          other.shell == shell &&
          other.cwd == cwd &&
          other.cols == cols &&
          other.rows == rows &&
          other.state == state &&
          other.exitCode == exitCode &&
          other.error == error &&
          other.controllerId == controllerId);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    shell,
    cwd,
    cols,
    rows,
    state,
    exitCode,
    error,
    controllerId,
  );
}

/// One frame of a terminal attachment
/// (`TerminalFrame`).
///
/// A generation always opens with [TerminalSnapshot]: its [sequence] is the
/// anchor the following [TerminalOutput] frames continue from, and the client
/// must reset its emulator and replay [screen] before consuming them. Sequence
/// numbers are strictly `previous + 1`; [TerminalStateChange] carries none.
sealed class TerminalFrame {
  const TerminalFrame();
}

/// The complete bounded screen at attachment time.
final class TerminalSnapshot extends TerminalFrame {
  const TerminalSnapshot({
    required this.sequence,
    required this.screen,
    required this.info,
  });

  final int sequence;
  final String screen;
  final TerminalInfo info;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TerminalSnapshot &&
          other.sequence == sequence &&
          other.screen == screen &&
          other.info == info);

  @override
  int get hashCode => Object.hash(sequence, screen, info);
}

/// Ordered output after the snapshot's anchor.
final class TerminalOutput extends TerminalFrame {
  const TerminalOutput({required this.sequence, required this.data});

  final int sequence;
  final String data;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TerminalOutput &&
          other.sequence == sequence &&
          other.data == data);

  @override
  int get hashCode => Object.hash(sequence, data);
}

/// A metadata change: title, dimensions, process state, or the holder of
/// input control.
final class TerminalStateChange extends TerminalFrame {
  const TerminalStateChange({required this.info});

  final TerminalInfo info;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TerminalStateChange && other.info == info);

  @override
  int get hashCode => info.hashCode;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
