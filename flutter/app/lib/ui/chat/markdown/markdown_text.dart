/// Renders one message body as markdown blocks. The parser output is plain
/// data; every color, font, and shape decision stays in this layer.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

import 'markdown_parser.dart';

class MarkdownText extends StatelessWidget {
  const MarkdownText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final blocks = MarkdownParser.parse(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final block in blocks) _block(context, block)],
    );
  }

  Widget _block(BuildContext context, MarkdownBlock block) {
    final theme = Theme.of(context);
    switch (block) {
      case CodeBlock():
        return _codeBlock(context, block);
      case HeadingBlock():
        final style = switch (block.level) {
          1 => theme.textTheme.headlineSmall,
          2 => theme.textTheme.titleLarge,
          3 => theme.textTheme.titleMedium,
          _ => theme.textTheme.titleSmall,
        };
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text.rich(_inlineSpan(context, block.inlines), style: style),
        );
      case BulletListBlock():
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in block.items)
              Padding(
                padding: EdgeInsets.only(left: entry.depth * 16.0, bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.depth == 0 ? '•  ' : '–  ',
                      style: theme.textTheme.bodyMedium,
                    ),
                    Expanded(
                      child: Text.rich(
                        _inlineSpan(context, entry.inlines),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      case BlockQuoteBlock():
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3,
              height: 20,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                _inlineSpan(context, block.inlines),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
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

  /// Pipe table: header row plus body rows, equal-weight columns.
  Widget _tableBlock(BuildContext context, TableBlock block) {
    final theme = Theme.of(context);
    final columns = block.header.length > 1 ? block.header.length : 1;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
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
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text.rich(
                      _inlineSpan(context, cell),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ),
            ],
          ),
          for (final row in block.rows)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var columnIndex = 0; columnIndex < columns; columnIndex++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
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
    final label = block.language ?? (block.open ? 'code (streaming)' : 'code');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              block.code,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
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
    final spans = <InlineSpan>[];
    void render(List<MarkdownInline> runs, List<InlineSpan> out) {
      for (final inline in runs) {
        switch (inline) {
          case TextInline():
            out.add(TextSpan(text: inline.text));
          case CodeInline():
            out.add(
              TextSpan(
                text: inline.code,
                style: TextStyle(
                  fontFamily: 'monospace',
                  backgroundColor: theme.colorScheme.surfaceContainerLow,
                ),
              ),
            );
          case BoldInline():
            final nested = <InlineSpan>[];
            render(inline.inlines, nested);
            out.add(
              TextSpan(
                children: nested,
                style: const TextStyle(fontWeight: FontWeight.bold),
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
