package com.deepseek.harness.android.domain.model

/**
 * Plan collaboration state mirrored from the `plan` session projection.
 * `active` is the last logged `plan/mode`; `pending` is true while a logged
 * `/plan` selection has not been recorded yet. The key's absence means the
 * plan capability is not composed on the host.
 */
data class PlanState(
    val active: Boolean,
    val pending: Boolean,
)
