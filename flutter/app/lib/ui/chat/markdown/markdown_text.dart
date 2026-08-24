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

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/theme.dart';
import 'incremental.dart';
import 'markdown_parser.dart';

/// Column the list marker occupies; wrapped text aligns to its right edge.
const double _kMarkerColumn = 22;

/// Indent one nesting level adds.
const double _kNestIndent = 16;

class MarkdownText extends StatefulWidget {
  const MarkdownText({super.key, required this.text});

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
          rendered != null &&
              (identical(rendered, block) || rendered == block)
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
            if (i > 0) SizedBox(height: _gapBetween(_blocks[i - 1], _blocks[i])),
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
        // inverts the hierarchy it is there to state.
        final style = switch (block.level) {
          1 => theme.textTheme.titleMedium?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
          2 => theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          _ => theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
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
        return Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: theme.colorScheme.outlineVariant,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.only(left: 12),
          child: Text.rich(
            _inlineSpan(context, block.inlines),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      case TableBlock():
        return _tableBlock(context, block);
      case ParagraphBlock():
        return Text.rich(
          _inlineSpan(context, block.inlines),
          style: theme.textTheme.bodyMedium,
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
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              _inlineSpan(context, inlines),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  /// Pipe table: header row plus body rows, equal-weight columns.
  Widget _tableBlock(BuildContext context, TableBlock block) {
    final theme = Theme.of(context);
    final columns = block.header.length > 1 ? block.header.length : 1;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(kShapeCard),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final cell in block.header)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: Text.rich(
                      _inlineSpan(context, cell),
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                ),
            ],
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            color: theme.colorScheme.outlineVariant,
          ),
          for (final row in block.rows)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var columnIndex = 0; columnIndex < columns; columnIndex++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      child: Text.rich(
                        _inlineSpan(
                          context,
                          columnIndex < row.length
                              ? row[columnIndex]
                              : const <MarkdownInline>[],
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _codeBlock(BuildContext context, CodeBlock block) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(kShapeCard),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  // A fence with no language says nothing worth a line of
                  // its own; an unclosed one says the body is still coming.
                  block.open ? l10n.codeStreamingLabel : (block.language ?? ''),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                tooltip: l10n.copyTooltip,
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(ClipboardData(text: block.code));
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(l10n.copiedTooltip),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(milliseconds: 1400),
                    ),
                  );
                },
                icon: Icon(Icons.copy_outlined, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              block.code,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.45,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Resolve theme styles first, then build spans in a plain builder.
  InlineSpan _inlineSpan(BuildContext context, List<MarkdownInline> inlines) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium;
    // Monospace runs wider and taller than the prose face at the same
    // nominal size, so the code run steps down to match its x-height. The
    // face is the whole signal: a tint behind a span paints a full-height
    // band with no padding, which on a wrapped path reads as a highlighter
    // stroke across the paragraph.
    final code = TextStyle(
      fontFamily: 'monospace',
      fontSize: (body?.fontSize ?? 15) * 0.92,
      color: theme.colorScheme.onSurface,
    );
    final spans = <InlineSpan>[];
    void render(List<MarkdownInline> runs, List<InlineSpan> out) {
      for (final inline in runs) {
        switch (inline) {
          case TextInline():
            out.add(TextSpan(text: inline.text));
          case CodeInline():
            out.add(TextSpan(text: inline.code, style: code));
          case BoldInline():
            final nested = <InlineSpan>[];
            render(inline.inlines, nested);
            out.add(
              TextSpan(
                children: nested,
                style: const TextStyle(fontWeight: FontWeight.w700),
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
                  ..onTap = () {
                    launchUrl(Uri.parse(inline.url));
                  },
              ),
            );
        }
      }
    }

    render(inlines, spans);
    return TextSpan(children: spans);
  }
}
