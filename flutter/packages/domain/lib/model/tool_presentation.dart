/// Tool render-intent vocabulary the host persists on `tool/result`.
///
/// The host's `ToolDefinition.presentCall`/`presentResult` functions are
/// Host-only and never cross the wire; what a client receives is each tool's
/// persisted `output.presentationMeta`, carried as the `tool/result` event's
/// opaque `meta` member. The reducing adapter narrows that member back into
/// the reference's `ToolResultView` arms
/// (`reference/deepseek-harness/packages/core/tools/src/presentation.ts`):
/// `read`, `diff`, `search`, `web`, plus the persistent-terminal viewport
/// payload. A tool with no persisted metadata — or one whose payload
/// carries none of the known shapes — falls back to a generic row, exactly
/// as the reference's `presentResult` narrowers return `undefined`.
///
/// A diff here is READ-ONLY: the reference renders the applied change with
/// no accept/reject affordance, so no decision field exists.
library;

/// One numbered line of a read window (`ReadFileLine`).
final class ReadFileLine {
  const ReadFileLine({required this.number, required this.text});

  /// 1-based line number in the file.
  final int number;

  /// The line without its trailing newline, already truncated to the read
  /// tool's per-line cap.
  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadFileLine && other.number == number && other.text == text);

  @override
  int get hashCode => Object.hash(number, text);
}

/// One single-file change (`FileDiff`). `oldText` is null for a new file or
/// an overwrite with no prior content available at call time.
final class FileDiff {
  const FileDiff({
    required this.path,
    required this.oldText,
    required this.newText,
  });

  final String path;
  final String? oldText;
  final String newText;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FileDiff &&
          other.path == path &&
          other.oldText == oldText &&
          other.newText == newText);

  @override
  int get hashCode => Object.hash(path, oldText, newText);
}

/// One matched line inside a [SearchFileMatches].
final class SearchLineMatch {
  const SearchLineMatch({required this.lineNumber, required this.line});

  final int lineNumber;
  final String line;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SearchLineMatch &&
          other.lineNumber == lineNumber &&
          other.line == line);

  @override
  int get hashCode => Object.hash(lineNumber, line);
}

/// One file's grouped content matches, in first-seen file order.
final class SearchFileMatches {
  const SearchFileMatches({required this.path, required this.matches});

  final String path;
  final List<SearchLineMatch> matches;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SearchFileMatches &&
          other.path == path &&
          _listEquals(other.matches, matches));

  @override
  int get hashCode => Object.hash(path, Object.hashAll(matches));
}

/// One citeable source in a web-search card (`WebSource`).
final class WebSource {
  const WebSource({
    required this.url,
    this.title,
    this.snippet,
    this.publishedAt,
  });

  final String url;
  final String? title;
  final String? snippet;

  /// Provider-supplied ISO-8601 publication/crawl timestamp.
  final String? publishedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WebSource &&
          other.url == url &&
          other.title == title &&
          other.snippet == snippet &&
          other.publishedAt == publishedAt);

  @override
  int get hashCode => Object.hash(url, title, snippet, publishedAt);
}

/// A persisted tool-result presentation, narrowed from the `tool/result`
/// event's `meta` member. The set of arms mirrors the reference
/// `ToolResultView` union plus the persistent-terminal viewport payload.
sealed class ToolResultPresentation {
  const ToolResultPresentation();
}

/// A completed file read rendered as a line-numbered window
/// (`ReadResultView`).
final class ReadToolPresentation extends ToolResultPresentation {
  const ReadToolPresentation({
    required this.path,
    required this.offset,
    required this.lines,
    required this.totalLines,
    this.lang,
  });

  /// The read file's path (the model-facing path).
  final String path;

  /// The 1-based first line the window requested.
  final int offset;

  /// The returned window's lines, in file order.
  final List<ReadFileLine> lines;

  /// Exact total line count in the file.
  final int totalLines;

  /// Syntax-highlighting language hint derived from the extension.
  final String? lang;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadToolPresentation &&
          other.path == path &&
          other.offset == offset &&
          _listEquals(other.lines, lines) &&
          other.totalLines == totalLines &&
          other.lang == lang);

  @override
  int get hashCode =>
      Object.hash(path, offset, Object.hashAll(lines), totalLines, lang);
}

/// A completed file mutation rendered as inline hunks (`DiffResultView`).
final class DiffToolPresentation extends ToolResultPresentation {
  const DiffToolPresentation({required this.diffs});

  /// The change to show, in file order.
  final List<FileDiff> diffs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiffToolPresentation && _listEquals(other.diffs, diffs));

  @override
  int get hashCode => Object.hash('diff', Object.hashAll(diffs));
}

/// Which shape a search card carries.
enum SearchPresentationShape { matches, paths }

/// A completed content or path search (`SearchResultView`).
final class SearchToolPresentation extends ToolResultPresentation {
  const SearchToolPresentation._({
    required this.shape,
    required this.truncated,
    required this.total,
    this.files = const <SearchFileMatches>[],
    this.paths = const <String>[],
  });

  /// Grouped-by-file content matches (`grep`).
  const SearchToolPresentation.matches({
    required List<SearchFileMatches> files,
    required bool truncated,
    required int total,
  }) : this._(
         shape: SearchPresentationShape.matches,
         files: files,
         truncated: truncated,
         total: total,
       );

  /// Flat path list (`glob`).
  const SearchToolPresentation.paths({
    required List<String> paths,
    required bool truncated,
    required int total,
  }) : this._(
         shape: SearchPresentationShape.paths,
         paths: paths,
         truncated: truncated,
         total: total,
       );

  final SearchPresentationShape shape;

  /// Whether the tool capped the inline result.
  final bool truncated;

  /// Total results the search found before capping.
  final int total;

  /// Populated for [SearchPresentationShape.matches].
  final List<SearchFileMatches> files;

  /// Populated for [SearchPresentationShape.paths].
  final List<String> paths;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SearchToolPresentation &&
          other.shape == shape &&
          other.truncated == truncated &&
          other.total == total &&
          _listEquals(other.files, files) &&
          _listEquals(other.paths, paths));

  @override
  int get hashCode => Object.hash(
    shape,
    truncated,
    total,
    Object.hashAll(files),
    Object.hashAll(paths),
  );
}

/// Which web operation produced a web card.
enum WebPresentationKind { search, fetch }

/// A completed web retrieval (`WebResultView`).
final class WebToolPresentation extends ToolResultPresentation {
  const WebToolPresentation._({
    required this.kind,
    required this.truncated,
    this.sources = const <WebSource>[],
    this.answer,
    this.url,
    this.statusCode,
  });

  /// `web_search`: the structured sources and optional answer.
  const WebToolPresentation.search({
    required List<WebSource> sources,
    required bool truncated,
    String? answer,
  }) : this._(
         kind: WebPresentationKind.search,
         sources: sources,
         truncated: truncated,
         answer: answer,
       );

  /// `web_fetch`: the final URL and HTTP status.
  const WebToolPresentation.fetch({
    required String url,
    required int statusCode,
    required bool truncated,
  }) : this._(
         kind: WebPresentationKind.fetch,
         url: url,
         statusCode: statusCode,
         truncated: truncated,
       );

  final WebPresentationKind kind;

  /// Whether the provider capped the result.
  final bool truncated;

  /// Populated for [WebPresentationKind.search].
  final List<WebSource> sources;

  /// Provider-generated answer text, when any.
  final String? answer;

  /// Populated for [WebPresentationKind.fetch].
  final String? url;

  /// Populated for [WebPresentationKind.fetch].
  final int? statusCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WebToolPresentation &&
          other.kind == kind &&
          other.truncated == truncated &&
          _listEquals(other.sources, sources) &&
          other.answer == answer &&
          other.url == url &&
          other.statusCode == statusCode);

  @override
  int get hashCode => Object.hash(
    kind,
    truncated,
    Object.hashAll(sources),
    answer,
    url,
    statusCode,
  );
}

/// The persistent-terminal send's documented wait reason
/// (`terminal_send`'s `waitReason`).
enum TerminalWaitReason { stdinRead, inferredIdle, timeout, sessionExit }

/// A `tool/result` viewport payload persisted by the persistent-terminal
/// tools. This is the terminal tool's own `presentationMeta` — raw wire
/// fields, not a `TerminalResultView`; the reference derives output and
/// exit status from the execution result, which is not persisted.
final class TerminalToolPresentation extends ToolResultPresentation {
  const TerminalToolPresentation({
    required this.viewport,
    required this.waitReason,
    required this.truncated,
    required this.sessionStatus,
  });

  /// Bounded terminal viewport text.
  final String viewport;

  final TerminalWaitReason waitReason;

  /// Whether the viewport was capped.
  final bool truncated;

  /// The terminal session's status object, verbatim JSON members (the
  /// reference's `SESSION_STATUS_SCHEMA` is session-owned and merge-
  /// extensible, so its fields stay unmodelled).
  final Map<String, Object?> sessionStatus;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TerminalToolPresentation &&
          other.viewport == viewport &&
          other.waitReason == waitReason &&
          other.truncated == truncated &&
          _mapEquals(other.sessionStatus, sessionStatus));

  @override
  int get hashCode => Object.hash(
    viewport,
    waitReason,
    truncated,
    Object.hashAll(
      sessionStatus.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}
