package com.deepseek.harness.android.domain.model

data class ModelSelection(
    val provider: String,
    val model: String,
    val reasoningEffort: String? = null,
)

data class ModelReasoningEffort(
    val id: String,
    val name: String,
    val description: String? = null,
)

data class ModelReasoning(
    val efforts: List<ModelReasoningEffort> = emptyList(),
    val defaultEffort: String? = null,
)

data class ModelCatalogModel(
    val id: String,
    val name: String,
    val description: String? = null,
    val reasoning: ModelReasoning? = null,
)

data class ModelProviderGroup(
    val id: String,
    val name: String,
    val models: List<ModelCatalogModel> = emptyList(),
)

data class ModelCatalogFailure(
    val id: String,
    val name: String,
    val message: String,
)

data class SessionModels(
    val current: ModelSelection,
    val routable: Boolean,
    val groups: List<ModelProviderGroup> = emptyList(),
    val failures: List<ModelCatalogFailure> = emptyList(),
)
