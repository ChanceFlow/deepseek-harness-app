/// Lightweight code tokenizer for the transcript's fenced blocks.
///
/// This is a reading affordance, not a language service: it splits a code body
/// into the four token classes a reader scans for — comments, strings, numbers
/// and keywords — and leaves everything else as plain text. A block whose
/// language this file does not know is returned as a single plain run, so an
/// unknown fence degrades to the pre-highlighting rendering rather than to
/// guessed colour.
///
/// The tokenizer is pure Dart with no Flutter dependency, so the widget layer
/// owns every colour decision and this file stays unit-testable on its own.
library;

/// The token classes the renderer paints. [plain] carries no emphasis: it is
/// identifiers, punctuation and whitespace.
enum CodeTokenKind { plain, comment, string, number, keyword }

/// One run of same-kind characters, in document order.
final class CodeToken {
  const CodeToken(this.kind, this.text);

  final CodeTokenKind kind;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is CodeToken && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => '${kind.name}(${text.replaceAll('\n', r'\n')})';
}

/// Comment prefixes per language family: the rest of the line after one of
/// these is a comment. Block-comment pairs live in [_blockComments].
const Map<String, String> _lineComment = {
  'dart': '//',
  'javascript': '//',
  'typescript': '//',
  'json': '',
  'yaml': '#',
  'python': '#',
  'bash': '#',
  'sql': '--',
};

/// Block-comment pairs per language family.
const Map<String, (String, String)> _blockComments = {
  'dart': ('/*', '*/'),
  'javascript': ('/*', '*/'),
  'typescript': ('/*', '*/'),
  'sql': ('/*', '*/'),
};

/// Quote characters that open a string in each family. Dart and the JS family
/// also carry a raw/backtick form; JSON quotes only with `"`.
const Map<String, List<String>> _quotes = {
  'dart': ["'", '"', "'''", '"""'],
  'javascript': ["'", '"', '`'],
  'typescript': ["'", '"', '`'],
  'json': ['"'],
  'yaml': ["'", '"'],
  'python': ["'", '"', "'''", '"""'],
  'bash': ["'", '"'],
  'sql': ["'"],
};

/// Words that read as structure rather than as data, per family.
const Map<String, Set<String>> _keywords = {
  'dart': {
    'abstract',
    'as',
    'assert',
    'async',
    'await',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'covariant',
    'default',
    'deferred',
    'do',
    'dynamic',
    'else',
    'enum',
    'export',
    'extends',
    'extension',
    'external',
    'factory',
    'false',
    'final',
    'finally',
    'for',
    'get',
    'hide',
    'if',
    'implements',
    'import',
    'in',
    'interface',
    'is',
    'late',
    'library',
    'mixin',
    'new',
    'null',
    'on',
    'operator',
    'part',
    'required',
    'rethrow',
    'return',
    'sealed',
    'set',
    'show',
    'static',
    'super',
    'switch',
    'sync',
    'this',
    'throw',
    'true',
    'try',
    'typedef',
    'var',
    'void',
    'when',
    'while',
    'with',
    'yield',
  },
  'javascript': {
    'async',
    'await',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'debugger',
    'default',
    'delete',
    'do',
    'else',
    'export',
    'extends',
    'false',
    'finally',
    'for',
    'function',
    'if',
    'import',
    'in',
    'instanceof',
    'let',
    'new',
    'null',
    'of',
    'return',
    'static',
    'super',
    'switch',
    'this',
    'throw',
    'true',
    'try',
    'typeof',
    'undefined',
    'var',
    'void',
    'while',
    'yield',
  },
  'typescript': {
    'abstract',
    'any',
    'as',
    'async',
    'await',
    'boolean',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'declare',
    'default',
    'delete',
    'do',
    'else',
    'enum',
    'export',
    'extends',
    'false',
    'finally',
    'for',
    'function',
    'if',
    'implements',
    'import',
    'in',
    'instanceof',
    'interface',
    'keyof',
    'let',
    'namespace',
    'never',
    'new',
    'null',
    'number',
    'of',
    'private',
    'protected',
    'public',
    'readonly',
    'return',
    'static',
    'string',
    'super',
    'switch',
    'this',
    'throw',
    'true',
    'try',
    'type',
    'typeof',
    'undefined',
    'unknown',
    'var',
    'void',
    'while',
    'yield',
  },
  'json': {'true', 'false', 'null'},
  'yaml': {'true', 'false', 'null', 'yes', 'no', 'on', 'off'},
  'python': {
    'and',
    'as',
    'assert',
    'async',
    'await',
    'break',
    'class',
    'continue',
    'def',
    'del',
    'elif',
    'else',
    'except',
    'False',
    'finally',
    'for',
    'from',
    'global',
    'if',
    'import',
    'in',
    'is',
    'lambda',
    'None',
    'nonlocal',
    'not',
    'or',
    'pass',
    'raise',
    'return',
    'True',
    'try',
    'while',
    'with',
    'yield',
  },
  'bash': {
    'case',
    'do',
    'done',
    'elif',
    'else',
    'esac',
    'fi',
    'for',
    'function',
    'if',
    'in',
    'local',
    'return',
    'then',
    'until',
    'while',
  },
  'sql': {
    'ALL',
    'AND',
    'AS',
    'ASC',
    'BY',
    'CREATE',
    'DELETE',
    'DESC',
    'DISTINCT',
    'DROP',
    'FROM',
    'GROUP',
    'HAVING',
    'INDEX',
    'INSERT',
    'INTO',
    'JOIN',
    'LEFT',
    'LIMIT',
    'NOT',
    'NULL',
    'OFFSET',
    'ON',
    'OR',
    'ORDER',
    'OUTER',
    'PRIMARY',
    'SELECT',
    'SET',
    'TABLE',
    'UPDATE',
    'VALUES',
    'WHERE',
  },
};

/// Fence languages whose body [_aliases] maps to a known family.
const Map<String, String> _aliases = {
  'dart': 'dart',
  'js': 'javascript',
  'jsx': 'javascript',
  'javascript': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'typescript': 'typescript',
  'json': 'json',
  'jsonc': 'json',
  'yml': 'yaml',
  'yaml': 'yaml',
  'py': 'python',
  'python': 'python',
  'sh': 'bash',
  'shell': 'bash',
  'bash': 'bash',
  'zsh': 'bash',
  'console': 'bash',
  'sql': 'sql',
};

/// Whether [language] (a fence info string) has a known tokenizer.
bool codeLanguageIsKnown(String? language) => _familyOf(language) != null;

/// Tokenize [code] as [language]. An unknown or absent language, or a body that
/// is empty, yields a single plain run so the caller can render it uniformly.
List<CodeToken> tokenizeCode(String code, String? language) {
  final family = _familyOf(language);
  if (family == null || code.isEmpty) {
    return code.isEmpty
        ? const <CodeToken>[]
        : [CodeToken(CodeTokenKind.plain, code)];
  }
  return _Scanner(code, family).run();
}

String? _familyOf(String? language) {
  if (language == null) return null;
  final key = language.trim().toLowerCase();
  if (key.isEmpty) return null;
  // A fence info string may carry attributes after the language
  // (```dart title="x"); only the first word names the language.
  final first = key.split(RegExp(r'[\s,{}]')).first;
  return _aliases[first];
}

class _Scanner {
  _Scanner(this._code, this._family);

  final String _code;
  final String _family;
  int _at = 0;
  final List<CodeToken> _out = <CodeToken>[];

  String? get _lineCommentMark => _lineComment[_family];
  (String, String)? get _blockCommentMarks => _blockComments[_family];
  List<String> get _quoteMarks => _quotes[_family] ?? const <String>[];
  Set<String> get _keywordSet => _keywords[_family] ?? const <String>{};
  bool get _keywordsAreCaseInsensitive => _family == 'sql';

  List<CodeToken> run() {
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isEmpty) return;
      _out.add(CodeToken(CodeTokenKind.plain, buffer.toString()));
      buffer.clear();
    }

    while (_at < _code.length) {
      final block = _blockCommentMarks;
      if (block != null && _code.startsWith(block.$1, _at)) {
        flush();
        final end = _code.indexOf(block.$2, _at + block.$1.length);
        final stop = end == -1 ? _code.length : end + block.$2.length;
        _out.add(CodeToken(CodeTokenKind.comment, _code.substring(_at, stop)));
        _at = stop;
        continue;
      }
      final lineMark = _lineCommentMark;
      if (lineMark != null &&
          lineMark.isNotEmpty &&
          _code.startsWith(lineMark, _at)) {
        flush();
        final end = _code.indexOf('\n', _at);
        final stop = end == -1 ? _code.length : end;
        _out.add(CodeToken(CodeTokenKind.comment, _code.substring(_at, stop)));
        _at = stop;
        continue;
      }
      // The longest matching mark wins: `"""` opens a triple-quoted run, and
      // matching `"` first would cut it into three empty-looking strings.
      String? quote;
      for (final mark in _quoteMarks) {
        if (_code.startsWith(mark, _at) &&
            (quote == null || mark.length > quote.length)) {
          quote = mark;
        }
      }
      if (quote != null) {
        flush();
        _out.add(CodeToken(CodeTokenKind.string, _readString(quote)));
        continue;
      }
      final char = _code[_at];
      if (_isDigit(char)) {
        flush();
        _out.add(CodeToken(CodeTokenKind.number, _readNumber()));
        continue;
      }
      if (_isIdentifierStart(char)) {
        final start = _at;
        while (_at < _code.length && _isIdentifierPart(_code[_at])) {
          _at++;
        }
        final word = _code.substring(start, _at);
        final isKeyword = _keywordsAreCaseInsensitive
            ? _keywordSet.contains(word.toUpperCase())
            : _keywordSet.contains(word);
        if (isKeyword) {
          flush();
          _out.add(CodeToken(CodeTokenKind.keyword, word));
        } else {
          buffer.write(word);
        }
        continue;
      }
      buffer.write(char);
      _at++;
    }
    flush();
    return _out;
  }

  /// Reads a quoted run starting at [_at], tolerating a backslash escape and a
  /// newline inside the run so an unterminated string colours to the end of the
  /// line rather than swallowing the block.
  String _readString(String quote) {
    final start = _at;
    _at += quote.length;
    while (_at < _code.length) {
      final char = _code[_at];
      if (char == r'\' && _at + 1 < _code.length) {
        _at += 2;
        continue;
      }
      if (char == '\n' && quote.length == 1) {
        // A single-quoted run does not cross a line in any family here.
        break;
      }
      if (_code.startsWith(quote, _at)) {
        _at += quote.length;
        break;
      }
      _at++;
    }
    return _code.substring(start, _at);
  }

  String _readNumber() {
    final start = _at;
    if (_code.startsWith('0x', _at) || _code.startsWith('0X', _at)) {
      _at += 2;
      while (_at < _code.length && _isHexDigit(_code[_at])) {
        _at++;
      }
      return _code.substring(start, _at);
    }
    while (_at < _code.length) {
      final char = _code[_at];
      if (_isDigit(char) || char == '.' || char == '_') {
        _at++;
        continue;
      }
      // An exponent (1e-9) is part of the literal.
      if ((char == 'e' || char == 'E') && _at + 1 < _code.length) {
        final next = _code[_at + 1];
        if (_isDigit(next) ||
            ((next == '+' || next == '-') &&
                _at + 2 < _code.length &&
                _isDigit(_code[_at + 2]))) {
          _at += 2;
          continue;
        }
      }
      break;
    }
    return _code.substring(start, _at);
  }

  static bool _isDigit(String c) {
    final code = c.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  static bool _isHexDigit(String c) {
    final code = c.codeUnitAt(0);
    return _isDigit(c) ||
        (code >= 0x61 && code <= 0x66) ||
        (code >= 0x41 && code <= 0x46);
  }

  static bool _isIdentifierStart(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A) ||
        code == 0x5F ||
        code == 0x24;
  }

  static bool _isIdentifierPart(String c) =>
      _isIdentifierStart(c) || _isDigit(c);
}
