package com.deepseek.harness.android.ui.chat

import com.deepseek.harness.android.domain.model.ChatMessage
import com.deepseek.harness.android.domain.model.MessageRole
import com.deepseek.harness.android.domain.model.TimelineItem
import org.junit.Assert.assertEquals
import org.junit.Test

class TimelineGroupingTest {

    private fun message(id: String): TimelineItem.Message =
        TimelineItem.Message(
            ChatMessage(id = id, sessionId = "s1", role = MessageRole.USER, text = id),
        )

    @Test
    fun `items before the first boundary form the null group`() {
        val groups = groupTimelineByTurn(listOf(message("a"), message("b")))

        assertEquals(1, groups.size)
        assertEquals(null, groups.single().turn)
        assertEquals(listOf("a", "b"), groups.single().items.map { (it as TimelineItem.Message).value.id })
    }

    @Test
    fun `boundaries split groups and land only in the heading`() {
        val groups = groupTimelineByTurn(
            listOf(
                TimelineItem.TurnBoundary(1L),
                message("a"),
                TimelineItem.TurnBoundary(2L),
                message("b"),
                message("c"),
            ),
        )

        assertEquals(3, groups.size)
        assertEquals(null, groups[0].turn)
        assertEquals(0, groups[0].items.size)
        assertEquals(1L, groups[1].turn)
        assertEquals(listOf("a"), groups[1].items.map { (it as TimelineItem.Message).value.id })
        assertEquals(2L, groups[2].turn)
        assertEquals(listOf("b", "c"), groups[2].items.map { (it as TimelineItem.Message).value.id })
    }

    @Test
    fun `a boundary without rows keeps its group for the outline number`() {
        val groups = groupTimelineByTurn(
            listOf(
                TimelineItem.TurnBoundary(1L),
                message("a"),
                TimelineItem.TurnBoundary(2L),
            ),
        )

        assertEquals(3, groups.size)
        assertEquals(2L, groups[2].turn)
        assertEquals(0, groups[2].items.size)
    }
}
