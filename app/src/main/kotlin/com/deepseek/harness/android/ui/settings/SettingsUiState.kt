package com.deepseek.harness.android.ui.settings

import androidx.compose.runtime.Immutable
import com.deepseek.harness.android.domain.model.CredentialStatus
import com.deepseek.harness.android.domain.model.SettingsSnapshot

@Immutable
data class SettingsUiState(
    val snapshot: SettingsSnapshot? = null,
    val credentials: List<CredentialStatus> = emptyList(),
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    /** Credential describe is enrichment: its failure never blanks the page. */
    val credentialError: String? = null,
)

sealed interface SettingsAction {
    data object Refresh : SettingsAction
    data object DismissError : SettingsAction
}
