package com.deepseek.harness.android.domain.model

data class GoalRef(
    val id: String,
    val revision: Long,
)

enum class GoalPhase {
    ACTIVE,
    PAUSED,
    BLOCKED,
    COMPLETE,
}

data class GoalSnapshot(
    val id: String,
    val revision: Long,
    val objective: String,
    val phase: GoalPhase,
    val blockedReason: String? = null,
    val maxGoalRounds: Long,
)

data class GoalProjection(
    val goal: GoalSnapshot,
    val roundsStarted: Long,
    val createdAt: Long,
    val updatedAt: Long,
)
