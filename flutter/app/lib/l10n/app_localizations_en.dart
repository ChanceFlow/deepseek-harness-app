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
  String get noCurrentGoal => 'No current goal';

  @override
  String get goalObjectiveHint => 'Goal objective';

  @override
  String get maxGoalRoundsHint => 'Max goal rounds (optional)';

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Resume';

  @override
  String get clear => 'Clear';

  @override
  String get complete => 'Complete';

  @override
  String get edit => 'Edit';

  @override
  String get goalPhaseActive => 'ACTIVE';

  @override
  String get goalPhasePaused => 'PAUSED';

  @override
  String get goalPhaseBlocked => 'BLOCKED';

  @override
  String get goalPhaseComplete => 'COMPLETE';

  @override
  String goalStatusLine(
    Object max,
    Object phase,
    Object revision,
    Object started,
  ) {
    return '$phase · revision $revision · rounds $started/$max';
  }

  @override
  String contextUsedPercent(Object percent) {
    return '$percent% of context used';
  }

  @override
  String get systemPromptLabel => 'System prompt';

  @override
  String get toolsLabel => 'Tools';

  @override
  String get conversationLabel => 'Conversation';

  @override
  String contextTokens(Object used, Object window) {
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
  String modelCurrent(Object name) {
    return '$name (current)';
  }

  @override
  String get reasoningEffortLabel => 'Reasoning effort';

  @override
  String get todosLabel => 'To-dos';

  @override
  String todoCountDone(Object count) {
    return '$count completed';
  }

  @override
  String todoCountActive(Object count) {
    return '$count active';
  }

  @override
  String todoCountPending(Object count) {
    return '$count pending';
  }

  @override
  String get backgroundJobsTitle => 'Background jobs';

  @override
  String jobCountRunning(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count background jobs running',
      one: '1 background job running',
    );
    return '$_temp0';
  }

  @override
  String jobCount(num count) {
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
  String jobDurationHoursMinutes(Object hours, Object minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String jobDurationMinutesSeconds(Object minutes, Object seconds) {
    return '${minutes}m ${seconds}s';
  }

  @override
  String jobDurationSeconds(Object seconds) {
    return '${seconds}s';
  }

  @override
  String get copyTooltip => 'Copy';

  @override
  String get copiedTooltip => 'Copied';

  @override
  String get waitingForApproval => 'Waiting for approval';

  @override
  String approveToolFallback(Object tool) {
    return 'Approve tool: $tool';
  }

  @override
  String toolRequestsPrivileged(Object tool) {
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
  String accessModeTooltip(Object label) {
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
  String get providerDefault => 'Provider default';

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
  String toolTodoPlanCompleted(Object done, Object total) {
    return '$done/$total completed';
  }

  @override
  String statsTurnsSteps(Object steps, Object turns) {
    return '$turns turns · $steps steps';
  }

  @override
  String statsLlmDuration(Object duration) {
    return 'LLM $duration';
  }

  @override
  String statsToolDuration(Object duration) {
    return 'Tool call $duration';
  }

  @override
  String statsTtftAvg(Object duration) {
    return 'TTFT avg $duration';
  }

  @override
  String statsTokensPerSecond(Object rate) {
    return '$rate tok/s';
  }

  @override
  String statsCacheHit(Object percent) {
    return 'Cache hit $percent%';
  }

  @override
  String statsInputTokens(Object tokens) {
    return 'Input $tokens tok';
  }

  @override
  String statsOutputTokens(Object tokens) {
    return 'Output $tokens tok';
  }

  @override
  String credentialStateUnavailable(Object error) {
    return 'Credential state unavailable: $error';
  }

  @override
  String storeCredentialTitle(Object ref) {
    return 'Store $ref';
  }

  @override
  String namespaceMetaApplies(Object name) {
    return 'applies: $name';
  }

  @override
  String namespaceMetaRevision(Object revision) {
    return 'revision: $revision';
  }

  @override
  String credentialMetaSource(Object source) {
    return 'source: $source';
  }

  @override
  String casRevisionLine(Object revision) {
    return 'CAS revision $revision; host validates against the schema';
  }

  @override
  String newSessionInWorkspace(Object title) {
    return 'New session in $title';
  }

  @override
  String workspaceActionsFor(Object title) {
    return 'Workspace actions for $title';
  }

  @override
  String workspaceNameExists(Object name) {
    return 'A workspace named \"$name\" already exists.';
  }

  @override
  String deleteWorkspaceConfirm(Object name) {
    return 'Delete workspace \"$name\"? Its sessions stay; the connector is removed.';
  }

  @override
  String newFolderIn(Object parent) {
    return 'New folder in \"$parent\"';
  }

  @override
  String secretsSetCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count secrets set',
      one: '1 secret set',
    );
    return '$_temp0';
  }

  @override
  String workspaceSessionCount(num count) {
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
      'Applies only while an agent is running.';

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
      'A preset is the plugin composition one session\'s agent runs — its tools, prompt, and capabilities.';

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
}
