package com.deepseek.harness.android.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.deepseek.harness.android.domain.model.CredentialStatus
import com.deepseek.harness.android.domain.model.SettingsSnapshot
import com.deepseek.harness.android.domain.repository.ChatRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * Read-only settings/credentials overview. The host pins both describe verbs
 * to loopback connections, so a remote source surfaces the transport error
 * instead of a page; nothing here mutates host state.
 */
@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val chatRepository: ChatRepository,
) : ViewModel() {

    private val snapshot = MutableStateFlow<SettingsSnapshot?>(null)
    private val credentials = MutableStateFlow<List<CredentialStatus>>(emptyList())
    private val isLoading = MutableStateFlow(false)
    private val errorMessage = MutableStateFlow<String?>(null)
    private val credentialError = MutableStateFlow<String?>(null)

    val uiState: StateFlow<SettingsUiState> = combine(
        snapshot,
        credentials,
        isLoading,
        errorMessage,
        credentialError,
    ) { described, credentialState, loading, error, credError ->
        SettingsUiState(
            snapshot = described,
            credentials = credentialState,
            isLoading = loading,
            errorMessage = error,
            credentialError = credError,
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(stopTimeoutMillis = 5_000),
        initialValue = SettingsUiState(isLoading = true),
    )

    init {
        refresh()
    }

    fun onAction(action: SettingsAction) {
        when (action) {
            SettingsAction.Refresh -> refresh()
            SettingsAction.DismissError -> errorMessage.value = null
        }
    }

    private fun refresh() {
        viewModelScope.launch {
            isLoading.value = true
            val described = runCatchingForUi { chatRepository.describeSettings() }
            if (described != null) {
                snapshot.value = described
                loadCredentials(described.credentialRefs)
            }
            isLoading.value = false
        }
    }

    private suspend fun loadCredentials(refs: List<String>) {
        credentialError.value = null
        try {
            credentials.value = chatRepository.describeCredentials(refs)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            credentials.value = emptyList()
            credentialError.value = error.message ?: error.javaClass.simpleName
        }
    }

    private suspend fun <T> runCatchingForUi(block: suspend () -> T): T? =
        try {
            errorMessage.value = null
            block()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            errorMessage.value = error.message ?: error.javaClass.simpleName
            null
        }
}
