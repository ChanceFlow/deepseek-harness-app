/// Renders one message body as markdown blocks. The parser output is plain
/// data; every color, font, and shape decision stays in this layer.
///
/// The body is a document, so it reads like one: blocks are separated by
/// space that names their relationship, a list marker sits in its own
/// column so wrapped text hangs under the text and not under the marker,
/// and every glyph is selectable — a path or an identifier is copied on its
/// own, without the message around it.
///
/// Rendering is incremental across a stream: all but the trailing two
/// blocks freeze (the reference web client's `IncrementalMarkdownParser`
/// rule), and a frozen block's widget instance is reused verbatim, so a
/// streaming chunk re-parses and re-builds only the tail while settled
/// messages cost nothing on each rebuild. The block widgets bake in theme
/// and locale reads; a dependency change discards the widget cache (the
/// parsed blocks stay valid).
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/theme.dart';
import 'code_highlight.dart';
import 'incremental.dart';
import 'markdown_parser.dart';

/// Column the list marker occupies; wrapped text aligns to its right edge.
const double _kMarkerColumn = 22;

/// Indent one nesting level adds.
const double _kNestIndent = 16;

class MarkdownText extends StatefulWidget {
  const MarkdownText({required this.text, super.key});

  final String text;

  @override
  State<MarkdownText> createState() => _MarkdownTextState();
}

class _MarkdownTextState extends State<MarkdownText> {
  final IncrementalMarkdownParse _parse = IncrementalMarkdownParse();

  /// Current block list for [MarkdownText.text]; instance-stable prefix
  /// across streaming appends.
  List<MarkdownBlock> _blocks = const <MarkdownBlock>[];

  /// Blocks and their widgets as last rendered. An identical block
  /// instance in the same position reuses its widget instance verbatim —
  /// Flutter skips a subtree whose widget did not change identity.
  List<MarkdownBlock> _renderedBlocks = const <MarkdownBlock>[];
  List<Widget> _renderedWidgets = const <Widget>[];
  bool _widgetsDirty = true;

  @override
  void initState() {
    super.initState();
    _blocks = _parse.update(widget.text);
  }

  @override
  void didUpdateWidget(covariant MarkdownText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _blocks = _parse.update(widget.text);
      _widgetsDirty = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Block widgets resolve Theme and AppLocalizations at build time; a
    // dependency change invalidates them. The parse stays valid.
    _renderedBlocks = const <MarkdownBlock>[];
    _renderedWidgets = const <Widget>[];
    _widgetsDirty = true;
  }

  @override
  Widget build(BuildContext context) {
    if (_widgetsDirty) {
      final widgets = <Widget>[];
      for (var i = 0; i < _blocks.length; i++) {
        final block = _blocks[i];
        // An unchanged block keeps its widget instance — identity for the
        // frozen prefix (O(1)), deep equality for the unstable tail's
        // settled blocks — so Flutter skips a subtree whose widget did
        // not change, and a streaming chunk only pays for what moved.
        final rendered = i < _renderedBlocks.length ? _renderedBlocks[i] : null;
        widgets.add(
          rendered != null && (identical(rendered, block) || rendered == block)
              ? _renderedWidgets[i]
              : _block(context, block),
        );
      }
      _renderedBlocks = _blocks;
      _renderedWidgets = widgets;
      _widgetsDirty = false;
    }
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _renderedWidgets.length; i++) ...[
            if (i > 0)
              SizedBox(height: _gapBetween(_blocks[i - 1], _blocks[i])),
            _renderedWidgets[i],
          ],
        ],
      ),
    );
  }

  /// Space between two blocks says what their relationship is: a heading
  /// opens a section, its first block belongs to it, everything else is a
  /// sibling paragraph.
  static double _gapBetween(MarkdownBlock previous, MarkdownBlock next) {
    if (next is HeadingBlock) return 16;
    if (previous is HeadingBlock) return 6;
    return 10;
  }

  Widget _block(BuildContext context, MarkdownBlock block) {
    final theme = Theme.of(context);
    switch (block) {
      case CodeBlock():
        return _codeBlock(context, block);
      case HeadingBlock():
        // A reply is not a web page: headings stay inside the reading
        // scale and separate by weight and space. None of them drops below
        // the body size — a section title smaller than its own paragraph
        // inverts the hierarchy it is there to state. The weights are the
        // reference's own markdown steps: h3 `700`
        // (`gradient-shadow-text.css:77`), h4 and below `600` (`:84`).
        final Color ink = theme.colorScheme.labelPrimary;
        final style = switch (block.level) {
          1 => DshType.markdownH1.style(color: ink),
          2 => DshType.markdownH2.style(color: ink),
          3 => DshType.markdownH3.style(color: ink),
          _ => DshType.markdownH4.style(color: ink),
        };
        return Text.rich(_inlineSpan(context, block.inlines), style: style);
      case BulletListBlock():
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < block.items.length; i++)
              _listRow(
                context,
                depth: block.items[i].depth,
                marker: block.items[i].depth == 0 ? '•' : '–',
                inlines: block.items[i].inlines,
                first: i == 0,
              ),
          ],
        );
      case OrderedListBlock():
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < block.items.length; i++)
              _listRow(
                context,
                depth: block.items[i].depth,
                marker: '${block.items[i].number}.',
                inlines: block.items[i].inlines,
                first: i == 0,
                markerAtEnd: true,
              ),
          ],
        );
      case BlockQuoteBlock():
        // The reference's quote: a 2px `label-caption` rule and a 14px pad,
        // the text keeping the document's own base step and ink
        // (`MarkdownText.module.css` `blockquote`, :148-152).
        return Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: theme.colorScheme.labelCaption, width: 2),
            ),
          ),
          padding: const EdgeInsets.only(left: 14),
          child: Text.rich(
            _inlineSpan(context, block.inlines),
            style: DshType.markdownBase.style(
              color: theme.colorScheme.labelPrimary,
            ),
          ),
        );
      case TableBlock():
        return _tableBlock(context, block);
      case ParagraphBlock():
        return Text.rich(
          _inlineSpan(context, block.inlines),
          style: DshType.markdownBase.style(
            color: theme.colorScheme.labelPrimary,
          ),
        );
    }
  }

  /// One list row: the marker holds a fixed column so a wrapped item hangs
  /// under its own text. A number right-aligns in that column, a bullet
  /// centers in it.
  Widget _listRow(
    BuildContext context, {
    required int depth,
    required String marker,
    required List<MarkdownInline> inlines,
    required bool first,
    bool markerAtEnd = false,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(left: depth * _kNestIndent, top: first ? 0 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _kMarkerColumn,
            child: Text(
              marker,
              textAlign: markerAtEnd ? TextAlign.right : TextAlign.center,
              // The reference's list marker is `label-secondary`
              // (`MarkdownText.module.css` `li::marker`, :125-128).
              style: DshType.markdownBase.style(
                color: theme.colorScheme.labelSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              _inlineSpan(context, inlines),
              style: DshType.markdownBase.style(
                color: theme.colorScheme.labelPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Pipe table: header row plus body rows, equal-weight columns with
  /// horizontal scroll protection on compact screens so cells are not crushed.
  Widget _tableBlock(BuildContext context, TableBlock block) {
    final theme = Theme.of(context);
    final columns = block.header.length > 1 ? block.header.length : 1;
    // The reference's table is not a card: a scroll wrapper and rules only
    // (`MarkdownText.module.css` `.tableScroll`, :183-247). Its header row
    // wears the table-head step over a half-pixel `border-l3`; each body row
    // the table step over `border-l2`, and the first/last cell drop their
    // outer padding.
    final Color ink = theme.colorScheme.labelPrimary;
    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const double minCellWidth = 84.0;
          final double totalMinWidth = columns * minCellWidth;
          final double tableWidth = constraints.maxWidth > totalMinWidth
              ? constraints.maxWidth - 8
              : totalMinWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: theme.colorScheme.borderL3,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < block.header.length; i++)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                i == 0 ? 0 : 16,
                                10,
                                i == block.header.length - 1 ? 0 : 16,
                                10,
                              ),
                              child: Text.rich(
                                _inlineSpan(context, block.header[i]),
                                style: DshType.markdownTableHead.style(
                                  color: ink,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final row in block.rows)
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: theme.colorScheme.borderL2,
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (
                            var columnIndex = 0;
                            columnIndex < columns;
                            columnIndex++
                          )
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  columnIndex == 0 ? 0 : 16,
                                  10,
                                  columnIndex == columns - 1 ? 0 : 16,
                                  10,
                                ),
                                child: Text.rich(
                                  _inlineSpan(
                                    context,
                                    columnIndex < row.length
                                        ? row[columnIndex]
                                        : const <MarkdownInline>[],
                                  ),
                                  style: DshType.markdownTable.style(
                                    color: ink,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _codeBlock(BuildContext context, CodeBlock block) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final scheme = theme.colorScheme;
    // The reference's code block (`markdown/CodeBlock.module.css`): the
    // code-block surface on the radius-lg step, a banner strip carrying the
    // language in the code face over `markdown-code-block-banner` (:36-46),
    // and the body padded 16 (:73-78).
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.markdownCodeBlock,
        borderRadius: BorderRadius.circular(kRadiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            color: scheme.markdownCodeBlockBanner,
            // The strip is as tall as its text: the copy target below overlays
            // it instead of setting its height (the 44px button that used to
            // live in this row is what left the language floating in a void).
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 9, 46, 9),
                  child: Text(
                    // A fence with no language says nothing worth a line of
                    // its own; an unclosed one says the body is still coming.
                    block.open
                        ? l10n.codeStreamingLabel
                        : (block.language ?? ''),
                    style: DshType.markdownCode
                        .style(color: scheme.labelPrimary)
                        .copyWith(
                          fontFamily: kCodeFontFamily,
                          fontFamilyFallback: kCodeFontFamilyFallback,
                          // The pin's step adds no tracking; null would let an
                          // ancestor text theme's letterSpacing leak in.
                          letterSpacing: 0,
                        ),
                  ),
                ),
                // The pin keeps the copy inside the banner strip
                // (`CodeBlock.module.css` `.action`/`.copyButton`, :56-66).
                // Positioned, so its 32px target rides over the strip without
                // making the strip 32px tall.
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 14,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      tooltip: l10n.copyTooltip,
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await Clipboard.setData(
                          ClipboardData(text: block.code),
                        );
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(l10n.copiedTooltip),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(milliseconds: 1400),
                          ),
                        );
                      },
                      icon: Icon(
                        Icons.copy_outlined,
                        color: scheme.labelPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _codeBody(context, block),
          ),
        ],
      ),
    );
  }

  /// The fence body: a horizontally scrolling, token-coloured run in the
  /// pin's code-block step. The reference's fence shows no number gutter in the
  /// chat (`CodeBlock.tsx` `lineNumbers` defaults off, :31-32) — it is the
  /// reader's own copy that carries the line breaks, not the render.
  ///
  /// Highlighting runs only on a closed fence in a language
  /// [codeLanguageIsKnown] accepts. A streaming fence re-lexes on every chunk
  /// and its tail is exactly the text still moving, so it renders plain until
  /// it settles — the same reasoning that freezes all but the last two blocks
  /// ([incremental.dart]).
  Widget _codeBody(BuildContext context, CodeBlock block) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = DshType.markdownCodeBlock
        .style(color: scheme.labelPrimary)
        .copyWith(
          fontFamily: kCodeFontFamily,
          fontFamilyFallback: kCodeFontFamilyFallback,
          // No added tracking, and no inherited tracking: the block's face is
          // the pin's, not a themed label's.
          letterSpacing: 0,
        );
    final highlighted = !block.open && codeLanguageIsKnown(block.language);
    final tokens = highlighted
        ? tokenizeCode(block.code, block.language)
        : <CodeToken>[CodeToken(CodeTokenKind.plain, block.code)];
    final body = highlighted
        ? Text.rich(
            TextSpan(
              children: [
                for (final token in tokens)
                  if (token.text.isNotEmpty)
                    TextSpan(
                      text: token.text,
                      style: _tokenStyle(scheme, token.kind),
                    ),
              ],
            ),
            style: base,
          )
        : Text(block.code, style: base);

    return body;
  }

  /// Paint one token class. `plain` keeps the code body's own ink, so an
  /// unclassified run reads exactly as it did before highlighting.
  static TextStyle? _tokenStyle(ColorScheme scheme, CodeTokenKind kind) =>
      switch (kind) {
        CodeTokenKind.plain => null,
        CodeTokenKind.comment => TextStyle(
          color: scheme.labelTertiary,
          fontStyle: FontStyle.italic,
        ),
        CodeTokenKind.string => TextStyle(color: scheme.syntaxString),
        CodeTokenKind.number => TextStyle(color: scheme.syntaxNumber),
        CodeTokenKind.keyword => TextStyle(
          color: scheme.syntaxKeyword,
          fontWeight: FontWeight.w600,
        ),
      };

  /// Resolve theme styles first, then build spans in a plain builder.
  InlineSpan _inlineSpan(BuildContext context, List<MarkdownInline> inlines) {
    final theme = Theme.of(context);
    // The reference's inline code run: the code face on the inline-code step
    // (`MarkdownText.module.css` `:not(pre) > code`, :155-166), chipped by the
    // `CodeInline` case below.
    final code = DshType.markdownCode
        .style(color: theme.colorScheme.labelPrimary)
        .copyWith(
          fontFamily: kCodeFontFamily,
          fontFamilyFallback: kCodeFontFamilyFallback,
          // The pin's step adds no tracking, and a null here would let the
          // ambient `DefaultTextStyle`'s tracking (our `labelSmall` carries
          // 0.4) leak into every inline run — which is what makes `root:root`
          // and `/data/adb` read as letter-spaced.
          letterSpacing: 0,
        );
    final spans = <InlineSpan>[];
    void render(List<MarkdownInline> runs, List<InlineSpan> out) {
      for (final inline in runs) {
        switch (inline) {
          case TextInline():
            out.add(TextSpan(text: inline.text));
          case CodeInline():
            // The pin chips an inline run: `markdown-inline-code` fill, the
            // half-pixel `border-l1`, `--dsw-radius-sm` and 5px side padding
            // (`MarkdownText.module.css` `:not(pre) > code`, :155-166) on the
            // code step. A `TextSpan` carries no fill, so the run is a
            // placeholder.
            //
            // The 1px vertical padding stands in for what CSS gets for free:
            // an inline background covers the line box, while a `Container`
            // paints exactly its box. With the chip's text at `height: 1` its
            // box, border and padding stay inside the body line's descent, so a
            // paragraph containing a chip keeps the body step's 24px rhythm.
            out.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.markdownInlineCode,
                    border: Border.all(
                      color: theme.colorScheme.borderL1,
                      width: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(kRadiusSm),
                  ),
                  child: Text(inline.code, style: code.copyWith(height: 1)),
                ),
              ),
            );
          case BoldInline():
            final nested = <InlineSpan>[];
            render(inline.inlines, nested);
            out.add(
              TextSpan(
                children: nested,
                // The reference's markdown strong is 600
                // (`MarkdownText.module.css:15-17`).
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            );
          case ItalicInline():
            final nested = <InlineSpan>[];
            render(inline.inlines, nested);
            out.add(
              TextSpan(
                children: nested,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            );
          case LinkInline():
            // Clickable span: the default handler opens the URI through the
            // platform; the styled span covers the label only.
            out.add(
              TextSpan(
                text: inline.label,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: theme.colorScheme.primary,
                ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () => _openLink(context, inline.url),
              ),
            );
        }
      }
    }

    render(inlines, spans);
    return TextSpan(children: spans);
  }

  /// Opens one inline link through the platform.
  ///
  /// A tap that opens nothing must say so: an unparseable URL, a scheme the
  /// device has no handler for, or a launcher that refuses all leave the
  /// reader with a dead span otherwise. The locale seat and the messenger are
  /// captured while this run of spans is built — a `TapGestureRecognizer`
  /// fires long after the build, so nothing may read `context` then.
  void _openLink(BuildContext context, String url) {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    unawaited(() async {
      var opened = false;
      try {
        opened = await launchUrl(Uri.parse(url));
      } catch (_) {
        opened = false;
      }
      if (opened || l10n == null || messenger == null) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.linkOpenFailedNotice)),
      );
    }());
  }
}
