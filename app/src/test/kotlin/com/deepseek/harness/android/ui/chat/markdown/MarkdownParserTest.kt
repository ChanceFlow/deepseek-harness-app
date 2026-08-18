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
            listOf(
                MarkdownInline.Text("first "),
                MarkdownInline.Bold(listOf(MarkdownInline.Text("bold"))),
                MarkdownInline.Text(" item"),
            ),
            list.items[0],
        )
        assertEquals(
            listOf(MarkdownInline.Text("second item")),
            list.items[1],
        )
        assertEquals(
            listOf(MarkdownInline.Text("plain")),
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
}
