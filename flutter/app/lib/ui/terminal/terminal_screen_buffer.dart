/// A bounded plain-text screen for one terminal attachment.
///
/// The host publishes an ANSI screen (`terminal/follow`'s `snapshot.screen`)
/// followed by ordered output chunks. This client renders that as text: the
/// escape sequences the wire carries are consumed rather than printed, the
/// erasures that change *what text exists* are honored, and everything else —
/// colors, attributes, cursor addressing, alternate-screen switching — is
/// dropped with the limitation stated in the UI.
///
/// Why not a full VT emulator: the shipped toolchain image ships a primed pub
/// cache and the analyze gate runs `--no-pub`, so a new pub dependency cannot
/// be resolved by the gate set that proves this change. Decision note:
/// [Terminals](../../../../.agents/notes/implemented/feature/2026-09-29-terminals.md).
library;

/// The widest screen this buffer keeps, in characters.
const int kTerminalScreenCharacterLimit = 200 * 1024;

/// One attachment's visible text.
///
/// The model is a line being written plus a cursor column, which is the least
/// a text view needs to render honestly:
///
///  - a carriage return moves the cursor to column 0, so a rewritten progress
///    line replaces what was there instead of duplicating it;
///  - a line feed commits the line;
///  - a backspace steps over the character before the cursor;
///  - an erase-display sequence clears the screen.
///
/// Everything else the wire carries — colors, attributes, cursor addressing,
/// alternate screens — is consumed and dropped, and the UI says so.
final class TerminalScreenBuffer {
  TerminalScreenBuffer({this.limit = kTerminalScreenCharacterLimit});

  /// The most characters of committed text kept; the oldest are dropped from
  /// the front so a long-running shell cannot grow without bound.
  final int limit;

  /// Committed lines, newest last, always ending in a newline.
  String _committed = '';

  /// The line being written, not yet committed by a line feed.
  String _line = '';

  /// The column the next character lands on.
  int _cursor = 0;

  /// The visible text, newest last.
  String get text => _committed + _line;

  /// Whether anything has been rendered yet.
  bool get isEmpty => text.isEmpty;

  /// Replaces the screen from a snapshot: there is no resume offset, so a new
  /// generation's snapshot *is* the whole screen.
  void reset(String screen) {
    _committed = '';
    _line = '';
    _cursor = 0;
    _write(screen);
    _trim();
  }

  /// Appends one output chunk.
  void append(String data) {
    _write(data);
    _trim();
  }

  void _write(String input) {
    var index = 0;
    while (index < input.length) {
      final code = input.codeUnitAt(index);
      if (code == 0x1b) {
        index = _consumeEscape(input, index);
        continue;
      }
      switch (code) {
        case 0x0d:
          _cursor = 0;
        case 0x0a:
          _committed = '$_committed$_line\n';
          _line = '';
          _cursor = 0;
        case 0x08:
          if (_cursor > 0) {
            _line = _line.substring(0, _cursor - 1) + _line.substring(_cursor);
            _cursor--;
          }
        case 0x07:
          break;
        case 0x09:
          // A tab advances to the next eight-column stop.
          final stop = _cursor + 8 - (_cursor % 8);
          _put(' ' * (stop - _cursor));
        default:
          _put(String.fromCharCode(code));
      }
      index++;
    }
  }

  /// Writes [text] at the cursor, overwriting what is already on the line.
  void _put(String text) {
    final end = _cursor + text.length;
    if (_cursor > _line.length) {
      _line = _line + ' ' * (_cursor - _line.length) + text;
    } else if (end <= _line.length) {
      _line = _line.substring(0, _cursor) + text + _line.substring(end);
    } else {
      _line = _line.substring(0, _cursor) + text;
    }
    _cursor = end;
  }

  /// Consumes one escape sequence starting at [start] and returns the index
  /// after it.
  int _consumeEscape(String input, int start) {
    if (start + 1 >= input.length) return input.length;
    final next = input.codeUnitAt(start + 1);
    if (next == 0x5b) {
      var index = start + 2;
      final params = StringBuffer();
      while (index < input.length) {
        final code = input.codeUnitAt(index);
        if (code >= 0x40 && code <= 0x7e) break;
        params.writeCharCode(code);
        index++;
      }
      final finalByte = index < input.length ? input[index] : '';
      if (finalByte == 'J') {
        // Erase display: `2` and `3` clear everything. `0` and `1` are partial
        // erases a text view cannot express, so they are no-ops rather than
        // guesses.
        final mode = params.toString().split(';').first;
        if (mode == '2' || mode == '3') {
          _committed = '';
          _line = '';
          _cursor = 0;
        }
      }
      return index + 1;
    }
    if (next == 0x5d) {
      // OSC, terminated by BEL or ST.
      var index = start + 2;
      while (index < input.length) {
        final code = input.codeUnitAt(index);
        if (code == 0x07) return index + 1;
        if (code == 0x1b &&
            index + 1 < input.length &&
            input.codeUnitAt(index + 1) == 0x5c) {
          return index + 2;
        }
        index++;
      }
      return input.length;
    }
    // Every other escape is a short sequence with nothing to render:
    // charset selection takes three bytes, the rest take two.
    if (next == 0x28 || next == 0x29 || next == 0x2a || next == 0x2b) {
      return start + 3 <= input.length ? start + 3 : input.length;
    }
    return start + 2;
  }

  void _trim() {
    final overflow = _committed.length + _line.length - limit;
    if (overflow <= 0) return;
    if (overflow >= _committed.length) {
      final drop = overflow - _committed.length;
      _committed = '';
      _line = drop >= _line.length ? '' : _line.substring(drop);
      _cursor = _cursor > _line.length ? _line.length : _cursor;
      return;
    }
    _committed = _committed.substring(overflow);
  }
}
