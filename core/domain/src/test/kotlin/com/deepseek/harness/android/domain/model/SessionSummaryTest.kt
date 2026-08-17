package com.deepseek.harness.android.domain.model

import org.junit.Assert.assertEquals
import org.junit.Test

class SessionSummaryTest {

    @Test
    fun `display title uses durable title first`() {
        val session = SessionSummary(
            id = "session-1",
            title = "Triage issue",
            cwd = "/home/user/work",
        )

        assertEquals("Triage issue", session.displayTitle)
    }

    @Test
    fun `display title falls back to workspace basename then id`() {
        val byPath = SessionSummary(
            id = "session-1",
            cwd = "/home/user/checkout",
        )
        val withTrailingSeparator = SessionSummary(
            id = "session-2",
            cwd = "C:\\work\\checkout\\",
        )
        val withoutAncestors = SessionSummary(
            id = "session-3",
        )

        assertEquals("checkout", byPath.displayTitle)
        assertEquals("checkout", withTrailingSeparator.displayTitle)
        assertEquals("session-3", withoutAncestors.displayTitle)
    }
}
