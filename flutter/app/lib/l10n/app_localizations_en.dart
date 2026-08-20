// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'DeepSeek Harness';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get create => 'Create';

  @override
  String get refresh => 'Refresh';

  @override
  String get retry => 'Retry';

  @override
  String get back => 'Back';

  @override
  String get close => 'Close';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get delete => 'Delete';

  @override
  String get rename => 'Rename';

  @override
  String get open => 'Open';

  @override
  String get defaultBadge => 'Default';

  @override
  String get destinationChat => 'Chat';

  @override
  String get destinationWorkspaces => 'Workspaces';

  @override
  String get destinationSettings => 'Settings';

  @override
  String get goalTitle => 'Goal';

  @override
  String get sessionLabel => 'Session';

  @override
  String get providersLabel => 'Providers';

  @override
  String get noCurrentGoal => 'No ongoing goal';

  @override
  String get goalObjectiveHint => 'Goal objective';

  @override
  String get maxGoalRoundsHint => 'Max goal rounds (optional)';

  @override
  String get pause => 'Pause goal';

  @override
  String get resume => 'Resume goal';

  @override
  String get clear => 'Clear goal';

  @override
  String get complete => 'Complete goal';

  @override
  String get edit => 'Edit goal';

  @override
  String get goalPhaseActive => 'Ongoing Goal';

  @override
  String get goalPhasePaused => 'Paused Goal';

  @override
  String get goalPhaseBlocked => 'Blocked Goal';

  @override
  String get goalPhaseComplete => 'Completed Goal';

  @override
  String goalStatusLine(int max, String phase, int revision, int started) {
    return '$phase · revision $revision · rounds $started/$max';
  }

  @override
  String contextUsedPercent(int percent) {
    return '$percent% of context used';
  }

  @override
  String get systemPromptLabel => 'System prompt';

  @override
  String get toolsLabel => 'Tools';

  @override
  String get conversationLabel => 'Messages';

  @override
  String contextTokens(String used, String window) {
    return '~$used / $window';
  }

  @override
  String get heroHeadline => 'Into the Unknown';

  @override
  String get heroPreview => 'Preview';

  @override
  String get heroChooseWorkspace => 'Choose workspace';

  @override
  String get modelsTitle => 'Models';

  @override
  String modelCurrent(String name) {
    return '$name (current)';
  }

  @override
  String get reasoningEffortLabel => 'Reasoning effort';

  @override
  String get todosLabel => 'To-dos';

  @override
  String todoCountDone(int count) {
    return '$count completed';
  }

  @override
  String todoCountActive(int count) {
    return '$count in progress';
  }

  @override
  String todoCountPending(int count) {
    return '$count pending';
  }

  @override
  String get backgroundJobsTitle => 'Background jobs';

  @override
  String jobCountRunning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count background jobs running',
      one: '1 background job running',
    );
    return '$_temp0';
  }

  @override
  String jobCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count background jobs',
      one: '1 background job',
    );
    return '$_temp0';
  }

  @override
  String get jobStatusRunning => 'running';

  @override
  String get jobStatusStopping => 'stopping';

  @override
  String get jobStatusCompleted => 'completed';

  @override
  String get jobStatusKilled => 'cancelled';

  @override
  String get jobStatusFailed => 'failed';

  @override
  String jobDurationHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String jobDurationMinutesSeconds(int minutes, int seconds) {
    return '${minutes}m ${seconds}s';
  }

  @override
  String jobDurationSeconds(int seconds) {
    return '${seconds}s';
  }

  @override
  String get copyTooltip => 'Copy';

  @override
  String get copiedTooltip => 'Copied';

  @override
  String get waitingForApproval => 'Waiting for approval';

  @override
  String approveToolFallback(String tool) {
    return 'Approve tool: $tool';
  }

  @override
  String toolRequestsPrivileged(String tool) {
    return 'Tool $tool requests privileged execution';
  }

  @override
  String get reject => 'Reject';

  @override
  String get allowOnce => 'Allow once';

  @override
  String get agentPresetLabel => 'Agent preset';

  @override
  String get agentPresetTooltip =>
      'Agent preset for the session you are about to start';

  @override
  String get accessModeLabel => 'Access mode';

  @override
  String accessModeTooltip(String label) {
    return 'Access mode: $label';
  }

  @override
  String get fullAccessOption => 'Full access';

  @override
  String get enableFullAccessTitle => 'Enable Full access?';

  @override
  String get fullAccessRisks =>
      'Full access reduces confirmation steps and lets the agent perform more actions directly, including sensitive operations, file changes, or external commands. Only use it when you trust the current task.';

  @override
  String get acknowledgeRisks => 'I understand the risks and want to continue';

  @override
  String get enableFullAccess => 'Enable Full access';

  @override
  String get modelLabel => 'Model';

  @override
  String get effortLabel => 'Effort';

  @override
  String get providerDefault => 'Default';

  @override
  String get presetStandardName => 'Standard mode';

  @override
  String get presetStandardDescription =>
      'Full coding agent with file editing, shell, file and web search, skills, planning, goals, subagents, and workflows.';

  @override
  String get presetCodeName => 'Code mode';

  @override
  String get presetCodeDescription =>
      'All Standard mode capabilities, with tools exposed through the Code Mode SDK so the model can combine multi-step operations in one TypeScript program.';

  @override
  String get presetMinimalName => 'Minimal mode';

  @override
  String get presetMinimalDescription =>
      'Two-tool coding agent with persistent bash and str_replace_editor.';

  @override
  String get presetCordisName => 'Creator mode';

  @override
  String get presetCordisDescription =>
      'Built for creating custom agent presets, with all Standard mode capabilities plus runtime inspection, plugin experiments, and preset-authoring guidance.';

  @override
  String get toolSearchTitle => 'Search';

  @override
  String get toolReadTitle => 'Read';

  @override
  String get toolBashTitle => 'Bash';

  @override
  String get toolWriteTitle => 'Write';

  @override
  String get toolEditTitle => 'Edit';

  @override
  String get toolCodeTitle => 'Code';

  @override
  String get toolCallTitle => 'Tool call';

  @override
  String get toolInspectTitle => 'Inspect';

  @override
  String get toolRunCordisPlugin => 'Run Cordis Plugin';

  @override
  String get toolStopCordisPlugin => 'Stop Cordis Plugin';

  @override
  String get toolRemoveCordisPlugin => 'Remove Cordis Plugin';

  @override
  String get toolPwshTitle => 'Pwsh';

  @override
  String get toolUpdateTodoTitle => 'Update to-do list';

  @override
  String toolTodoPlanCompleted(int done, int total) {
    return '$done/$total completed';
  }

  @override
  String statsTurnsSteps(int steps, int turns) {
    return '$turns turns · $steps steps';
  }

  @override
  String statsLlmDuration(String duration) {
    return 'LLM $duration';
  }

  @override
  String statsToolDuration(String duration) {
    return 'Tool call $duration';
  }

  @override
  String statsTtftAvg(String duration) {
    return 'TTFT avg $duration';
  }

  @override
  String statsTokensPerSecond(String rate) {
    return '$rate tok/s';
  }

  @override
  String statsCacheHit(int percent) {
    return 'Cache hit $percent%';
  }

  @override
  String statsInputTokens(String tokens) {
    return 'Input $tokens tok';
  }

  @override
  String statsOutputTokens(String tokens) {
    return 'Output $tokens tok';
  }

  @override
  String credentialStateUnavailable(String error) {
    return 'Credential state unavailable: $error';
  }

  @override
  String storeCredentialTitle(String ref) {
    return 'Store $ref';
  }

  @override
  String namespaceMetaApplies(String name) {
    return 'applies: $name';
  }

  @override
  String namespaceMetaRevision(int revision) {
    return 'revision: $revision';
  }

  @override
  String credentialMetaSource(String source) {
    return 'source: $source';
  }

  @override
  String casRevisionLine(int revision) {
    return 'CAS revision $revision; host validates against the schema';
  }

  @override
  String newSessionInWorkspace(String title) {
    return 'New session in $title';
  }

  @override
  String workspaceActionsFor(String title) {
    return 'Workspace actions for $title';
  }

  @override
  String workspaceNameExists(String name) {
    return 'A workspace named “$name” already exists.';
  }

  @override
  String deleteWorkspaceConfirm(String name, String ungroupedLabel) {
    return 'This removes “$name” from the workspace list. The folder and session logs will be kept. Its sessions will appear under $ungroupedLabel.';
  }

  @override
  String newFolderIn(String parent) {
    return 'New folder in \"$parent\"';
  }

  @override
  String secretsSetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count secrets set',
      one: '1 secret set',
    );
    return '$_temp0';
  }

  @override
  String workspaceSessionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions',
      one: '1 session',
    );
    return '$_temp0';
  }

  @override
  String get settingsNavBackends => 'Backends';

  @override
  String get settingsNavGeneral => 'General';

  @override
  String get settingsNavModels => 'Models';

  @override
  String get settingsNavPlugins => 'Plugins';

  @override
  String get settingsNavAgentPresets => 'Agent presets';

  @override
  String get settingsNavCredentials => 'Credentials';

  @override
  String get settingsLoopbackHint =>
      'settings/credentials are loopback-only on the host; connect via adb reverse';

  @override
  String get backendsIntro =>
      'Host endpoints this device keeps connected — every configured backend stays live; the active one drives Chat and these host-settings pages.';

  @override
  String get addBackend => 'Add backend';

  @override
  String get editBackend => 'Edit backend';

  @override
  String get removeActiveBackendFirst =>
      'Switch away before removing the active backend.';

  @override
  String get cannotRemoveLastBackend => 'The last backend cannot be removed.';

  @override
  String get backendStatusActive => 'Active';

  @override
  String get backendStatusStandby => 'Standby';

  @override
  String get hostSettingsUnavailable => 'Host settings unavailable';

  @override
  String get hostSettingsUnavailableBody =>
      'The active backend did not answer. Repoint or switch it from the Backends page.';

  @override
  String get hostWritesLabel => 'Host writes';

  @override
  String get hostWritesDescription =>
      'Whether the host accepts settings and credential writes.';

  @override
  String get writableValue => 'Writable';

  @override
  String get readOnlyValue => 'Read-only';

  @override
  String get settingsDocumentLabel => 'Settings document';

  @override
  String get settingsDocumentDescription =>
      'Whether a user settings document backs the namespaces.';

  @override
  String get presentValue => 'Present';

  @override
  String get noneValue => 'None';

  @override
  String get generalIntro =>
      'New-session defaults and the host settings plane.';

  @override
  String get busyPreferenceLabel => 'Enter behavior while busy';

  @override
  String get busyPreferenceDescription =>
      'Busy only; Cmd/Ctrl+Enter uses the other behavior';

  @override
  String get busyBehaviorQueue => 'Queue';

  @override
  String get busyBehaviorSteer => 'Steer';

  @override
  String get agentPresetPreferenceLabel => 'Agent preset';

  @override
  String get agentPresetPreferenceDescription =>
      'Applies to sessions you start from now on. Running sessions keep the preset they began with.';

  @override
  String get agentPresetsIntro =>
      'A preset is the plugin composition one session\'s agent runs — its tools, prompt, and capabilities. Duplicate an existing one and make it yours, or let the agent draft one for you in Creator mode.';

  @override
  String get presetGroupBuiltIn => 'Built-in';

  @override
  String get presetGroupCustom => 'Custom';

  @override
  String get presetsFooter =>
      'Presets are authored on the host: copy, edit, and delete them from the desktop settings.';

  @override
  String get noDescription => 'No description.';

  @override
  String get presetBrokenBadge => 'Failed to load';

  @override
  String get presetInUseBadge => 'In use';

  @override
  String get pluginsIntro =>
      'Configure and inspect the plugins installed in this deployment.';

  @override
  String get noPluginSettings => 'This deployment exposes no plugin settings.';

  @override
  String get modelsIntro =>
      'Enter your API keys to use models from the following providers.';

  @override
  String get settingsReadOnlyNotice =>
      'The settings document is read-only in this deployment.';

  @override
  String get modelsFooter =>
      'Custom providers are managed on the host: this client covers the DeepSeek API key only.';

  @override
  String get apiKeyConfigured => 'API key configured';

  @override
  String get apiKeyMissing => 'API key missing';

  @override
  String get credentialsIntro =>
      'Secret references named by the host namespaces.';

  @override
  String get noCredentialsReferenced => 'No credentials referenced.';

  @override
  String get patchKey => 'Patch key';

  @override
  String get replaceSection => 'Replace section';

  @override
  String get topLevelKey => 'Top-level key';

  @override
  String get wholeUserLayerJson => 'Whole user-layer JSON object';

  @override
  String get jsonValue => 'JSON value';

  @override
  String get jsonKeyValueExampleHint => '{ \"key\": value }';

  @override
  String get jsonValueExampleHint => 'true / 42 / \"text\" / {…}';

  @override
  String get discard => 'Discard';

  @override
  String get stateConfigured => 'Configured';

  @override
  String get stateNotSet => 'Not set';

  @override
  String get credentialReadOnlyHint =>
      'Read-only on this connection; the stored value cannot be changed from this client.';

  @override
  String get unset => 'Unset';

  @override
  String get secretValueLabel => 'Secret value';

  @override
  String get secretValueHint => 'secret value';

  @override
  String get secretValueHintLine =>
      'Stored on the host; the value never rides a response.';

  @override
  String get backendLabel => 'Label';

  @override
  String get backendLabelHint => 'Laptop host, build box, …';

  @override
  String get backendBaseUrlLabel => 'Base URL';

  @override
  String get backendBaseUrlHint => 'http://10.0.2.2:3080';

  @override
  String get baseUrlDerivationHint =>
      'RPC and event paths derive from this base.';

  @override
  String get baseUrlValidHint =>
      'http or https with a host, e.g. http://10.0.2.2:3080';

  @override
  String get remove => 'Remove';

  @override
  String get add => 'Add';

  @override
  String get userLayerLabel => 'user layer';

  @override
  String get credentialMetaConfigured => 'configured';

  @override
  String get credentialMetaNotConfigured => 'not configured';

  @override
  String get credentialMetaWritable => 'writable';

  @override
  String get credentialMetaReadOnly => 'read-only';

  @override
  String get workspacesNavTitle => 'Workspaces';

  @override
  String get searchWorkspacesHint => 'Search workspaces...';

  @override
  String get noMatchingWorkspaces => 'No matches';

  @override
  String get noWorkspacesYet => 'No workspaces yet';

  @override
  String get moveUp => 'Move up';

  @override
  String get moveDown => 'Move down';

  @override
  String get deleteWorkspace => 'Delete workspace';

  @override
  String get renameWorkspace => 'Rename workspace';

  @override
  String get renameWorkspaceTitle => 'Rename workspace';

  @override
  String get newFolder => 'New folder';

  @override
  String get untitledFolderHint => 'Untitled folder';

  @override
  String get homeCrumb => 'Home';

  @override
  String get selectWorkspaceDirectoryTitle => 'Select Workspace Directory';

  @override
  String get editPathTooltip => 'Edit path';

  @override
  String get unableToLoadDirectory => 'Unable to load directory';

  @override
  String get noFolders => 'No folders';

  @override
  String get tooManyFoldersHint =>
      'Too many folders to list; only the beginning is shown.';

  @override
  String get showHiddenFiles => 'Show hidden files';

  @override
  String get pathLabel => 'Path';

  @override
  String get ungroupedLabel => 'Ungrouped';

  @override
  String get openSidebar => 'Open sidebar';

  @override
  String get collapseSidebar => 'Collapse sidebar';

  @override
  String get newSession => 'New session';

  @override
  String get searchSessions => 'Search sessions';

  @override
  String get searchSessionsHint => 'Search sessions...';

  @override
  String get noSessionsYet => 'No sessions yet';

  @override
  String get noMatchingSessions => 'No matching sessions';

  @override
  String get relativeTimeNow => 'now';

  @override
  String relativeTimeMinutes(int minutes) {
    return '${minutes}min';
  }

  @override
  String relativeTimeHours(int hours) {
    return '${hours}h';
  }

  @override
  String relativeTimeDays(int days) {
    return '${days}d';
  }

  @override
  String relativeTimeMonths(int months) {
    return '${months}mo';
  }

  @override
  String relativeTimeYears(int years) {
    return '${years}y';
  }

  @override
  String sessionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions',
      one: '1 session',
    );
    return '$_temp0';
  }

  @override
  String get showLess => 'Show less';

  @override
  String showAll(int count) {
    return 'Show all $count';
  }

  @override
  String get noWorkspacesRegistered => 'No workspaces registered.';

  @override
  String get noWorkspacesRegisteredBody =>
      'Use the Workspaces tab to register a directory first, or choose Default to create an unaccounted session.';

  @override
  String get chooseWorkspaceOrDefault =>
      'Choose a workspace or keep the default.';

  @override
  String get subagentsTitle => 'Subagents';

  @override
  String get selectParentSession => 'Select a parent session';

  @override
  String get noSubagents => 'No subagents';

  @override
  String get loadingSubagents => 'Loading subagents…';

  @override
  String get unableToLoadSubagents => 'Unable to load subagents';

  @override
  String get messageSelectedSubagentHint => 'Message selected subagent';

  @override
  String get sending => 'Sending';

  @override
  String get send => 'Send';

  @override
  String get stopTooltip => 'Stop';

  @override
  String get modeOneShot => 'one-shot';

  @override
  String get modeContinuable => 'continuable';

  @override
  String get activityRunning => 'running';

  @override
  String get activityNotRunning => 'not running';

  @override
  String get diagnosticCorrupt => 'corrupted session record';

  @override
  String get diagnosticUnsupported => 'unsupported subagent record version';

  @override
  String get diagnosticUnavailable => 'session record temporarily unavailable';

  @override
  String get oneShotRecordTitle => 'One-shot subagent record';

  @override
  String get parentUnavailableTitle => 'This subagent is read-only for now';

  @override
  String get oneShotRecordBody =>
      'One-shot tasks do not accept follow-ups; review the full execution record here.';

  @override
  String get parentUnavailableBody =>
      'The parent session is offline; reopen it to continue sending messages.';

  @override
  String backendVersion(String version) {
    return 'v$version';
  }

  @override
  String get outlineTooltip => 'Outline';

  @override
  String get subagentsTooltip => 'Subagents';

  @override
  String get renameSession => 'Rename session';

  @override
  String get forkSession => 'Fork session';

  @override
  String get archiveSession => 'Archive session';

  @override
  String get archiveSessionBody =>
      'The session log and its workspace seat are kept; this row is hidden from all grouping surfaces.';

  @override
  String get archive => 'Archive';

  @override
  String get expandAll => 'Expand all';

  @override
  String get planBadge => 'Plan';

  @override
  String imagePlaceholderSuffix(String name) {
    return ' · $name';
  }

  @override
  String imageLoadingPlaceholder(
    int bytes,
    int height,
    String suffix,
    int width,
  ) {
    return 'image $width×$height ($bytes bytes)$suffix';
  }

  @override
  String get semanticsRunning => 'Running';

  @override
  String get semanticsFailed => 'Failed';

  @override
  String get inputLabel => 'Input';

  @override
  String get outputLabel => 'Output';

  @override
  String get runStatusRunning => 'Running…';

  @override
  String get runStatusDone => 'Done';

  @override
  String get runStatusFailed => 'Failed';

  @override
  String get pauseGoal => 'Pause goal';

  @override
  String get resumeGoal => 'Resume goal';

  @override
  String get clearGoal => 'Clear goal';

  @override
  String get openGoal => 'Open goal';

  @override
  String queuedMessagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count queued messages',
      one: '1 queued message',
    );
    return '$_temp0';
  }

  @override
  String get editQueuedMessageHint => 'Edit queued message';

  @override
  String get saveQueuedMessage => 'Save queued message';

  @override
  String get cancelEdit => 'Cancel editing';

  @override
  String get steer => 'Steer';

  @override
  String get removeQueuedMessage => 'Remove queued message';

  @override
  String approveTool(String tool) {
    return 'Approve tool: $tool';
  }

  @override
  String get allow => 'Allow';

  @override
  String get answer => 'Answer';

  @override
  String get planReview => 'Plan review';

  @override
  String get skipped => 'Skipped';

  @override
  String get answerInstead => 'Answer instead';

  @override
  String get typeYourAnswerHint => 'Type your answer';

  @override
  String get skip => 'Skip';

  @override
  String get questionPrev => 'Previous question';

  @override
  String get questionNext => 'Next question';

  @override
  String get questionCancel => 'Dismiss all questions';

  @override
  String get questionRecommended => 'Recommended';

  @override
  String get questionErrorIncomplete => 'Please complete this question first.';

  @override
  String get questionErrorUnanswered =>
      'Please select an option or enter a custom answer.';

  @override
  String get questionSubmit => 'Submit';

  @override
  String get questionSubmitNext => 'Next';

  @override
  String get planApprove => 'Approve';

  @override
  String get planDecline => 'Refuse';

  @override
  String get planDiscuss => 'Chat about it';

  @override
  String get planPlaceholder => 'describe your task to generate plan';

  @override
  String get messagePlaceholder => 'Message the agent';

  @override
  String removeImage(String name) {
    return 'Remove $name';
  }

  @override
  String get delivery => 'Delivery';

  @override
  String get commandsTooltip => 'Commands';

  @override
  String get searchCommandsHint => 'Search commands';

  @override
  String get noMatchingCommands => 'No matching commands';

  @override
  String get attachImages => 'Attach images';

  @override
  String get pickFromGallery => 'Pick from gallery';

  @override
  String unknownImageType(String name) {
    return 'unknown image type for $name';
  }

  @override
  String beforeFirstTurnHeader(int count) {
    return 'Before first turn · $count messages';
  }

  @override
  String turnHeader(int count, int toolCount, int turn) {
    return 'Turn $turn · $count messages · $toolCount tools';
  }

  @override
  String get contextCompacted => 'Context compacted';

  @override
  String compactedHistoryCount(int count) {
    return 'Compacted $count history items';
  }

  @override
  String get recallLabel => 'Session recall';

  @override
  String get contextInjectionLabel => 'Context injection';

  @override
  String get chatGoalPhaseActive => 'Active';

  @override
  String get chatGoalPhasePaused => 'Paused';

  @override
  String get chatGoalPhaseBlocked => 'Blocked';

  @override
  String get queue => 'Queue';

  @override
  String get thinkLabel => 'Think';

  @override
  String get commandPlanDescription => 'Enter or leave plan mode';

  @override
  String get commandGoalDescription =>
      'set or view the goal for a long-running task';

  @override
  String get commandCompactDescription => 'Compact older conversation history';

  @override
  String get commandPermissionDescription =>
      'Switch the permission preset (sandbox mode + approval policy)';

  @override
  String get commandFeedbackDescription => 'record feedback about this session';

  @override
  String commandImagesUnsupported(String command) {
    return '/$command does not accept image attachments; remove them first';
  }

  @override
  String get parentSession => 'Parent session';

  @override
  String get addWorkspace => 'Add workspace';

  @override
  String get searchTooltip => 'Search';

  @override
  String get namespaceReadOnlyHint =>
      'Host is read-only on this connection; namespace edits are unavailable.';

  @override
  String turnNumberLabel(int turn) {
    return 'Turn $turn';
  }

  @override
  String get attachmentName => 'attachment';

  @override
  String imageRejectionUnsupported(String name, String type) {
    return '$name: unsupported type $type';
  }

  @override
  String imageRejectionTooLarge(String name, int maxBytes) {
    return '$name: exceeds $maxBytes bytes';
  }

  @override
  String imageRejectionNoRoom(int room) {
    return 'Only $room more image(s) allowed per message';
  }

  @override
  String get commandFailed => 'Command failed';

  @override
  String turnFailed(String detail) {
    return 'This turn failed: $detail';
  }

  @override
  String get unknownModelFailure => 'unknown model failure';

  @override
  String get turnStopped => 'Turn stopped';

  @override
  String get turnInterrupted => 'Turn interrupted';

  @override
  String get turnBlocked => 'Turn blocked';

  @override
  String get turnMaxTokens => 'Output token limit reached';

  @override
  String get turnCompleteTitle => 'Turn complete';

  @override
  String get turnCompletionChannel => 'Turn completion';

  @override
  String get turnCompletionChannelDescription =>
      'Notifies when a running conversation turn finishes.';
}
