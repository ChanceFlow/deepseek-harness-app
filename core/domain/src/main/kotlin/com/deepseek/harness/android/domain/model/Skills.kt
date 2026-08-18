package com.deepseek.harness.android.domain.model

/**
 * One user-invocable skill from the session's catalog (`skill.list`).
 * Picking a candidate lands the literal `/name ` text in the composer,
 * mirroring the Web client's plain-text-reference decision.
 */
data class SkillEntry(
    val name: String,
    val description: String,
    val whenToUse: String? = null,
    val modelInvocable: Boolean = false,
)
