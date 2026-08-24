/// Incremental block-level markdown parsing for an append-only stream.
///
/// Re-parsing the whole accumulated document on every streaming chunk is
/// quadratic in the final reply length — a huge repeated output (an agent
/// looping over a giant block) starves the UI thread. Block parsing is
/// line-based and appended text can only reshape the parse frontier — the
/// last couple of top-level blocks (a paragraph gaining its table
/// delimiter row, a list continuing, an unclosed fence swallowing lines)
/// — so every block behind the unstable tail is final. This parser
/// therefore freezes all but the trailing [unstableTailBlocks] blocks and
/// re-parses only the source tail behind them: each source region is
/// parsed O(1) times over the stream instead of once per chunk.
///
/// This is the Dart port of the reference web client's
/// `IncrementalMarkdownParser`
/// (reference/deepseek-harness/packages/client/ui-primitives/src/markdown/incremental.ts),
/// including the trailing-block margin and the freeze cut at the last
/// frozen block's end offset, so the two clients agree on where the tail
/// begins.
library;

import 'markdown_parser.dart';

/// Trailing blocks kept unstable. Appended text reshapes at most the last
/// block; the second-to-last is retained as safety margin so a freeze
/// decision never has to reason about the parse frontier (a paragraph
/// whose final line becomes a table header is the case that needs both).
const int unstableTailBlocks = 2;

/// Append-only incremental parser over [MarkdownParser.parseSpanned]. One
/// instance accumulates one streaming document; non-append input resets
/// it.
class IncrementalMarkdownParse {
  String _prevText = '';
  int _tailStart = 0;
  List<MarkdownBlock> _frozen = <MarkdownBlock>[];
  List<MarkdownBlock>? _cached;

  /// Fold the current accumulated text and return the whole block list.
  /// Idempotent for identical input (the previous result is returned
  /// as-is), so callers may invoke it from build paths that re-execute.
  /// Frozen prefix blocks keep their instances across updates, so a
  /// consumer keying work on block identity skips everything behind the
  /// tail.
  List<MarkdownBlock> update(String text) {
    final cached = _cached;
    if (cached != null && text == _prevText) return cached;
    // Deliberate O(prefix) memcmp per update: sound divergence detection
    // has to verify the whole retained prefix, and startsWith compares
    // bytes orders of magnitude faster than parsing them — the cost this
    // class exists to remove.
    if (!text.startsWith(_prevText)) {
      _prevText = '';
      _tailStart = 0;
      _frozen = <MarkdownBlock>[];
    }
    _prevText = text;
    final base = _tailStart;
    final parsed = MarkdownParser.parseSpanned(text.substring(base));
    var firstUnstable = parsed.length - unstableTailBlocks;
    if (firstUnstable < 0) firstUnstable = 0;
    if (firstUnstable > 0) {
      final cut = parsed[firstUnstable - 1].end;
      _frozen = <MarkdownBlock>[
        ..._frozen,
        for (final spanned in parsed.take(firstUnstable)) spanned.block,
      ];
      _tailStart = base + cut;
    }
    final result = <MarkdownBlock>[
      ..._frozen,
      for (final spanned in parsed.skip(firstUnstable)) spanned.block,
    ];
    _cached = result;
    return result;
  }
}
