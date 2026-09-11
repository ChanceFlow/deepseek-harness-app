// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'DSH Mobile';

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
  String get reconnect => 'Reconnect';

  @override
  String connectionHostUnreachable(String host) {
    return 'Can\'t reach $host';
  }

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
  String get contextLabel => 'Context';

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
  String get codeStreamingLabel => 'streaming';

  @override
  String get forkFromHere => 'Fork from here';

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
  String thoughtDuration(String duration) {
    return 'Thought $duration';
  }

  @override
  String thinkingDuration(String duration) {
    return 'Thinking · $duration';
  }

  @override
  String exploredFilesAndSearches(int files, int searches) {
    String _temp0 = intl.Intl.pluralLogic(
      files,
      locale: localeName,
      other: 'Explored $files files',
      one: 'Explored 1 file',
    );
    String _temp1 = intl.Intl.pluralLogic(
      searches,
      locale: localeName,
      other: '$searches searches',
      one: '1 search',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String exploredFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Explored $count files',
      one: 'Explored 1 file',
    );
    return '$_temp0';
  }

  @override
  String exploringFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Exploring $count files',
      one: 'Exploring 1 file',
    );
    return '$_temp0';
  }

  @override
  String searchedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count searches',
      one: '1 search',
    );
    return '$_temp0';
  }

  @override
  String modifiedFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Modified $count files',
      one: 'Modified 1 file',
    );
    return '$_temp0';
  }

  @override
  String ranCommands(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ran $count commands',
      one: 'Ran 1 command',
    );
    return '$_temp0';
  }

  @override
  String runningCommands(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Running $count commands',
      one: 'Running 1 command',
    );
    return '$_temp0';
  }

  @override
  String toolGroupOperations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count operations',
      one: '1 operation',
    );
    return '$_temp0';
  }

  @override
  String toolWorkingSteps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count steps',
      one: '1 step',
    );
    return 'Working ($_temp0)';
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
  String sessionActionsFor(String title) {
    return 'Session actions for $title';
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
  String get settingsCategoryApp => 'App';

  @override
  String get settingsCategoryHost => 'Host';

  @override
  String get settingsSectionHost => 'Host & connection';

  @override
  String get settingsSectionApp => 'App preferences';

  @override
  String get settingsSectionChat => 'Chat & agent';

  @override
  String get settingsSectionModels => 'Models & credentials';

  @override
  String get settingsSectionPlugins => 'Plugins & advanced';

  @override
  String get manageHosts => 'Manage';

  @override
  String get appSettingsIntro =>
      'Preferences stored on this device — they apply everywhere, with or without a connected host.';

  @override
  String get languageLabel => 'Language';

  @override
  String get languageDescription =>
      'The app interface language; Follow system tracks the device language.';

  @override
  String get languageOptionSystem => 'Follow system';

  @override
  String get languageOptionZh => '中文';

  @override
  String get languageOptionEn => 'English';

  @override
  String get settingsNavGeneral => 'General';

  @override
  String get settingsNavModels => 'Models';

  @override
  String get settingsNavPlugins => 'Plugins';

  @override
  String get settingsNavPluginSettings => 'Plugin settings';

  @override
  String get settingsNavAgentPresets => 'Agent presets';

  @override
  String get settingsNavCredentials => 'Credentials';

  @override
  String get settingsScopeTitle => 'Choose a host';

  @override
  String get settingsScopeHint =>
      'These settings pages describe the chosen host - independent of the host Chat uses.';

  @override
  String get settingsScopeFollowActive => 'Follow the active host';

  @override
  String get settingsScopeFactsTitle => 'This host';

  @override
  String get settingsLoopbackHint =>
      'settings/credentials are loopback-only on the host; connect via adb reverse';

  @override
  String get setChatHost => 'Set as chat host';

  @override
  String get addBackend => 'Add host';

  @override
  String get editBackend => 'Edit host';

  @override
  String get removeActiveBackendFirst =>
      'Switch away before removing the active host.';

  @override
  String get cannotRemoveLastBackend => 'The last host cannot be removed.';

  @override
  String get backendErrorInvalidJson =>
      'Host configuration file contains invalid JSON.';

  @override
  String get backendErrorMalformedEntry =>
      'Host configuration file contains malformed data.';

  @override
  String backendErrorBadBaseUrl(String baseUrl) {
    return 'Invalid host base URL: $baseUrl';
  }

  @override
  String get backendErrorInvalidBaseUrl => 'Invalid host base URL.';

  @override
  String get backendErrorEmptyList => 'Host configuration list is empty.';

  @override
  String get backendErrorReadFailed =>
      'Failed to read host configuration file.';

  @override
  String get backendErrorWriteFailed =>
      'Failed to save host configuration file.';

  @override
  String get backendErrorEmptyLabel => 'Host label cannot be empty.';

  @override
  String backendErrorUnknownBackend(String id) {
    return 'Unknown host: $id';
  }

  @override
  String get backendErrorUnknown => 'Unknown host.';

  @override
  String get backendErrorLoadFailed => 'Couldn\'t load host configuration.';

  @override
  String get backendErrorDisabled => 'Enable the host before activating it.';

  @override
  String backendErrorDuplicateId(String id) {
    return 'A host with ID “$id” already exists.';
  }

  @override
  String get backendStatusActive => 'Active';

  @override
  String get backendStatusStandby => 'Standby';

  @override
  String get backendStatusDisabled => 'Disabled';

  @override
  String get backendEnableTooltip => 'Enable this host';

  @override
  String get backendDisableTooltip => 'Disable this host';

  @override
  String get hostSettingsUnavailable => 'Host settings unavailable';

  @override
  String get hostSettingsUnavailableBody =>
      'The host did not answer. Repoint it, or choose another host.';

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
  String get settingsSectionPluginInventory => 'Plugin inventory';

  @override
  String get pluginInventoryIntro =>
      'The plugins this host loads and the composition each agent preset builds.';

  @override
  String get pluginInventoryReadOnlyNotice =>
      'Read-only. Enable, disable, and configure plugins on the host.';

  @override
  String get pluginInventorySearchHint => 'Search module name or entry ID';

  @override
  String get pluginInventoryLoading => 'Reading plugins…';

  @override
  String get pluginInventoryEmpty => 'This host exposes no plugins.';

  @override
  String get pluginInventoryNoMatch => 'No plugins match this search.';

  @override
  String get pluginInventoryLoadFailed =>
      'Plugins are temporarily unavailable.';

  @override
  String get pluginInventoryEnabledTag => 'Enabled';

  @override
  String get pluginInventoryDisabledTag => 'Disabled';

  @override
  String get pluginInventoryConditionalTag => 'Conditional';

  @override
  String get pluginInventoryFailedTag => 'Failed';

  @override
  String get pluginInventoryPresetGroupTitle => 'Session plugins';

  @override
  String get pluginInventoryPresetGroupIntro =>
      'Composed per session by agent presets.';

  @override
  String get pluginInventoryGlobalGroupTitle => 'Global plugins';

  @override
  String get pluginInventoryGlobalGroupIntro =>
      'Shared by the system and every session.';

  @override
  String pluginInventoryPluginCount(int count) {
    return '$count plugins';
  }

  @override
  String pluginInventoryFailedCount(int count) {
    return '$count failed';
  }

  @override
  String get pluginInventoryDefaultBadge => 'Default';

  @override
  String get pluginInventoryPresetBrokenLabel => 'Composition unavailable';

  @override
  String get pluginInventoryModuleLabel => 'Module';

  @override
  String get pluginInventoryStatusLabel => 'Status';

  @override
  String get pluginInventoryConditionLabel => 'Disabled when';

  @override
  String get pluginInventoryPhasePending => 'Waiting for dependencies';

  @override
  String get pluginInventoryPhaseLoading => 'Loading';

  @override
  String get pluginInventoryPhaseActive => 'Running';

  @override
  String get pluginInventoryPhaseFailed => 'Failed to start';

  @override
  String get pluginInventoryPhaseUnloading => 'Unloading';

  @override
  String get modelsIntro =>
      'Enter your API keys to use models from the following providers.';

  @override
  String get settingsReadOnlyNotice =>
      'The settings document is read-only in this deployment.';

  @override
  String get modelsFooter =>
      'Provider credentials live on the host; the Providers page adds, keys, and removes them from this device.';

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
  String get backendBaseUrlHint => 'http://127.0.0.1:3080';

  @override
  String get baseUrlDerivationHint =>
      'RPC and event paths derive from this base.';

  @override
  String get baseUrlValidHint =>
      'http or https with a host, e.g. http://127.0.0.1:3080';

  @override
  String get backendTrustCertificateTitle => 'Trust this host\'s certificate';

  @override
  String get backendTrustCertificateDescription =>
      'Accept this host\'s TLS certificate even when Android cannot verify it — for a self-signed or internal-CA gateway. Only this host is affected, and anyone who can intercept the connection could impersonate it. Leave off unless you control the gateway.';

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
  String get sessionMenuTooltip => 'Session menu';

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
  String get diffLabel => 'Diff';

  @override
  String get viewDiff => 'Diff';

  @override
  String get viewFullFile => 'Full file';

  @override
  String get outputLabel => 'Output';

  @override
  String get runStatusRunning => 'Running…';

  @override
  String get turnStatusWorking => 'Deep diving…';

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
  String get steeringPending => 'Steering';

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
  String get attachImages => 'Attach images';

  @override
  String get pickFromGallery => 'Pick from gallery';

  @override
  String unknownImageType(String name) {
    return 'unknown image type for $name';
  }

  @override
  String beforeFirstTurnHeader(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: '1 message',
    );
    return 'Before first turn · $_temp0';
  }

  @override
  String turnHeader(int count, int toolCount, int turn) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: '1 message',
    );
    String _temp1 = intl.Intl.pluralLogic(
      toolCount,
      locale: localeName,
      other: '$toolCount tools',
      one: '1 tool',
    );
    return 'Turn $turn · $_temp0 · $_temp1';
  }

  @override
  String turnFailedCount(int count) {
    return '$count failed';
  }

  @override
  String get contextCompacted => 'Context compacted';

  @override
  String get compactionRunning => 'Compacting context…';

  @override
  String compactionCompleted(int items, int tokens) {
    return 'Compacted $items history items (~$tokens tokens)';
  }

  @override
  String get compactionViewSummary => 'View compaction summary';

  @override
  String get compactionSummaryUnavailable => 'Compaction summary unavailable';

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
  String get chatLoadOlder => 'Load earlier';

  @override
  String get chatLoadingOlder => 'Loading earlier…';

  @override
  String get chatBeginningOfHistory => 'Beginning of conversation';

  @override
  String get chatLoadOlderRetry =>
      'Couldn\'t load earlier messages. Tap to retry.';

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
  String get commandExportDescription =>
      'Download this session log as a ZIP archive';

  @override
  String get sessionLogExportTooltip => 'Download session log';

  @override
  String sessionLogExportSaved(String location) {
    return 'Session log saved to $location';
  }

  @override
  String get sessionLogExportFailed => 'Couldn\'t export the session log';

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

  @override
  String get otherTurnCompleteTitle => 'New turn in another session';

  @override
  String get approvalRequestedTitle => 'Approval requested';

  @override
  String get planReviewRequestedTitle => 'Plan review requested';

  @override
  String get approvalChannel => 'Approvals';

  @override
  String get approvalChannelDescription =>
      'Notifies when a session waits on your approval.';

  @override
  String get planReviewChannel => 'Plan reviews';

  @override
  String get planReviewChannelDescription =>
      'Notifies when a session waits on your plan review.';

  @override
  String get notificationDismissTooltip => 'Dismiss notification';

  @override
  String get workingChannel => 'Working sessions';

  @override
  String get workingChannelDescription =>
      'Shows a silent, persistent notice while a session is working or waiting on you.';

  @override
  String get workingNotificationBody => 'Working…';

  @override
  String get waitingApprovalBody => 'Waiting for your approval';

  @override
  String get waitingPlanReviewBody => 'Waiting for your plan review';

  @override
  String get waitingAnswerBody => 'Waiting for your answer';

  @override
  String get jumpToBottomTooltip => 'Jump to bottom';

  @override
  String get settingsSectionAsr => 'Voice recognition';

  @override
  String get asrModelsTitle => 'ASR Models';

  @override
  String get asrModelsDescription =>
      'Download and manage on-device speech recognition models for offline voice input.';

  @override
  String asrInstalledCount(int installed, int total) {
    return '$installed/$total installed';
  }

  @override
  String get asrDefaultSource => 'Default download source';

  @override
  String get asrDefaultSourceDesc => 'Choose preferred model mirror repository';

  @override
  String get asrAllowCellular => 'Allow cellular downloads';

  @override
  String get asrAllowCellularDesc =>
      'Download models over mobile data (may incur carrier data fees)';

  @override
  String get asrRuntimeTitle => 'On-device engine';

  @override
  String get asrRuntimeDesc =>
      'Speech recognition runs locally with sherpa-onnx. The engine is downloaded during setup instead of shipping inside the APK, which keeps the download small.';

  @override
  String get asrRuntimeReady => 'Installed';

  @override
  String asrRuntimeProgress(String size, int percent) {
    return '$size · $percent%';
  }

  @override
  String get asrRuntimeFailed => 'Install failed';

  @override
  String asrRuntimeSize(String version, String size) {
    return '$version · $size to download';
  }

  @override
  String get asrRuntimeUnavailable => 'Not available for this device';

  @override
  String get asrRuntimeInstall => 'Install engine';

  @override
  String get asrRuntimeDelete => 'Delete engine';

  @override
  String get voiceInputNoRuntimeTitle => 'Speech Engine Required';

  @override
  String get voiceInputNoRuntimeBody =>
      'Install the on-device speech engine in Settings → Voice input to use offline voice input.';

  @override
  String get voiceInputRuntimeNotInstalled =>
      'The on-device speech engine isn\'t installed. Install it in Settings → Voice input.';

  @override
  String get asrModelStatusIdle => 'Not downloaded';

  @override
  String get asrModelStatusDownloading => 'Downloading';

  @override
  String get asrModelStatusDownloaded => 'Installed';

  @override
  String get asrModelStatusFailed => 'Download failed';

  @override
  String get asrModelStatusCanceled => 'Canceled';

  @override
  String get asrModelDiscontinued => 'Discontinued · local copy only';

  @override
  String get asrDownloadButton => 'Download';

  @override
  String get asrCancelButton => 'Cancel';

  @override
  String get asrDeleteButton => 'Delete';

  @override
  String get asrRetryButton => 'Retry';

  @override
  String asrSwitchSourceRetry(String source) {
    return 'Retry from $source';
  }

  @override
  String get asrDeleteConfirmTitle => 'Delete model';

  @override
  String asrDeleteConfirmBody(String modelName) {
    return 'Are you sure you want to delete $modelName? You can download it again anytime.';
  }

  @override
  String asrDiskUsage(String size) {
    return 'Disk: $size';
  }

  @override
  String asrSourceLabel(String source) {
    return 'Source: $source';
  }

  @override
  String get asrLanguagesLabel => 'Languages';

  @override
  String get asrLicenseLabel => 'License';

  @override
  String asrSpeedLabel(String speed) {
    return '$speed/s';
  }

  @override
  String get voiceInputTooltip => 'Voice input';

  @override
  String get voiceInputNoModelTitle => 'Speech Model Required';

  @override
  String get voiceInputNoModelBody =>
      'Download an on-device speech recognition model in Settings to enable offline voice input.';

  @override
  String get voiceInputGoToSettings => 'Go to Settings';

  @override
  String get voiceInputCancel => 'Cancel';

  @override
  String get voiceInputDone => 'Done';

  @override
  String get voiceInputSlideToSend => 'Release to send · slide up to cancel';

  @override
  String get voiceInputReleaseToCancel => 'Release to cancel';

  @override
  String get voiceInputTapToFinish => 'Tap the mic to finish';

  @override
  String get voiceInputInitializing => 'Getting ready…';

  @override
  String get voiceInputFinalizing => 'Transcribing…';

  @override
  String get voiceInputPermissionDenied =>
      'Microphone permission is required for voice input.';

  @override
  String get voiceInputRecordFailed =>
      'Voice recording could not start. Check that your microphone is available and try again.';

  @override
  String get voiceInputSilentInput =>
      'No audio signal detected from the microphone. Check the mic access toggle and that no other app is using it.';

  @override
  String get voiceInputInputFailed =>
      'Voice input stopped unexpectedly. Please try again.';

  @override
  String get voiceInputModelUnsupported =>
      'The selected speech model is not supported. Pick another installed model in Settings.';

  @override
  String get asrActiveModel => 'Active speech model';

  @override
  String get asrActiveModelDesc =>
      'Model used for voice transcription in chat.';

  @override
  String get asrNoModelInstalled => 'None (download a model below)';

  @override
  String get asrVoiceInputModeTitle => 'Voice input mode';

  @override
  String get asrVoiceInputModeDesc =>
      'Choose whether speech recognition runs on-device or via an online speech service.';

  @override
  String get asrVoiceInputModeOffline => 'On-device';

  @override
  String get asrVoiceInputModeOnline => 'Online';

  @override
  String get asrOnlineProviderVolcengine => 'Volcengine · Doubao';

  @override
  String get asrOnlineProviderVolcengineHint =>
      'Doubao streaming speech recognition, authenticated with an X-Api-Key.';

  @override
  String get asrOnlineProviderTencent => 'Tencent Cloud · Hunyuan';

  @override
  String get asrOnlineProviderTencentHint =>
      'Real-time speech recognition Hy-ASR-3.0-preview, authenticated with signed credentials.';

  @override
  String get asrOnlineVolcengineApiKeyLabel => 'API Key';

  @override
  String get asrOnlineVolcengineApiKeyHint =>
      'From the Volcengine speech console';

  @override
  String get asrOnlineTencentAppIdLabel => 'AppID';

  @override
  String get asrOnlineTencentSecretIdLabel => 'SecretId';

  @override
  String get asrOnlineTencentSecretKeyLabel => 'SecretKey';

  @override
  String get asrOnlineEndpointLabel => 'Endpoint (optional)';

  @override
  String get asrOnlineTencentLimit =>
      'The Hunyuan preview accepts 16 kHz mono PCM only and recognizes at most 1 minute per session.';

  @override
  String get asrOnlinePrivacyNote =>
      'Keys are stored on this device only; audio is sent only to the selected provider.';

  @override
  String get asrOnlineSaved => 'Voice input settings saved';

  @override
  String get voiceInputCloudSetupTitle => 'Online Speech Setup Required';

  @override
  String get voiceInputCloudSetupBody =>
      'Add your online speech service credentials in Settings to enable online voice input.';

  @override
  String get voiceInputCloudNotConfigured =>
      'Online voice input needs credentials. Add them in Settings → Speech recognition.';

  @override
  String get voiceInputCloudConnectFailed =>
      'Could not reach the online speech service. Check your network and credentials, then try again.';

  @override
  String get voiceInputCloudFailed =>
      'Online speech recognition failed. Check your credentials and try again.';

  @override
  String get errorLogsTitle => 'Error Logs';

  @override
  String get errorLogsDescription => 'View and export application error logs';

  @override
  String get errorLogsEmptyTitle => 'No Error Logs';

  @override
  String get errorLogsEmptySubtitle =>
      'Application is running smoothly with no errors captured.';

  @override
  String get errorLogsFilterAll => 'All';

  @override
  String get errorLogsFilterFatal => 'Fatal';

  @override
  String get errorLogsFilterError => 'Error';

  @override
  String get errorLogsFilterWarn => 'Warning';

  @override
  String get errorLogsSearchHint => 'Search errors or stack trace…';

  @override
  String get errorLogsCopyAll => 'Copy All';

  @override
  String get errorLogsCopyAllSuccess => 'All error logs copied to clipboard';

  @override
  String get errorLogsCopyEntry => 'Copy';

  @override
  String get errorLogsCopyEntrySuccess => 'Error details copied to clipboard';

  @override
  String get errorLogsClear => 'Clear';

  @override
  String get errorLogsClearConfirmTitle => 'Clear Error Logs';

  @override
  String get errorLogsClearConfirmMessage =>
      'Are you sure you want to clear all recorded error logs? This cannot be undone.';

  @override
  String get errorLogsClearSuccess => 'Error logs cleared';

  @override
  String get errorLogsStackTrace => 'Stack Trace';

  @override
  String get errorLogsBreadcrumbs => 'Related Logs';

  @override
  String get errorLogsContext => 'Context';

  @override
  String get errorLogsSystemInfo => 'System & Build Info';

  @override
  String get errorLogsCopySystemInfo => 'Copy System Info';

  @override
  String get errorLogsSystemInfoCopied => 'System info copied to clipboard';

  @override
  String errorLogsCountBadge(int count) {
    return '$count errors';
  }

  @override
  String get errorLogsNoSearchResults => 'No errors match your filter.';

  @override
  String get previewFile => 'Preview';

  @override
  String get copyPath => 'Copy path';

  @override
  String get copyContent => 'Copy content';

  @override
  String get copiedFeedback => 'Copied to clipboard';

  @override
  String get filePreviewFailed => 'Failed to load file preview';

  @override
  String get filePreviewBinary =>
      'This file isn\'t text, so it can\'t be previewed.';

  @override
  String get filePreviewEmpty => 'This file is empty.';

  @override
  String filePreviewTruncated(int count) {
    return 'Previewing first $count lines';
  }

  @override
  String get sessionAlreadyOwnedError =>
      'This session is currently locked by another process or CLI.';

  @override
  String get chatActionFailed => 'That action couldn\'t be completed.';

  @override
  String get sessionAgentFailed => 'The agent stopped with an error.';

  @override
  String get chatLoadFailed => 'Couldn\'t load this conversation.';

  @override
  String get systemPromptUpdated => 'System prompt updated';

  @override
  String get trajectoryTitle => 'Trajectory';

  @override
  String get trajectorySearchHint => 'Search ledger';

  @override
  String get trajectorySearchClear => 'Clear search';

  @override
  String trajectorySearchMatches(int matches, int total) {
    return '$matches of $total';
  }

  @override
  String get trajectoryLoadOlder => 'Load older history';

  @override
  String get trajectoryLoadingOlder => 'Loading older history…';

  @override
  String get trajectoryLoadOlderFailed =>
      'Couldn\'t load older history. Try again.';

  @override
  String get trajectoryNoMatches =>
      'No records match this search in the loaded window.';

  @override
  String get trajectoryEmpty => 'This session has no trajectory records yet.';

  @override
  String get trajectoryBeforeFirstTurn => 'Before the first turn';

  @override
  String trajectoryTurnLabel(int turn) {
    return 'Turn $turn';
  }

  @override
  String trajectoryTurnSummary(int records, int tools) {
    String _temp0 = intl.Intl.pluralLogic(
      records,
      locale: localeName,
      other: '$records records',
      one: '1 record',
    );
    String _temp1 = intl.Intl.pluralLogic(
      tools,
      locale: localeName,
      other: '$tools tools',
      one: '1 tool',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String trajectoryStepLabel(int step) {
    return 'Step $step';
  }

  @override
  String trajectoryStepRecordCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count records',
      one: '1 record',
    );
    return '$_temp0';
  }

  @override
  String get trajectoryKindUser => 'User';

  @override
  String get trajectoryKindContext => 'Context';

  @override
  String get trajectoryKindAssistant => 'Assistant';

  @override
  String get trajectoryKindTool => 'Tool';

  @override
  String get trajectoryKindCompaction => 'Compacted';

  @override
  String get trajectoryKindCommand => 'Command';

  @override
  String get trajectoryKindError => 'Error';

  @override
  String get trajectoryStatusStreaming => 'Streaming';

  @override
  String get trajectoryFactTurn => 'Turn';

  @override
  String get trajectoryFactStep => 'Step';

  @override
  String get trajectoryFactKind => 'Kind';

  @override
  String get trajectoryFactStatus => 'Status';

  @override
  String get trajectoryFactStarted => 'Started';

  @override
  String get trajectoryFactFirstToken => 'First token';

  @override
  String get trajectoryFactDuration => 'Duration';

  @override
  String get trajectoryFactParentCall => 'Parent call';

  @override
  String get trajectoryFactOutsideStep => 'Outside a step';

  @override
  String get trajectoryFactUnavailable => 'Unavailable';

  @override
  String get trajectoryTimingNotRecorded => 'Not recorded';

  @override
  String get trajectoryDurationNotRecorded =>
      'The session log carries no settle timestamp for this record.';

  @override
  String get trajectoryUsageSection => 'Token usage';

  @override
  String get trajectoryUsageNotReported =>
      'The host reported no usage for this record.';

  @override
  String get trajectoryUsageInput => 'Input';

  @override
  String get trajectoryUsageCachedRead => 'Cache read';

  @override
  String get trajectoryUsageCacheWrite => 'Cache write';

  @override
  String get trajectoryUsageOutput => 'Output';

  @override
  String get trajectoryUsageReasoning => 'Reasoning';

  @override
  String get trajectoryInputSection => 'Input';

  @override
  String get trajectoryOutputSection => 'Output';

  @override
  String trajectoryTokenCount(int value) {
    return '$value tok';
  }

  @override
  String trajectoryTurnUsage(String input, String output) {
    return 'in $input · out $output';
  }

  @override
  String get trajectoryEntryTooltip => 'Trajectory';

  @override
  String get settingsSectionProviders => 'Providers';

  @override
  String get providersIntro =>
      'Add a provider, enter its API key, and discover the models it serves.';

  @override
  String get providersReadOnlyNotice =>
      'The settings document is read-only in this deployment.';

  @override
  String providersLoadFailed(String error) {
    return 'Couldn\'t load providers: $error';
  }

  @override
  String providerCredentialUnavailable(String error) {
    return 'Credential state unavailable: $error';
  }

  @override
  String get providerStateLive => 'Live';

  @override
  String get providerStateDormant => 'Dormant';

  @override
  String get providerDeclared => 'Hand-declared';

  @override
  String providerNeedsRepair(String error) {
    return 'Needs repair: $error';
  }

  @override
  String get providersEmpty => 'No configurable providers on this host.';

  @override
  String get addProvider => 'Add provider';

  @override
  String get addProviderFamilyLabel => 'Settings family';

  @override
  String get addProviderRouteLabel => 'Route id';

  @override
  String get addProviderRouteHint => 'acme-gateway';

  @override
  String get addProviderRouteInvalid =>
      'Use lower-case letters, digits, and single hyphens, starting with a letter.';

  @override
  String get addProviderRouteTaken => 'That route already exists.';

  @override
  String get addProviderDisplayNameLabel => 'Display name (optional)';

  @override
  String get addProviderBaseUrlLabel => 'Base URL (optional)';

  @override
  String get addProviderBaseUrlInvalid => 'Enter an http:// or https:// URL.';

  @override
  String get addProviderProtocolLabel => 'Protocol (optional)';

  @override
  String get addProviderModelsLabel => 'Model ids, one per line (optional)';

  @override
  String get addProviderModelsHint =>
      'A route the adapter does not already know needs at least one.';

  @override
  String providerRouteLine(String route) {
    return 'Route $route';
  }

  @override
  String providerKeyRefLine(String ref) {
    return 'Key reference $ref';
  }

  @override
  String get providerKeyHint =>
      'The value goes to the host credential store and is never shown again.';

  @override
  String get providerRemoveAction => 'Remove provider';

  @override
  String providerRemoveConfirm(String name) {
    return 'Remove $name?';
  }

  @override
  String get providerRemoveBody =>
      'The stored profile is removed. A stored API key is left in place.';

  @override
  String get discoverModels => 'Discover models';

  @override
  String get discoverModelsEmpty => 'The endpoint advertised no models.';

  @override
  String discoverModelsFailed(String error) {
    return 'Model discovery failed: $error';
  }

  @override
  String get discoveredModelsTitle => 'Advertised models';

  @override
  String modelContextWindowLine(int tokens) {
    return 'Context $tokens';
  }

  @override
  String modelMaxTokensLine(int tokens) {
    return 'Max output $tokens';
  }

  @override
  String get providerFooter =>
      'Provider routes and profiles live in the host settings document; keys ride the host credential plane.';

  @override
  String get settingsSectionAbout => 'About';

  @override
  String get aboutVersionLabel => 'App version';

  @override
  String aboutVersionLine(String version, String build) {
    return '$version (build $build)';
  }

  @override
  String get aboutDocs => 'Documentation';

  @override
  String get aboutFeedback => 'Report a bug or send feedback';

  @override
  String get aboutLinkFailed => 'Couldn\'t open that link.';

  @override
  String get producedFilesLabel => 'Files changed';

  @override
  String producedFilesMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return '+ $_temp0';
  }

  @override
  String producedFilesOpen(String name) {
    return 'Open $name';
  }

  @override
  String messageTokensPerSecond(String tps) {
    return '$tps tok/s';
  }

  @override
  String messageTokenUsage(String tokens) {
    return '$tokens tok';
  }

  @override
  String get settingsAppearanceTitle => 'Appearance';

  @override
  String get settingsAppearanceLight => 'Light';

  @override
  String get settingsAppearanceDark => 'Dark';

  @override
  String get settingsAppearanceOled => 'OLED';

  @override
  String get settingsAppearanceSystem => 'System';

  @override
  String get settingsAppearanceUnavailable =>
      'Host theme settings are unavailable.';

  @override
  String get settingsValueUnavailable => 'Unavailable';

  @override
  String get settingsAppearanceSaveFailed => 'Couldn\'t save the theme choice.';

  @override
  String get cordisApprovalHeader => 'Plugin approval';

  @override
  String get cordisPurposeLabel => 'Purpose';

  @override
  String get cordisPluginIdLabel => 'Plugin ID';

  @override
  String get cordisPackageIdLabel => 'Package ID';

  @override
  String get cordisModeRun => 'Run';

  @override
  String get cordisModeUpdate => 'Update';

  @override
  String get cordisRejectOnlyNotice =>
      'This phone can only reject: approving needs the browser plugin runtime that reports the activation it created, and this client doesn\'t have one. Rejecting releases the blocked tool call and runs neither half.';

  @override
  String get cordisAnswerFailed =>
      'The host didn\'t accept the plugin decision.';

  @override
  String get backendTestConnection => 'Test connection';

  @override
  String get backendProbeRunning => 'Testing connection…';

  @override
  String get backendProbeReachable =>
      'Reachable. The host answered the dsh contract.';

  @override
  String get backendProbeUnreachable =>
      'No dsh answered at this address. Check the base URL, that the gateway is running, and that this phone can reach it.';

  @override
  String get backendProbeCertificateNotTrusted =>
      'TLS handshake failed. The host\'s certificate is not trusted — if you control this gateway, turn on “Trust this host\'s certificate” above.';

  @override
  String get backendProbeAuthenticationRequired =>
      'The gateway requires pairing or credentials this client does not have (deployment authentication, or the URL token dsh web prints). This client performs no authentication.';

  @override
  String get backendProbeNotDshSurface =>
      'Something answered, but it is not a dsh host: there is no dsh RPC route at this address.';

  @override
  String backendProbeUnexpectedStatus(int status) {
    return 'The host answered HTTP $status, which the dsh contract does not use.';
  }

  @override
  String get backendProbeUnenvelopedResponse =>
      'The host answered, but not with a dsh JSON-RPC response.';

  @override
  String get backendProbeUnknown =>
      'Could not classify the connection failure.';

  @override
  String get backendProbeAmbiguousTls =>
      'The failure was a TLS handshake error; it may be a certificate the system rejects or another TLS mismatch.';

  @override
  String get backendProbeSaveNotBlocked =>
      'Saving is not blocked — a host can be offline while you configure it.';

  @override
  String workflowMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
    );
    return '$_temp0';
  }

  @override
  String get workflowRunEmpty => 'No members started';

  @override
  String get workflowPhaseUnassigned => 'Unphased';

  @override
  String get workflowPhaseEmpty => 'Empty phase name';

  @override
  String get workflowMemberEmpty => 'Empty member name';

  @override
  String workflowMemberOpen(String name) {
    return 'Open $name';
  }

  @override
  String get workflowStatusRunning => 'Running';

  @override
  String get workflowStatusCompleted => 'Completed';

  @override
  String get workflowStatusFailed => 'Failed';

  @override
  String get workflowStatusCancelled => 'Cancelled';

  @override
  String get workflowStatusInterrupted => 'Interrupted';

  @override
  String workflowStatusCountRunning(int count) {
    return 'Running $count';
  }

  @override
  String workflowStatusCountCompleted(int count) {
    return 'Completed $count';
  }

  @override
  String workflowStatusCountFailed(int count) {
    return 'Failed $count';
  }

  @override
  String workflowStatusCountCancelled(int count) {
    return 'Cancelled $count';
  }

  @override
  String workflowStatusCountInterrupted(int count) {
    return 'Interrupted $count';
  }

  @override
  String get hookAuditPending => 'Pending';

  @override
  String hookAuditDecision(String decision) {
    return '$decision';
  }

  @override
  String hookAuditDurationMs(int durationMs) {
    return '$durationMs ms';
  }

  @override
  String get hookAuditPoint => 'Point';

  @override
  String get hookAuditDialect => 'Dialect';

  @override
  String get hookDialectClaudeCode => 'Claude Code';

  @override
  String get hookDialectCodex => 'Codex';

  @override
  String get hookAuditMatcher => 'Matcher';

  @override
  String get hookAuditDecisionLabel => 'Decision';

  @override
  String get hookAuditExitCode => 'Exit code';

  @override
  String get hookAuditUnknown => 'Not reported';

  @override
  String get hookAuditStderr => 'Stderr';

  @override
  String get hookAuditNoStderr => 'None';

  @override
  String get sandboxModeUnknownTooltip =>
      'This session has not reported its sandbox mode. The host\'s deployment default applies.';

  @override
  String sandboxModeTooltip(String mode) {
    return 'Sandbox: $mode';
  }

  @override
  String get sandboxModeReadOnly => 'Read only';

  @override
  String get sandboxModeWorkspaceWrite => 'Workspace write';

  @override
  String get sandboxModeDangerFullAccess => 'Full access';

  @override
  String get scheduleStripTitle => 'Reminders';

  @override
  String scheduleReminderCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reminders',
      one: '1 reminder',
    );
    return '$_temp0';
  }

  @override
  String get scheduleUnknown => 'Not reported by this host';

  @override
  String get scheduleEmpty => 'None active';

  @override
  String scheduleNextAt(String at) {
    return 'Next $at';
  }

  @override
  String scheduleOverdueCount(int count) {
    return '$count overdue';
  }

  @override
  String scheduleMoreCount(int count) {
    return '+$count more';
  }

  @override
  String get scheduleFrequencyOnce => 'Once';

  @override
  String scheduleFrequencyEvery(int value, String unit) {
    return 'Every $value $unit';
  }

  @override
  String get scheduleUnitDay => 'day';

  @override
  String get scheduleUnitDays => 'days';

  @override
  String get scheduleUnitHour => 'hour';

  @override
  String get scheduleUnitHours => 'hours';

  @override
  String get scheduleUnitMinute => 'minute';

  @override
  String get scheduleUnitMinutes => 'minutes';

  @override
  String get scheduleUnitSecond => 'second';

  @override
  String get scheduleUnitSeconds => 'seconds';

  @override
  String get keepAliveChannelName => 'Background connection';

  @override
  String get keepAliveChannelDescription =>
      'Keeps the connection to your host open while agent work is in flight.';

  @override
  String get keepAliveNotificationTitle => 'Keeping your session connected';

  @override
  String get keepAliveNotificationBody =>
      'Agent work continues in the background; you will be notified when it finishes.';

  @override
  String get batteryOptimizationTitle => 'Background connection';

  @override
  String get batteryOptimizationNotExemptBody =>
      'Android can suspend this app\'s network and close the connection while the screen is off. Allow background running so agent work keeps its connection.';

  @override
  String get batteryOptimizationExemptBody =>
      'Background running is allowed, so the system will not suspend the connection while agent work is in flight.';

  @override
  String get batteryOptimizationAllowAction => 'Allow';

  @override
  String get batteryOptimizationRequestFailed =>
      'Could not open the battery optimization dialog on this device.';
}
