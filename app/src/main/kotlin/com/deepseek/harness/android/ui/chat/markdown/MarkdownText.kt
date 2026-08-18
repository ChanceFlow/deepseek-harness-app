package com.deepseek.harness.android.ui.chat.markdown

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.deepseek.harness.android.ui.theme.DeepSeekHarnessAndroidTheme

/**
 * Renders one message body as markdown blocks. The parser output is plain
 * data; every color, font, and shape decision stays in this layer.
 */
@Composable
fun MarkdownText(
    text: String,
    modifier: Modifier = Modifier,
) {
    val blocks = remember(text) { MarkdownParser.parse(text) }
    Column(modifier = modifier.fillMaxWidth()) {
        blocks.forEach { block ->
            when (block) {
                is MarkdownBlock.Code -> CodeBlock(block)
                is MarkdownBlock.Heading -> Text(
                    text = inlineAnnotated(block.inlines),
                    style = when (block.level) {
                        1 -> MaterialTheme.typography.headlineSmall
                        2 -> MaterialTheme.typography.titleLarge
                        3 -> MaterialTheme.typography.titleMedium
                        else -> MaterialTheme.typography.titleSmall
                    },
                    modifier = Modifier.padding(vertical = 2.dp),
                )

                is MarkdownBlock.BulletList -> Column {
                    block.items.forEach { entry ->
                        Row(modifier = Modifier.padding(start = (entry.depth * 16).dp)) {
                            Text(
                                text = if (entry.depth == 0) "•  " else "–  ",
                                style = MaterialTheme.typography.bodyMedium,
                            )
                            Text(
                                text = inlineAnnotated(entry.inlines),
                                style = MaterialTheme.typography.bodyMedium,
                                modifier = Modifier.padding(bottom = 2.dp),
                            )
                        }
                    }
                }

                is MarkdownBlock.BlockQuote -> Row {
                    Box(
                        modifier = Modifier
                            .width(3.dp)
                            .height(20.dp)
                            .clip(RoundedCornerShape(2.dp))
                            .background(MaterialTheme.colorScheme.outlineVariant),
                    )
                    Text(
                        text = inlineAnnotated(block.inlines),
                        style = MaterialTheme.typography.bodyMedium.copy(
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        ),
                        modifier = Modifier.padding(start = 8.dp),
                    )
                }

                is MarkdownBlock.Table -> TableBlock(block)

                is MarkdownBlock.Paragraph -> Text(
                    text = inlineAnnotated(block.inlines),
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }
    }
}

/** Pipe table: header row plus body rows, equal-weight columns. */
@Composable
private fun TableBlock(block: MarkdownBlock.Table) {
    val columns = block.header.size.coerceAtLeast(1)
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = RoundedCornerShape(6.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
    ) {
        Column(modifier = Modifier.padding(6.dp)) {
            Row(modifier = Modifier.fillMaxWidth()) {
                block.header.forEach { cell ->
                    Text(
                        text = inlineAnnotated(cell),
                        style = MaterialTheme.typography.titleSmall,
                        modifier = Modifier
                            .weight(1f)
                            .padding(horizontal = 4.dp, vertical = 2.dp),
                    )
                }
            }
            block.rows.forEach { row ->
                Row(modifier = Modifier.fillMaxWidth()) {
                    repeat(columns) { columnIndex ->
                        val cell = row.getOrNull(columnIndex).orEmpty()
                        Text(
                            text = inlineAnnotated(cell),
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier
                                .weight(1f)
                                .padding(horizontal = 4.dp, vertical = 2.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CodeBlock(block: MarkdownBlock.Code) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = RoundedCornerShape(6.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
    ) {
        Column(modifier = Modifier.padding(8.dp)) {
            val label = block.language ?: if (block.open) "code (streaming)" else "code"
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = block.code,
                style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
            )
        }
    }
}

/** Resolve theme styles first, then build spans in a plain builder. */
@Composable
private fun inlineAnnotated(inlines: List<MarkdownInline>): AnnotatedString {
    val codeStyle = SpanStyle(
        fontFamily = FontFamily.Monospace,
        background = MaterialTheme.colorScheme.surfaceVariant,
    )
    val boldStyle = SpanStyle(fontWeight = FontWeight.Bold)
    val italicStyle = SpanStyle(fontStyle = FontStyle.Italic)
    val linkStyle = SpanStyle(
        color = MaterialTheme.colorScheme.primary,
        textDecoration = TextDecoration.Underline,
    )
    return buildAnnotatedString {
        renderInlines(inlines, codeStyle, boldStyle, italicStyle, linkStyle)
    }
}

private fun AnnotatedString.Builder.renderInlines(
    inlines: List<MarkdownInline>,
    codeStyle: SpanStyle,
    boldStyle: SpanStyle,
    italicStyle: SpanStyle,
    linkStyle: SpanStyle,
) {
    inlines.forEach { inline ->
        when (inline) {
            is MarkdownInline.Text -> append(inline.text)
            is MarkdownInline.Code -> withStyle(codeStyle) { append(inline.code) }
            is MarkdownInline.Bold -> withStyle(boldStyle) {
                renderInlines(inline.inlines, codeStyle, boldStyle, italicStyle, linkStyle)
            }

            is MarkdownInline.Italic -> withStyle(italicStyle) {
                renderInlines(inline.inlines, codeStyle, boldStyle, italicStyle, linkStyle)
            }

            is MarkdownInline.Link -> {
                // Clickable span: the default handler opens the URI through
                // the platform; the styled span covers the label only.
                val start = length
                append(inline.label)
                addLink(
                    LinkAnnotation.Url(
                        inline.url,
                        TextLinkStyles(style = linkStyle),
                    ),
                    start,
                    length,
                )
            }
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun MarkdownTextPreview() {
    DeepSeekHarnessAndroidTheme {
        MarkdownText(
            text = """
                ## Release notes
                The **agent** now supports `host.listDirectory` and *streaming* fences.

                - bullet with **bold**
                - bullet with [docs](https://example.com/docs)

                ```kotlin
                val listing = repository.listDirectory(null)
                ```
            """.trimIndent(),
        )
    }
}
