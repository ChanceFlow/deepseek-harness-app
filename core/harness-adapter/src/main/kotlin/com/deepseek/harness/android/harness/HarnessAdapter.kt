package com.deepseek.harness.android.harness

import com.deepseek.harness.android.domain.model.SessionSummary
import com.deepseek.harness.android.domain.model.TimelineItem
import kotlinx.coroutines.flow.Flow

/**
 * Anti-corruption layer between dsh and the Android domain model.
 *
 * This is the ONLY module allowed to know about dsh endpoints,
 * dsh event names, and dsh response shapes. It publishes neutral
 * domain model objects such as [SessionSummary] and [TimelineItem]
 * to the rest of the app.
 */
interface HarnessAdapter {
    suspend fun listSessions(): List<SessionSummary>

    fun observeTimeline(sessionId: String): Flow<TimelineItem>
}
