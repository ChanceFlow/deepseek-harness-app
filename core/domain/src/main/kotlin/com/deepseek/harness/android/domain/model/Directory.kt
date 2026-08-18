package com.deepseek.harness.android.domain.model

/**
 * Neutral host-directory browser vocabulary. The host returns absolute paths
 * for every entry; the Android client never joins path segments itself.
 */
data class DirectoryEntry(
    val name: String,
    val path: String,
    val hidden: Boolean,
)

data class DirectoryListing(
    val path: String,
    val home: String,
    val crumbs: List<DirectoryEntry>,
    val entries: List<DirectoryEntry>,
    val truncated: Boolean,
)
