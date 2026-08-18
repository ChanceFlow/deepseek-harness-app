package com.deepseek.harness.android.ui.chat

import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.deepseek.harness.android.domain.model.AttachmentRef
import com.deepseek.harness.android.domain.model.ChatMessage
import com.deepseek.harness.android.domain.model.ConnectionPhase
import com.deepseek.harness.android.domain.model.ConnectionState
import com.deepseek.harness.android.domain.model.HostDescription
import com.deepseek.harness.android.domain.model.ImageLimits
import com.deepseek.harness.android.domain.model.JobStatus
import com.deepseek.harness.android.domain.model.JobView
import com.deepseek.harness.android.domain.model.MessageRole
import com.deepseek.harness.android.domain.model.PendingImage
import com.deepseek.harness.android.domain.model.PlanState
import com.deepseek.harness.android.domain.model.PromptMode
import com.deepseek.harness.android.domain.model.QuestionAnswer
import com.deepseek.harness.android.domain.model.QueuePlacement
import com.deepseek.harness.android.domain.model.QueueUpdateKind
import com.deepseek.harness.android.domain.model.SessionQueueItem
import com.deepseek.harness.android.domain.model.QuestionItem
import com.deepseek.harness.android.domain.model.SessionSearchResult
import com.deepseek.harness.android.domain.model.SessionSummary
import com.deepseek.harness.android.domain.model.SkillEntry
import com.deepseek.harness.android.domain.model.TimelineItem
import com.deepseek.harness.android.domain.model.ToolRunStatus
import com.deepseek.harness.android.domain.model.WorkspaceSummary
import com.deepseek.harness.android.ui.theme.DeepSeekHarnessAndroidTheme
import com.deepseek.harness.android.ui.chat.markdown.MarkdownText
import java.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Decodes one durable attachment lazily; returns null on any failure. */
typealias AttachmentLoader = suspend (sessionId: String, ref: AttachmentRef) -> ByteArray?

@Composable
fun ChatRoute(
    modifier: Modifier = Modifier,
    viewModel: ChatViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    ChatScreen(
        uiState = uiState,
        onAction = viewModel::onAction,
        modifier = modifier,
        loadAttachment = viewModel::loadAttachmentBytes,
    )
}

@Composable
fun ChatScreen(
    uiState: ChatUiState,
    onAction: (ChatAction) -> Unit,
    modifier: Modifier = Modifier,
    loadAttachment: AttachmentLoader = { _, _ -> null },
) {
    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val useTwoPanes = maxWidth >= 720.dp

        Scaffold { innerPadding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
            ) {
                ConnectionBanner(uiState = uiState)
                if (useTwoPanes) {
                    Row(modifier = Modifier.fillMaxSize()) {
                        SessionPanel(
                            sessions = uiState.sessions,
                            workspaces = uiState.workspaces,
                            searchResults = uiState.searchResults,
                            selectedSessionId = uiState.selectedSessionId,
                            onSelectSession = { onAction(ChatAction.SelectSession(it)) },
                            onCreateSession = { onAction(ChatAction.CreateSessionInWorkspace(it)) },
                            onSearchSessions = { onAction(ChatAction.SearchSessions(it)) },
                            modifier = Modifier.width(320.dp),
                        )
                        ChatPanel(
                            uiState = uiState,
                            onAction = onAction,
                            loadAttachment = loadAttachment,
                            modifier = Modifier.weight(1f),
                        )
                    }
                } else {
                    Column(modifier = Modifier.fillMaxSize()) {
                        SessionPanel(
                            sessions = uiState.sessions,
                            workspaces = uiState.workspaces,
                            searchResults = uiState.searchResults,
                            selectedSessionId = uiState.selectedSessionId,
                            onSelectSession = { onAction(ChatAction.SelectSession(it)) },
                            onCreateSession = { onAction(ChatAction.CreateSessionInWorkspace(it)) },
                            onSearchSessions = { onAction(ChatAction.SearchSessions(it)) },
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(160.dp),
                        )
                        ChatPanel(
                            uiState = uiState,
                            onAction = onAction,
                            loadAttachment = loadAttachment,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ConnectionBanner(uiState: ChatUiState) {
    val connection = uiState.connection
    val text = when (connection.phase) {
        ConnectionPhase.CONNECTED -> "connected ${connection.hostDescription?.version.orEmpty()}"
        ConnectionPhase.CONNECTING -> "connecting"
        ConnectionPhase.RECONNECTING -> "reconnecting"
        ConnectionPhase.DISCONNECTED -> "disconnected"
    }
    Text(
        text = text,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 4.dp),
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        style = MaterialTheme.typography.labelMedium,
    )
}

@Composable
private fun SessionPanel(
    sessions: List<SessionSummary>,
    workspaces: List<WorkspaceSummary>,
    searchResults: List<SessionSearchResult>,
    selectedSessionId: String?,
    onSelectSession: (String) -> Unit,
    onCreateSession: (String?) -> Unit,
    onSearchSessions: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var query by remember { mutableStateOf("") }
    var showNewSessionDialog by remember { mutableStateOf(false) }
    Column(modifier = modifier.padding(8.dp)) {
        OutlinedButton(
            onClick = { showNewSessionDialog = true },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("New session")
        }

        if (showNewSessionDialog) {
            AlertDialog(
                onDismissRequest = { showNewSessionDialog = false },
                title = { Text("New session") },
                text = {
                    Column {
                        if (workspaces.isEmpty()) {
                            Text("No workspaces registered.")
                            Text(
                                text = "Use the Workspaces tab to register a directory first, or choose Default to create an unaccounted session.",
                                style = MaterialTheme.typography.bodySmall,
                            )
                        } else {
                            Text(
                                text = "Choose a workspace or keep the default.",
                                style = MaterialTheme.typography.bodySmall,
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            workspaces.forEach { workspace ->
                                OutlinedButton(
                                    onClick = {
                                        onCreateSession(workspace.workspaceId)
                                        showNewSessionDialog = false
                                    },
                                    modifier = Modifier.fillMaxWidth(),
                                ) {
                                    Text(
                                        text = "${workspace.title} — ${workspace.path}",
                                        maxLines = 1,
                                    )
                                }
                            }
                        }
                    }
                },
                confirmButton = {
                    Button(
                        onClick = {
                            onCreateSession(null)
                            showNewSessionDialog = false
                        },
                    ) { Text("Default") }
                },
                dismissButton = {
                    OutlinedButton(onClick = { showNewSessionDialog = false }) {
                        Text("Cancel")
                    }
                },
            )
        }

        Row(modifier = Modifier.fillMaxWidth()) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                modifier = Modifier.weight(1f),
                placeholder = { Text("Search sessions") },
                singleLine = true,
            )
            Button(
                onClick = { onSearchSessions(query) },
                modifier = Modifier.padding(start = 4.dp),
                enabled = query.isNotBlank(),
            ) {
                Text("Go")
            }
        }
        searchResults.forEach { result ->
            OutlinedButton(
                onClick = { onSelectSession(result.sessionId) },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Search: ${result.snippet}", maxLines = 1)
            }
        }
        Spacer(modifier = Modifier.height(8.dp))
        LazyColumn(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            items(sessions, key = { it.id }) { session ->
                val selected = session.id == selectedSessionId
                Button(
                    onClick = { onSelectSession(session.id) },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !selected,
                ) {
                    val displayTitle = if (session.blank) "New session" else session.displayTitle
                    val status = if (!session.blank && session.running) " ●" else ""
                    Text(
                        text = displayTitle + status,
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

@Composable
private fun ChatPanel(
    uiState: ChatUiState,
    onAction: (ChatAction) -> Unit,
    loadAttachment: AttachmentLoader,
    modifier: Modifier = Modifier,
) {
    var showRenameDialog by remember { mutableStateOf(false) }
    var renameTitle by remember { mutableStateOf("") }
    var showArchiveDialog by remember { mutableStateOf(false) }
    var promptMode by remember(uiState.selectedSessionId) { mutableStateOf(PromptMode.QUEUE) }
    val selectedSessionId = uiState.selectedSessionId
    val selectedSession = uiState.sessions.firstOrNull { it.id == selectedSessionId }
    val isSessionRunning = selectedSession?.running == true

    Column(modifier = modifier.padding(12.dp)) {
        if (selectedSessionId != null) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                OutlinedButton(onClick = { showRenameDialog = true }) { Text("Rename") }
                OutlinedButton(
                    onClick = { onAction(ChatAction.ForkSession(selectedSessionId)) },
                    modifier = Modifier.padding(start = 4.dp),
                ) { Text("Fork") }
                OutlinedButton(
                    onClick = { showArchiveDialog = true },
                    enabled = selectedSession?.blank != true,
                    modifier = Modifier.padding(start = 4.dp),
                ) { Text("Archive") }
                uiState.plan?.let { plan ->
                    Spacer(modifier = Modifier.width(8.dp))
                    PlanChip(plan)
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
        }

        if (showArchiveDialog && selectedSessionId != null) {
            AlertDialog(
                onDismissRequest = { showArchiveDialog = false },
                title = { Text("Archive session") },
                text = {
                    Text("The session log and its workspace seat are kept; this row is hidden from all grouping surfaces.")
                },
                confirmButton = {
                    Button(
                        onClick = {
                            onAction(ChatAction.ArchiveSession(selectedSessionId))
                            showArchiveDialog = false
                        },
                    ) { Text("Archive") }
                },
                dismissButton = {
                    OutlinedButton(onClick = { showArchiveDialog = false }) { Text("Cancel") }
                },
            )
        }

        if (showRenameDialog && selectedSessionId != null) {
            AlertDialog(
                onDismissRequest = { showRenameDialog = false },
                title = { Text("Rename session") },
                text = {
                    OutlinedTextField(
                        value = renameTitle,
                        onValueChange = { renameTitle = it },
                        singleLine = true,
                    )
                },
                confirmButton = {
                    Button(
                        onClick = {
                            onAction(ChatAction.RenameSession(selectedSessionId, renameTitle))
                            showRenameDialog = false
                            renameTitle = ""
                        },
                    ) { Text("Save") }
                },
                dismissButton = {
                    OutlinedButton(onClick = { showRenameDialog = false }) { Text("Cancel") }
                },
            )
        }

        uiState.errorMessage?.let { error ->
            Text(text = error, color = MaterialTheme.colorScheme.error)
            Spacer(modifier = Modifier.height(8.dp))
        }

        var outline by remember(uiState.selectedSessionId) { mutableStateOf(false) }
        var collapsedTurns by remember(uiState.selectedSessionId) { mutableStateOf(setOf<Long>()) }
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedButton(onClick = { outline = !outline }) {
                Text(if (outline) "Outline: on" else "Outline: off")
            }
            if (outline && collapsedTurns.isNotEmpty()) {
                OutlinedButton(
                    onClick = { collapsedTurns = emptySet() },
                    modifier = Modifier.padding(start = 8.dp),
                ) { Text("Expand all") }
            }
        }
        Spacer(modifier = Modifier.height(4.dp))

        if (outline) {
            OutlineTimeline(
                timeline = uiState.timeline,
                collapsedTurns = collapsedTurns,
                onToggle = { turn -> collapsedTurns = collapsedTurns.toMutableSet().apply { if (!add(turn)) remove(turn) } },
                onAction = onAction,
                loadAttachment = loadAttachment,
                modifier = Modifier.weight(1f),
            )
        } else {
            LazyColumn(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(uiState.timeline, key = { timelineKey(it) }) { item ->
                    TimelineRow(item = item, onAction = onAction, loadAttachment = loadAttachment)
                }
            }
        }

        Row(modifier = Modifier.fillMaxWidth()) {
            ComposerBar(
                enabled = uiState.selectedSessionId != null && !uiState.isSending,
                isSending = uiState.isSending,
                running = isSessionRunning,
                mode = promptMode,
                onModeChange = { promptMode = it },
                pendingImages = uiState.pendingImages,
                imageLimits = uiState.imageLimits,
                skills = uiState.skills,
                onAction = onAction,
                onSend = {
                    onAction(
                        ChatAction.SendPrompt(
                            text = it,
                            mode = if (isSessionRunning) promptMode else PromptMode.QUEUE,
                        ),
                    )
                },
                modifier = Modifier.weight(1f),
            )
            Button(
                onClick = { onAction(ChatAction.CancelTurn) },
                enabled = uiState.selectedSessionId != null,
                modifier = Modifier.padding(start = 8.dp),
            ) {
                Text("Stop")
            }
        }
    }
}

/** Plan collaboration state; `/plan` in the composer toggles it. */
@Composable
private fun PlanChip(plan: PlanState) {
    val label = when {
        plan.pending -> "Plan: switching…"
        plan.active -> "Plan: active"
        else -> "Plan: off"
    }
    Text(
        text = label,
        style = MaterialTheme.typography.labelMedium,
        color = if (plan.active || plan.pending) {
            MaterialTheme.colorScheme.primary
        } else {
            MaterialTheme.colorScheme.onSurfaceVariant
        },
    )
}

@Composable
private fun TimelineRow(
    item: TimelineItem,
    onAction: (ChatAction) -> Unit,
    loadAttachment: AttachmentLoader,
) {
    when (item) {
        is TimelineItem.Message -> MessageRow(item.value, loadAttachment)
        is TimelineItem.TurnBoundary -> TurnBoundaryRow(item.turn)
        is TimelineItem.ToolCall -> ToolCallRow(item)
        is TimelineItem.ApprovalRequest -> ApprovalRow(
            requestId = item.requestId,
            approvalId = item.approvalId,
            toolName = item.toolName,
            reason = item.reason,
            onAction = onAction,
        )
        is TimelineItem.QuestionRequest -> QuestionRow(
            request = item,
            onAction = onAction,
        )
        is TimelineItem.Queue -> QueueRow(
            items = item.items,
            onAction = onAction,
        )
        is TimelineItem.Jobs -> JobsRow(item.jobs)
        is TimelineItem.Error -> Text(
            text = item.message,
            color = MaterialTheme.colorScheme.error,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
private fun MessageRow(
    message: ChatMessage,
    loadAttachment: AttachmentLoader,
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = if (message.role == MessageRole.USER) "You" else "Assistant",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        message.reasoning?.takeIf { it.isNotEmpty() }?.let { reasoning ->
            Text(
                text = reasoning,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (message.text.isNotEmpty()) {
            MarkdownText(text = message.text)
        }
        message.images.forEach { ref ->
            AttachmentImageRow(sessionId = message.sessionId, ref = ref, loadAttachment = loadAttachment)
        }
        if (message.streaming) {
            CircularProgressIndicator(
                modifier = Modifier
                    .width(12.dp)
                    .height(12.dp),
            )
        }
    }
}

/**
 * Draft-image thumbnail: decode the pending base64 payload once per image,
 * downsampled to icon size, off the main thread. The name chip stays if the
 * bytes fail to decode.
 */
@Composable
private fun PendingImageThumbnail(image: PendingImage) {
    val bitmap by produceState<android.graphics.Bitmap?>(
        initialValue = null,
        key1 = image.id,
        key2 = image.base64Data,
    ) {
        value = withContext(Dispatchers.Default) {
            runCatching {
                val bytes = Base64.getDecoder().decode(image.base64Data)
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                BitmapFactory.Options().apply {
                    inSampleSize = maxOf(1, minOf(bounds.outWidth, bounds.outHeight) / 128)
                }.let { options ->
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
                }
            }.getOrNull()
        }
    }
    if (bitmap != null) {
        Image(
            bitmap = bitmap!!.asImageBitmap(),
            contentDescription = image.name ?: "pending image",
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .padding(end = 4.dp)
                .size(36.dp)
                .clip(RoundedCornerShape(4.dp)),
        )
    }
}

/** One durable image: lazy download through the loader, placeholder on failure. */
@Composable
private fun AttachmentImageRow(
    sessionId: String,
    ref: AttachmentRef,
    loadAttachment: AttachmentLoader,
) {
    var retryCount by remember(ref.attachmentId) { mutableStateOf(0) }
    val bitmap by produceState<android.graphics.Bitmap?>(
        initialValue = null,
        key1 = sessionId,
        key2 = ref.attachmentId,
        key3 = retryCount,
    ) {
        val bytes = loadAttachment(sessionId, ref)
        value = bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
    }
    Column(modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
        if (bitmap != null) {
            Image(
                bitmap = bitmap!!.asImageBitmap(),
                contentDescription = ref.name ?: "image attachment",
                contentScale = ContentScale.FillWidth,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(180.dp),
            )
        } else {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "image ${ref.width}×${ref.height} (${ref.bytes} bytes)" +
                        (ref.name?.let { " · $it" } ?: ""),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                OutlinedButton(onClick = { retryCount++ }) { Text("Retry") }
            }
        }
    }
}

@Composable
private fun ToolCallRow(call: TimelineItem.ToolCall) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = "${call.name} ${call.status.label()}",
            style = MaterialTheme.typography.labelLarge,
        )
        call.arguments?.let { Text(text = it, style = MaterialTheme.typography.bodySmall) }
        call.result?.let { Text(text = it, style = MaterialTheme.typography.bodySmall) }
    }
}

private fun ToolRunStatus.label(): String = when (this) {
    ToolRunStatus.RUNNING -> "running..."
    ToolRunStatus.COMPLETED -> "done"
    ToolRunStatus.FAILED -> "failed"
}

@Composable
private fun JobsRow(jobs: List<JobView>) {
    Column(modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
        Text("Background jobs", style = MaterialTheme.typography.labelLarge)
        jobs.forEach { job ->
            Text(
                text = "${job.kind} · ${job.label} · ${job.status}",
                style = MaterialTheme.typography.bodySmall,
            )
            job.detail?.let { Text(text = it, style = MaterialTheme.typography.bodySmall) }
            if (job.finishedAt != null) {
                Text(
                    text = "finished @ ${job.finishedAt}",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }
}

@Composable
private fun QueueRow(
    items: List<SessionQueueItem>,
    onAction: (ChatAction) -> Unit,
) {
    var editingItemId by remember(items) { mutableStateOf<String?>(null) }
    var editingText by remember(items) { mutableStateOf("") }

    items.forEach { item ->
        val prefix = when (item.placement) {
            QueuePlacement.QUEUED -> "Queued"
            QueuePlacement.STEERING -> "Steering"
            QueuePlacement.CONTEXT -> "Context"
        }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 2.dp),
        ) {
            Text(text = "$prefix: ${item.text}", style = MaterialTheme.typography.bodySmall)
            if (item.placement != QueuePlacement.CONTEXT) {
                Row {
                    if (item.placement == QueuePlacement.QUEUED && item.text.isNotBlank()) {
                        OutlinedButton(
                            onClick = {
                                editingItemId = item.itemId
                                editingText = item.text
                            },
                        ) { Text("Edit") }
                    }
                    OutlinedButton(
                        onClick = {
                            onAction(
                                ChatAction.UpdateQueue(
                                    itemId = item.itemId,
                                    kind = QueueUpdateKind.STEER,
                                ),
                            )
                        },
                        modifier = Modifier.padding(start = 4.dp),
                    ) { Text("Steer") }
                    OutlinedButton(
                        onClick = {
                            onAction(
                                ChatAction.UpdateQueue(
                                    itemId = item.itemId,
                                    kind = QueueUpdateKind.REMOVE,
                                ),
                            )
                        },
                        modifier = Modifier.padding(start = 4.dp),
                    ) { Text("Remove") }
                }
            }
        }
    }

    editingItemId?.let { targetId ->
        QueueEditDialog(
            itemId = targetId,
            initialText = editingText,
            onSave = { edited ->
                onAction(
                    ChatAction.UpdateQueue(
                        itemId = targetId,
                        kind = QueueUpdateKind.EDIT,
                        text = edited,
                    ),
                )
            },
            onDismiss = { editingItemId = null },
        )
    }
}

/**
 * Queue text edit: blank text never dispatches (Save no-ops), matching the
 * Web composer's non-empty constraint for queue edits.
 */
@Composable
private fun QueueEditDialog(
    itemId: String,
    initialText: String,
    onSave: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    var text by remember(itemId) { mutableStateOf(initialText) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Edit queued message") },
        text = {
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                singleLine = true,
            )
        },
        confirmButton = {
            Button(
                onClick = {
                    if (text.isNotBlank()) {
                        onSave(text.trim())
                    }
                    onDismiss()
                },
            ) { Text("Save") }
        },
        dismissButton = {
            OutlinedButton(onClick = onDismiss) {
                Text("Cancel")
            }
        },
    )
}

@Preview(showBackground = true)
@Composable
private fun QueueEditDialogPreview() {
    DeepSeekHarnessAndroidTheme {
        QueueEditDialog(
            itemId = "queued-1",
            initialText = "revised prompt",
            onSave = {},
            onDismiss = {},
        )
    }
}

@Composable
private fun ApprovalRow(
    requestId: String,
    approvalId: String,
    toolName: String,
    reason: String?,
    onAction: (ChatAction) -> Unit,
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = "Approve tool: $toolName",
            style = MaterialTheme.typography.titleSmall,
        )
        reason?.let { Text(text = it, style = MaterialTheme.typography.bodySmall) }
        Row {
            Button(
                onClick = { onAction(ChatAction.RespondApproval(requestId, approvalId, true)) },
            ) {
                Text("Allow")
            }
            OutlinedButton(
                onClick = { onAction(ChatAction.RespondApproval(requestId, approvalId, false)) },
                modifier = Modifier.padding(start = 8.dp),
            ) {
                Text("Reject")
            }
        }
    }
}

@Composable
private fun QuestionRow(
    request: TimelineItem.QuestionRequest,
    onAction: (ChatAction) -> Unit,
) {
    var drafts by remember(request.requestId) {
        mutableStateOf<Map<String, QuestionDraft>>(emptyMap())
    }
    val answerEnabled = request.questions.isNotEmpty() && request.questions.all { question ->
        val draft = drafts[question.id] ?: QuestionDraft()
        draft.skipped || draft.selected.isNotEmpty() || draft.customText.isNotBlank()
    }
    Column(modifier = Modifier.fillMaxWidth()) {
        request.questions.forEach { question ->
            QuestionItemEditor(
                question = question,
                draft = drafts[question.id] ?: QuestionDraft(),
                onDraftChange = { updated ->
                    drafts = drafts + (question.id to updated)
                },
            )
        }
        Button(
            onClick = {
                val answers = request.questions.map { question ->
                    val draft = drafts[question.id] ?: QuestionDraft()
                    if (draft.skipped) {
                        QuestionAnswer(
                            questionId = question.id,
                            selectedOptions = emptyList(),
                        )
                    } else {
                        val custom = draft.customText.trim()
                        QuestionAnswer(
                            questionId = question.id,
                            selectedOptions = if (
                                custom.isNotEmpty() && !question.multiSelect
                            ) {
                                emptyList()
                            } else {
                                draft.selected.toList()
                            },
                            customText = custom.ifBlank { null },
                        )
                    }
                }
                onAction(ChatAction.AnswerQuestion(request.requestId, answers))
            },
            enabled = answerEnabled,
        ) {
            Text("Answer")
        }
    }
}

/**
 * Plan-review decision card: the plan body renders as markdown (the detail
 * slot carries it), the approve option is the primary action, and any other
 * option stays secondary. Answers use the same question channel.
 */
@Composable
private fun PlanReviewEditor(
    question: QuestionItem,
    draft: QuestionDraft,
    onDraftChange: (QuestionDraft) -> Unit,
) {
    val approve = question.intent?.approve
    val chosen = draft.selected.singleOrNull()
    Column {
        Text(
            text = question.header ?: "Plan review",
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
        )
        Text(text = question.question, style = MaterialTheme.typography.titleSmall)
        question.detail?.let { plan ->
            Surface(
                color = MaterialTheme.colorScheme.surfaceVariant,
                shape = RoundedCornerShape(6.dp),
                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
            ) {
                MarkdownText(
                    text = plan,
                    modifier = Modifier.padding(8.dp),
                )
            }
        }
        Row {
            val approveOption = question.options.firstOrNull { it == approve }
                ?: question.options.firstOrNull()
            approveOption?.let { option ->
                Button(onClick = { onDraftChange(draft.copy(selected = setOf(option))) }) {
                    Text(if (chosen == option) "✓ $option" else option)
                }
            }
            question.options.filterNot { it == approveOption }.forEach { option ->
                OutlinedButton(
                    onClick = { onDraftChange(draft.copy(selected = setOf(option))) },
                    modifier = Modifier.padding(start = 8.dp),
                ) {
                    Text(if (chosen == option) "✓ $option" else option)
                }
            }
        }
    }
}

private data class QuestionDraft(
    val selected: Set<String> = emptySet(),
    val customText: String = "",
    val skipped: Boolean = false,
)

@Composable
private fun QuestionItemEditor(
    question: QuestionItem,
    draft: QuestionDraft,
    onDraftChange: (QuestionDraft) -> Unit,
) {
    if (question.intent?.kind == "plan-review") {
        PlanReviewEditor(question = question, draft = draft, onDraftChange = onDraftChange)
        return
    }
    val selected = draft.selected
    Column {
        question.header?.let { Text(text = it, style = MaterialTheme.typography.labelLarge) }
        Text(text = question.question, style = MaterialTheme.typography.titleSmall)
        question.detail?.let { Text(text = it, style = MaterialTheme.typography.bodySmall) }
        if (draft.skipped) {
            Text(
                text = "Skipped",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedButton(
                onClick = {
                    onDraftChange(
                        QuestionDraft(
                            selected = emptySet(),
                            customText = "",
                            skipped = false,
                        ),
                    )
                },
            ) { Text("Answer instead") }
        } else {
            question.options.forEach { option ->
                val isSelected = option in selected
                if (isSelected) {
                    Button(
                        onClick = {
                            onDraftChange(
                                QuestionDraft(
                                    selected = selectedWithout(selected, option, question.multiSelect),
                                    customText = draft.customText,
                                ),
                            )
                        },
                    ) {
                        Text(option)
                    }
                } else {
                    OutlinedButton(
                        onClick = {
                            onDraftChange(
                                QuestionDraft(
                                    selected = selectedWith(selected, option, question.multiSelect),
                                    customText = if (question.multiSelect) draft.customText else "",
                                ),
                            )
                        },
                    ) {
                        Column {
                            Text(option)
                            question.optionDescriptions[option]?.let { description ->
                                Text(
                                    text = description,
                                    style = MaterialTheme.typography.bodySmall,
                                )
                            }
                        }
                    }
                }
            }
            OutlinedTextField(
                value = draft.customText,
                onValueChange = { text ->
                    onDraftChange(
                        QuestionDraft(
                            selected = if (
                                text.isNotBlank() && !question.multiSelect
                            ) {
                                emptySet()
                            } else {
                                draft.selected
                            },
                            customText = text,
                        ),
                    )
                },
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("Type your answer") },
                singleLine = true,
            )
            OutlinedButton(
                onClick = {
                    onDraftChange(
                        QuestionDraft(
                            selected = emptySet(),
                            customText = "",
                            skipped = true,
                        ),
                    )
                },
            ) { Text("Skip") }
        }
    }
}

private fun selectedWith(current: Set<String>, option: String, multi: Boolean): Set<String> =
    if (multi) current + option else setOf(option)

private fun selectedWithout(current: Set<String>, option: String, multi: Boolean): Set<String> =
    if (multi) current - option else emptySet()

@Composable
private fun ComposerBar(
    enabled: Boolean,
    isSending: Boolean,
    running: Boolean,
    mode: PromptMode,
    onModeChange: (PromptMode) -> Unit,
    pendingImages: List<PendingImage>,
    imageLimits: ImageLimits,
    skills: List<SkillEntry>,
    onAction: (ChatAction) -> Unit,
    onSend: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var draft by remember { mutableStateOf("") }
    val effectiveMode = if (running) mode else PromptMode.QUEUE
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val pickImages = rememberLauncherForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(),
    ) { uris ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        scope.launch {
            val loaded = mutableListOf<PendingImage>()
            var failure: String? = null
            withContext(Dispatchers.IO) {
                uris.forEach { uri ->
                    runCatching {
                        val mediaType = context.contentResolver.getType(uri)
                            ?: guessImageMediaType(uri)
                        require(mediaType != null) { "unknown image type for ${uri.lastPathSegment}" }
                        val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                        requireNotNull(bytes) { "cannot read ${uri.lastPathSegment}" }
                        PendingImage(
                            id = uri.toString(),
                            mediaType = mediaType,
                            base64Data = Base64.getEncoder().encodeToString(bytes),
                            name = uri.lastPathSegment,
                            byteSize = bytes.size.toLong(),
                        )
                    }.onSuccess { loaded += it }
                        .onFailure { failure = it.message ?: it.javaClass.simpleName }
                }
            }
            if (loaded.isNotEmpty()) onAction(ChatAction.ImagesLoaded(loaded))
            failure?.let { onAction(ChatAction.ImagePickError(it)) }
        }
    }
    val attachAllowed = enabled && pendingImages.size < imageLimits.maxImagesPerMessage
    Column(modifier = modifier) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = "Delivery",
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.padding(end = 8.dp),
            )
            ModeChip(
                label = "Queue",
                selected = effectiveMode == PromptMode.QUEUE,
                enabled = enabled,
                onClick = { onModeChange(PromptMode.QUEUE) },
            )
            ModeChip(
                label = "Steer",
                selected = effectiveMode == PromptMode.STEER,
                enabled = enabled && running,
                onClick = { onModeChange(PromptMode.STEER) },
            )
        }
        if (pendingImages.isNotEmpty()) {
            Row(modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                pendingImages.forEach { image ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.padding(end = 8.dp),
                    ) {
                        PendingImageThumbnail(image)
                        Text(
                            text = image.name ?: image.id.substringAfterLast('/'),
                            style = MaterialTheme.typography.bodySmall,
                        )
                        IconButton(onClick = { onAction(ChatAction.RemovePendingImage(image.id)) }) {
                            Icon(
                                Icons.Filled.Close,
                                contentDescription = "Remove ${image.name ?: "attachment"}",
                                modifier = Modifier.size(16.dp),
                            )
                        }
                    }
                }
            }
        }
        SlashSkillCandidates(
            draft = draft,
            skills = skills,
            enabled = enabled,
            onPick = { name -> draft = "/$name " },
        )
        Row(
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(
                onClick = {
                    pickImages.launch(
                        PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                    )
                },
                enabled = attachAllowed,
            ) {
                Icon(Icons.Filled.Add, contentDescription = "Attach images")
            }
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it },
                modifier = Modifier.weight(1f),
                enabled = enabled,
                placeholder = {
                    Text(
                        if (effectiveMode == PromptMode.STEER) {
                            "Steer the running turn"
                        } else {
                            "Message DeepSeek Harness"
                        },
                    )
                },
            )
            Button(
                onClick = {
                    onSend(draft)
                    draft = ""
                },
                modifier = Modifier.padding(start = 8.dp),
                enabled = enabled && !isSending && (draft.isNotBlank() || pendingImages.isNotEmpty()),
            ) {
                Text(if (isSending) "Sending" else "Send")
            }
        }
    }
}

/**
 * `/` composer source: while the draft is a single slash token, offer the
 * session's skill catalog filtered by prefix; picking lands the literal
 * `/name ` text, matching the Web plain-text-reference decision.
 */
@Composable
private fun SlashSkillCandidates(
    draft: String,
    skills: List<SkillEntry>,
    enabled: Boolean,
    onPick: (String) -> Unit,
) {
    if (!enabled || !draft.startsWith("/") || draft.contains(' ')) return
    val query = draft.removePrefix("/").lowercase()
    val candidates = skills.filter { skill ->
        query.isEmpty() || skill.name.lowercase().startsWith(query)
    }.take(6)
    if (candidates.isEmpty()) return
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = RoundedCornerShape(6.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 4.dp),
    ) {
        Column(modifier = Modifier.padding(4.dp)) {
            candidates.forEach { skill ->
                OutlinedButton(
                    onClick = { onPick(skill.name) },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(modifier = Modifier.fillMaxWidth()) {
                        Text(
                            text = "/${skill.name}",
                            style = MaterialTheme.typography.titleSmall,
                        )
                        Text(
                            text = skill.description,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                        )
                    }
                }
            }
        }
    }
}

/** Photo-picker fallback when the resolver reports no MIME type. */
private fun guessImageMediaType(uri: Uri): String? =
    when (uri.lastPathSegment?.substringAfterLast('.', "")?.lowercase()) {
        "png" -> "image/png"
        "jpg", "jpeg" -> "image/jpeg"
        "webp" -> "image/webp"
        "gif" -> "image/gif"
        else -> null
    }

@Composable
private fun ModeChip(
    label: String,
    selected: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    if (selected) {
        Button(
            onClick = onClick,
            enabled = enabled,
            modifier = Modifier.padding(end = 4.dp),
        ) { Text(label) }
    } else {
        OutlinedButton(
            onClick = onClick,
            enabled = enabled,
            modifier = Modifier.padding(end = 4.dp),
        ) { Text(label) }
    }
}

private fun timelineKey(item: TimelineItem): String = when (item) {
    is TimelineItem.Message -> "message:${item.value.id}:${item.value.streaming}"
    is TimelineItem.TurnBoundary -> "turn:${item.turn}"
    is TimelineItem.ToolCall -> "tool:${item.id}:${item.status}"
    is TimelineItem.ApprovalRequest -> "approval:${item.requestId}"
    is TimelineItem.QuestionRequest -> "question:${item.requestId}"
    is TimelineItem.Queue -> "queue"
    is TimelineItem.Jobs -> "jobs"
    is TimelineItem.Error -> "error:${item.id}"
}

/** Ledger-style outline: turn-group headers collapse their rows on tap. */
@Composable
private fun OutlineTimeline(
    timeline: List<TimelineItem>,
    collapsedTurns: Set<Long>,
    onToggle: (Long) -> Unit,
    onAction: (ChatAction) -> Unit,
    loadAttachment: AttachmentLoader,
    modifier: Modifier = Modifier,
) {
    val groups = remember(timeline) { groupTimelineByTurn(timeline) }
    LazyColumn(modifier = modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        groups.forEachIndexed { groupIndex, group ->
            val turn = group.turn
            val collapsed = turn != null && turn in collapsedTurns
            item(key = "group-${turn ?: groupIndex}") {
                TurnGroupHeader(
                    turn = turn,
                    items = group.items,
                    collapsed = collapsed,
                    onToggle = onToggle,
                )
            }
            if (!collapsed) {
                items(group.items, key = { timelineKey(it) }) { item ->
                    TimelineRow(item = item, onAction = onAction, loadAttachment = loadAttachment)
                }
            }
        }
    }
}

@Composable
private fun TurnGroupHeader(
    turn: Long?,
    items: List<TimelineItem>,
    collapsed: Boolean,
    onToggle: (Long) -> Unit,
) {
    val messages = items.count { it is TimelineItem.Message }
    val tools = items.filterIsInstance<TimelineItem.ToolCall>()
    val label = when {
        turn == null -> "Before first turn · $messages messages"
        else -> "Turn $turn · $messages messages · ${tools.size} tools"
    }
    val toolSummary = tools
        .groupBy({ it.name }, { it.status })
        .toSortedMap()
        .entries
        .joinToString(separator = " · ") { (name, statuses) ->
            val completed = statuses.count { it == ToolRunStatus.COMPLETED }
            val failed = statuses.count { it == ToolRunStatus.FAILED }
            val running = statuses.count { it == ToolRunStatus.RUNNING }
            buildString {
                append(name)
                append(' ')
                append(completed)
                append('✓')
                if (failed > 0) append(" $failed✗")
                if (running > 0) append(" $running…")
            }
        }
    OutlinedButton(
        onClick = { turn?.let(onToggle) },
        enabled = turn != null,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            Text(if (collapsed) "▸ $label" else "▾ $label")
            promptPreview(items)?.let { prompt ->
                Text(
                    text = "“$prompt”",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 1,
                )
            }
            if (toolSummary.isNotEmpty()) {
                Text(
                    text = toolSummary,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = if (collapsed) 2 else 1,
                )
            }
        }
    }
}

/** Ledger-style turn divider, the first slice of the Web trajectory grouping. */
@Composable
private fun TurnBoundaryRow(turn: Long) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
    ) {
        HorizontalDivider(modifier = Modifier.weight(1f))
        Text(
            text = "Turn $turn",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 8.dp),
        )
        HorizontalDivider(modifier = Modifier.weight(1f))
    }
}

@Preview(showBackground = true, widthDp = 840)
@Composable
private fun ChatScreenPreview() {
    DeepSeekHarnessAndroidTheme {
        ChatScreen(
            uiState = ChatUiState(
                connection = ConnectionState(
                    phase = ConnectionPhase.CONNECTED,
                    hostDescription = HostDescription(version = "preview", cwd = "/tmp"),
                ),
                sessions = listOf(SessionSummary(id = "s1", title = "Preview session")),
                selectedSessionId = "s1",
                timeline = listOf(
                    TimelineItem.Message(
                        ChatMessage(
                            id = "m1",
                            sessionId = "s1",
                            role = MessageRole.ASSISTANT,
                            text = "Kotlin best-practice skeleton.",
                        ),
                    ),
                    TimelineItem.Message(
                        ChatMessage(
                            id = "m2",
                            sessionId = "s1",
                            role = MessageRole.USER,
                            text = "Screenshot attached.",
                            images = listOf(
                                AttachmentRef(
                                    attachmentId = "preview-image-1",
                                    mediaType = "image/png",
                                    bytes = 20_480L,
                                    width = 640,
                                    height = 480,
                                    name = "screenshot.png",
                                ),
                            ),
                        ),
                    ),
                    TimelineItem.ToolCall(
                        id = "call-1",
                        name = "bash",
                        arguments = "ls -la",
                        result = "README.md",
                        status = ToolRunStatus.COMPLETED,
                    ),
                    TimelineItem.ApprovalRequest(
                        requestId = "rpc-1",
                        sessionId = "s1",
                        approvalId = "approval-1",
                        toolName = "bash",
                        reason = "Would run a command",
                    ),
                    TimelineItem.QuestionRequest(
                        requestId = "rpc-2",
                        questions = listOf(
                            QuestionItem(
                                id = "q1",
                                question = "Continue?",
                                options = listOf("yes", "no"),
                            ),
                        ),
                    ),
                ),
            ),
            onAction = {},
        )
    }
}
