package com.deepseek.harness.android.ui.chat.markdown

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MarkdownParserTest {

    @Test
    fun `plain paragraph stays one block`() {
        val blocks = MarkdownParser.parse("just plain text")

        val paragraph = blocks.single() as MarkdownBlock.Paragraph
        assertEquals(listOf(MarkdownInline.Text("just plain text")), paragraph.inlines)
    }

    @Test
    fun `blank lines split paragraphs`() {
        val blocks = MarkdownParser.parse("first\n\nsecond")

        assertEquals(2, blocks.size)
        assertEquals(
            listOf(MarkdownInline.Text("first")),
            (blocks[0] as MarkdownBlock.Paragraph).inlines,
        )
        assertEquals(
            listOf(MarkdownInline.Text("second")),
            (blocks[1] as MarkdownBlock.Paragraph).inlines,
        )
    }

    @Test
    fun `fenced code block keeps language and body`() {
        val blocks = MarkdownParser.parse("before\n\n```kotlin\nval a = 1\nval b = 2\n```\nafter")

        assertEquals(3, blocks.size)
        val code = blocks[1] as MarkdownBlock.Code
        assertEquals("kotlin", code.language)
        assertEquals("val a = 1\nval b = 2", code.code)
        assertEquals(false, code.open)
        assertEquals(
            listOf(MarkdownInline.Text("before")),
            (blocks[0] as MarkdownBlock.Paragraph).inlines,
        )
        assertEquals(
            listOf(MarkdownInline.Text("after")),
            (blocks[2] as MarkdownBlock.Paragraph).inlines,
        )
    }

    @Test
    fun `unterminated fence renders open code block`() {
        val blocks = MarkdownParser.parse("```python\nprint(1)")

        val code = blocks.single() as MarkdownBlock.Code
        assertEquals("python", code.language)
        assertEquals("print(1)", code.code)
        assertTrue(code.open)
    }

    @Test
    fun `inline code bold italic and link parse`() {
        val inlines = MarkdownParser.parseInlines(
            "run `gradlew test` with **full** *power* then see [docs](https://example.com)",
        )

        assertEquals(
            listOf(
                MarkdownInline.Text("run "),
                MarkdownInline.Code("gradlew test"),
                MarkdownInline.Text(" with "),
                MarkdownInline.Bold(listOf(MarkdownInline.Text("full"))),
                MarkdownInline.Text(" "),
                MarkdownInline.Italic(listOf(MarkdownInline.Text("power"))),
                MarkdownInline.Text(" then see "),
                MarkdownInline.Link("docs", "https://example.com"),
            ),
            inlines,
        )
    }

    @Test
    fun `unmatched markers degrade to plain text`() {
        val inlines = MarkdownParser.parseInlines("a * b ** c ` d")

        assertEquals(listOf(MarkdownInline.Text("a * b ** c ` d")), inlines)
    }

    @Test
    fun `headings parse level and inline runs`() {
        val blocks = MarkdownParser.parse("## Title with `code`")

        val heading = blocks.single() as MarkdownBlock.Heading
        assertEquals(2, heading.level)
        assertEquals(
            listOf(MarkdownInline.Text("Title with "), MarkdownInline.Code("code")),
            heading.inlines,
        )
    }

    @Test
    fun `consecutive bullets group into one list and inline emphasis holds`() {
        val blocks = MarkdownParser.parse("- first **bold** item\n- second item\n\nplain")

        val list = blocks[0] as MarkdownBlock.BulletList
        assertEquals(2, list.items.size)
        assertEquals(
            MarkdownBlock.BulletEntry(
                inlines = listOf(
                    MarkdownInline.Text("first "),
                    MarkdownInline.Bold(listOf(MarkdownInline.Text("bold"))),
                    MarkdownInline.Text(" item"),
                ),
                depth = 0,
            ),
            list.items[0],
        )
        assertEquals(
            MarkdownBlock.BulletEntry(
                inlines = listOf(MarkdownInline.Text("second item")),
                depth = 0,
            ),
            list.items[1],
        )
        assertEquals(
            listOf(MarkdownInline.Text("plain")),
            (blocks[1] as MarkdownBlock.Paragraph).inlines,
        )
    }

    @Test
    fun `indented bullets nest up to two levels`() {
        val blocks = MarkdownParser.parse("- top\n  - nested\n    - deeper flattens\n      - beyond flattens")

        val list = blocks.single() as MarkdownBlock.BulletList
        assertEquals(listOf(0, 1, 2, 2), list.items.map { it.depth })
        assertEquals("beyond flattens", (list.items[3].inlines.single() as MarkdownInline.Text).text)
    }

    @Test
    fun `quote lines fold into one block quote`() {
        val blocks = MarkdownParser.parse("> quoted **strong**\n> second line\n\nafter")

        val quote = blocks[0] as MarkdownBlock.BlockQuote
        assertEquals(
            listOf(
                MarkdownInline.Text("quoted "),
                MarkdownInline.Bold(listOf(MarkdownInline.Text("strong"))),
                MarkdownInline.Text("\nsecond line"),
            ),
            quote.inlines,
        )
        assertEquals(
            listOf(MarkdownInline.Text("after")),
            (blocks[1] as MarkdownBlock.Paragraph).inlines,
        )
    }

    @Test
    fun `nested bold keeps inner code span`() {
        val inlines = MarkdownParser.parseInlines("**outer `inner` outer**")

        assertEquals(
            listOf(
                MarkdownInline.Bold(
                    listOf(
                        MarkdownInline.Text("outer "),
                        MarkdownInline.Code("inner"),
                        MarkdownInline.Text(" outer"),
                    ),
                ),
            ),
            inlines,
        )
    }

    @Test
    fun `bullet lines inside paragraphs are not emphasized`() {
        val inlines = MarkdownParser.parseInlines("2 * 3 = 6 and a_b_c stay")

        assertEquals(listOf(MarkdownInline.Text("2 * 3 = 6 and a_b_c stay")), inlines)
    }

    @Test
    fun `pipe table parses header and body rows with inline runs`() {
        val blocks = MarkdownParser.parse(
            "intro\n\n| Name | Notes |\n| --- | --- |\n| `code` | **bold** |\n| plain | b |\n\nafter",
        )

        assertEquals(3, blocks.size)
        val table = blocks[1] as MarkdownBlock.Table
        assertEquals(
            listOf(
                listOf(MarkdownInline.Text("Name")),
                listOf(MarkdownInline.Text("Notes")),
            ),
            table.header,
        )
        assertEquals(2, table.rows.size)
        assertEquals(
            listOf(MarkdownInline.Code("code")),
            table.rows[0][0],
        )
        assertEquals(
            listOf(MarkdownInline.Bold(listOf(MarkdownInline.Text("bold")))),
            table.rows[0][1],
        )
        assertEquals(
            listOf(MarkdownInline.Text("plain")),
            table.rows[1][0],
        )
        assertEquals(
            listOf(MarkdownInline.Text("after")),
            (blocks[2] as MarkdownBlock.Paragraph).inlines,
        )
    }

    @Test
    fun `pipe row without delimiter line stays a paragraph`() {
        val blocks = MarkdownParser.parse("a | b\nc | d")

        val paragraph = blocks.single() as MarkdownBlock.Paragraph
        assertEquals("a | b\nc | d", (paragraph.inlines.single() as MarkdownInline.Text).text)
    }

    @Test
    fun `short table rows render with missing cells`() {
        val blocks = MarkdownParser.parse("| a | b |\n| --- | --- |\n| only-one")

        val table = blocks.single() as MarkdownBlock.Table
        assertEquals(1, table.rows.size)
        assertEquals(1, table.rows.single().size)
        assertEquals(listOf(MarkdownInline.Text("only-one")), table.rows.single().single())
    }
}
