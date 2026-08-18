package com.deepseek.harness.android.ui.chat

import com.deepseek.harness.android.domain.model.MessageRole
import com.deepseek.harness.android.domain.model.TimelineItem

/**
 * One trajectory-outline segment: everything after a turn boundary until the
 * next one. A null turn holds the rows before the first `turn/start`.
 */
internal data class TimelineTurnGroup(
    val turn: Long?,
    val items: List<TimelineItem>,
)

/**
 * Partition a timeline into ledger-style turn groups. Boundary markers land
 * in their own group's heading (not its rows); boundaries with no rows still
 * produce a group so the outline keeps the turn number.
 */
internal fun groupTimelineByTurn(items: List<TimelineItem>): List<TimelineTurnGroup> {
    val groups = mutableListOf<TimelineTurnGroup>()
    var currentTurn: Long? = null
    var current = mutableListOf<TimelineItem>()

    fun flush() {
        groups += TimelineTurnGroup(turn = currentTurn, items = current)
        current = mutableListOf()
    }

    items.forEach { item ->
        if (item is TimelineItem.TurnBoundary) {
            flush()
            currentTurn = item.turn
        } else {
            current += item
        }
    }
    flush()
    return groups
}

/**
 * Request-header preview: the first user message of a group, folded to one
 * line and truncated — the trajectory outline's prompt echo.
 */
internal fun promptPreview(items: List<TimelineItem>, maxChars: Int = 60): String? {
    val text = items
        .filterIsInstance<TimelineItem.Message>()
        .firstOrNull { it.value.role == MessageRole.USER }
        ?.value
        ?.text
        ?.lineSequence()
        ?.firstOrNull { it.isNotBlank() }
        ?.trim()
        ?: return null
    return if (text.length <= maxChars) text else text.take(maxChars - 1).trimEnd() + "…"
}
