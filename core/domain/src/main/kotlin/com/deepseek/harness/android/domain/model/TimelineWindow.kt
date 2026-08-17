package com.deepseek.harness.android.domain.model

/**
 * Neutral paginated timeline window consumed by the chat screen.
 *
 * `:app` never learns how pages are fetched; it only renders this window and
 * emits an action when the user asks for older history.
 */
data class TimelineWindow(
    val items: List<TimelineItem> = emptyList(),
    val hasMoreOlder: Boolean = false,
    val isLoadingOlder: Boolean = false,
)