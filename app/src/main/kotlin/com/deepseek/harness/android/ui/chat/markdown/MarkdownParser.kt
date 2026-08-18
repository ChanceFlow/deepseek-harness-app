package com.deepseek.harness.android.ui.chat.markdown

/**
 * Minimal markdown vocabulary for assistant/user message bodies.
 *
 * Scope mirrors the Android MVP slice: fenced code blocks, headings,
 * bullet lists, and paragraphs with inline code, bold, italic, and links.
 * The parser is pure Kotlin so plain JVM tests pin its behavior; the
 * Compose layer owns every style decision.
 */
sealed interface MarkdownBlock {
    data class Code(
        val language: String?,
        val code: String,
        /** True while a streaming body has not closed the fence yet. */
        val open: Boolean = false,
    ) : MarkdownBlock

    data class Heading(
        val level: Int,
        val inlines: List<MarkdownInline>,
    ) : MarkdownBlock

    data class BulletList(
        val items: List<List<MarkdownInline>>,
    ) : MarkdownBlock

    /** GFM pipe table; column count follows the header, short rows pad empty. */
    data class Table(
        val header: List<List<MarkdownInline>>,
        val rows: List<List<List<MarkdownInline>>>,
    ) : MarkdownBlock

    data class Paragraph(
        val inlines: List<MarkdownInline>,
    ) : MarkdownBlock
}

sealed interface MarkdownInline {
    data class Text(val text: String) : MarkdownInline

    data class Code(val code: String) : MarkdownInline

    data class Bold(val inlines: List<MarkdownInline>) : MarkdownInline

    data class Italic(val inlines: List<MarkdownInline>) : MarkdownInline

    data class Link(val label: String, val url: String) : MarkdownInline
}

object MarkdownParser {

    private val fence = Regex("^(`{3,})\\s*([A-Za-z0-9_+-]*)\\s*$")
    private val bullet = Regex("^[*-] (\\S.*)$")
    private val heading = Regex("^(#{1,6}) (.*)$")
    private val delimiterCell = Regex("^:?-+:?$")

    /** Parse one message body into ordered blocks. */
    fun parse(text: String): List<MarkdownBlock> {
        val blocks = mutableListOf<MarkdownBlock>()
        val lines = text.lines()
        var index = 0

        var paragraph = mutableListOf<String>()
        var bullets = mutableListOf<MutableList<MarkdownInline>>()

        fun flushParagraph() {
            if (paragraph.isNotEmpty()) {
                blocks += MarkdownBlock.Paragraph(parseInlines(paragraph.joinToString("\n")))
                paragraph = mutableListOf()
            }
        }

        fun flushBullets() {
            if (bullets.isNotEmpty()) {
                blocks += MarkdownBlock.BulletList(bullets.map { it.toList() })
                bullets = mutableListOf()
            }
        }

        while (index < lines.size) {
            val line = lines[index]
            val fenceMatch = fence.matchEntire(line)
            if (fenceMatch != null) {
                flushParagraph()
                flushBullets()
                val marker = fenceMatch.groupValues[1]
                val language = fenceMatch.groupValues[2].ifEmpty { null }
                val code = StringBuilder()
                var closed = false
                index++
                while (index < lines.size) {
                    val candidate = lines[index]
                    if (candidate.trimEnd().startsWith(marker) && candidate.trim() == marker) {
                        closed = true
                        index++
                        break
                    }
                    if (code.isNotEmpty()) code.append('\n')
                    code.append(candidate)
                    index++
                }
                blocks += MarkdownBlock.Code(
                    language = language,
                    code = code.toString(),
                    open = !closed,
                )
                continue
            }

            if (line.isBlank()) {
                flushParagraph()
                flushBullets()
                index++
                continue
            }

            if (isTableStart(lines, index)) {
                flushParagraph()
                flushBullets()
                val header = splitTableRow(line)
                index += 2
                val rows = mutableListOf<List<List<MarkdownInline>>>()
                while (index < lines.size && lines[index].contains('|') && lines[index].isNotBlank()) {
                    rows += splitTableRow(lines[index])
                    index++
                }
                blocks += MarkdownBlock.Table(header = header, rows = rows)
                continue
            }

            val headingMatch = heading.matchEntire(line)
            if (headingMatch != null) {
                flushParagraph()
                flushBullets()
                blocks += MarkdownBlock.Heading(
                    level = headingMatch.groupValues[1].length,
                    inlines = parseInlines(headingMatch.groupValues[2]),
                )
                index++
                continue
            }

            val bulletMatch = bullet.matchEntire(line)
            if (bulletMatch != null) {
                flushParagraph()
                bullets += parseInlines(bulletMatch.groupValues[1]).toMutableList()
                index++
                continue
            }

            flushBullets()
            paragraph += line.trimEnd()
            index++
        }
        flushParagraph()
        flushBullets()
        return blocks
    }

    /** Parse inline emphasis/code/link runs inside one paragraph line group. */
    internal fun parseInlines(text: String): List<MarkdownInline> {
        val inlines = mutableListOf<MarkdownInline>()
        val plain = StringBuilder()
        var index = 0

        fun flushPlain() {
            if (plain.isNotEmpty()) {
                inlines += MarkdownInline.Text(plain.toString())
                plain.clear()
            }
        }

        while (index < text.length) {
            val char = text[index]
            when {
                char == '`' && text.indexOf('`', index + 1) != -1 -> {
                    val end = text.indexOf('`', index + 1)
                    flushPlain()
                    inlines += MarkdownInline.Code(text.substring(index + 1, end))
                    index = end + 1
                }

                char == '*' && text.startsWith("**", index) -> {
                    val end = text.indexOf("**", index + 2)
                    if (end != -1 && end > index + 2) {
                        flushPlain()
                        inlines += MarkdownInline.Bold(parseInlines(text.substring(index + 2, end)))
                        index = end + 2
                    } else {
                        plain.append(char)
                        index++
                    }
                }

                char == '*' && index + 1 < text.length && !text[index + 1].isWhitespace() -> {
                    val close = findSingleEmphasisClose(text, index + 1)
                    if (close != -1) {
                        flushPlain()
                        inlines += MarkdownInline.Italic(parseInlines(text.substring(index + 1, close)))
                        index = close + 1
                    } else {
                        plain.append(char)
                        index++
                    }
                }

                char == '[' -> {
                    val labelEnd = text.indexOf("](", index + 1)
                    if (labelEnd != -1) {
                        val urlEnd = text.indexOf(')', labelEnd + 2)
                        if (urlEnd != -1) {
                            flushPlain()
                            inlines += MarkdownInline.Link(
                                label = text.substring(index + 1, labelEnd),
                                url = text.substring(labelEnd + 2, urlEnd),
                            )
                            index = urlEnd + 1
                            continue
                        }
                    }
                    plain.append(char)
                    index++
                }

                else -> {
                    plain.append(char)
                    index++
                }
            }
        }
        flushPlain()
        return inlines
    }

    /** Closing single `*` that is not the start of a `**` pair. */
    private fun findSingleEmphasisClose(text: String, from: Int): Int {
        var index = from
        while (index < text.length) {
            if (text[index] == '*') {
                if (text.startsWith("**", index)) {
                    index += 2
                    continue
                }
                if (!text[index - 1].isWhitespace()) return index
            }
            index++
        }
        return -1
    }

    /** A pipe row starts a table only when the next line is a delimiter row. */
    private fun isTableStart(lines: List<String>, index: Int): Boolean {
        val line = lines[index]
        if (!line.contains('|')) return false
        val next = lines.getOrNull(index + 1) ?: return false
        val cells = splitTableRow(next)
        return cells.isNotEmpty() && cells.all { delimiterCell.matches(it.text().ifEmpty { "-" }) }
    }

    /** Split one pipe row into inline cells; outer pipes optional. */
    private fun splitTableRow(line: String): List<List<MarkdownInline>> {
        val trimmed = line.trim().removePrefix("|").removeSuffix("|")
        return trimmed.split('|').map { cell -> parseInlines(cell.trim()) }
    }

    /** Plain text of one parsed cell, for delimiter-row matching. */
    private fun List<MarkdownInline>.text(): String =
        joinToString(separator = "") { inline ->
            when (inline) {
                is MarkdownInline.Text -> inline.text
                is MarkdownInline.Code -> inline.code
                is MarkdownInline.Bold, is MarkdownInline.Italic,
                is MarkdownInline.Link,
                -> ""
            }
        }
}
