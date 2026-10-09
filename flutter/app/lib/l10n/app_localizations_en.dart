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
  String get teamPanelTitle => 'Agent team';

  @override
  String get teamRosterHeading => 'Members';

  @override
  String get teamTasksHeading => 'Shared tasks';

  @override
  String get teamTaskBoardEmpty => 'No shared tasks yet';

  @override
  String get teamCurrentChat => 'Current chat';

  @override
  String get teamOpenMember => 'Open conversation';

  @override
  String get teamMemberRunning => 'running';

  @override
  String get teamMemberInactive => 'inactive';

  @override
  String get teamMemberProvisioning => 'provisioning';

  @override
  String get teamMemberFailed => 'failed';

  @override
  String get teamTaskPending => 'pending';

  @override
  String get teamTaskInProgress => 'in progress';

  @override
  String get teamTaskCompleted => 'completed';

  @override
  String teamTaskOwner(String name) {
    return 'Owner: $name';
  }

  @override
  String get teamTaskUnowned => 'unowned';

  @override
  String get teamTaskReady => 'ready';

  @override
  String get teamTaskBlocked => 'blocked';

  @override
  String teamTaskBlockedBy(String ids) {
    return 'Blocked by: $ids';
  }

  @override
  String teamTaskWriteScopes(String scopes) {
    return 'Write scopes: $scopes';
  }

  @override
  String get teamTaskShowMore => 'Show more';

  @override
  String get teamTaskShowLess => 'Show less';

  @override
  String teamFailure(String message) {
    return 'Invalid persisted team record: $message';
  }

  @override
  String get settingsNavPluginManager => 'Plugin manager';

  @override
  String get pluginManagerIntro =>
      'Install bundles on the host, switch them and the plugins they compose on or off, and remove what you added.';

  @override
  String get pluginManagerEmpty => 'No bundles to manage on this host.';

  @override
  String get pluginManagerUnavailable =>
      'This host composes no plugin manager, so plugins cannot be managed from here.';

  @override
  String get pluginManagerAdd => 'Add plugin';

  @override
  String get pluginManagerSearchHint => 'Search bundles';

  @override
  String get pluginManagerBetaTag => 'Beta';

  @override
  String get pluginManagerProblemTag => 'Problem';

  @override
  String get pluginManagerReadOnlyManagement =>
      'Managed by the profile; change it on the host.';

  @override
  String get pluginManagerReadOnlyAddress =>
      'Not addressable through the profile patch.';

  @override
  String get pluginManagerUninstall => 'Uninstall';

  @override
  String pluginManagerUninstallTitle(String name) {
    return 'Uninstall $name?';
  }

  @override
  String get pluginManagerUninstallBody =>
      'The host removes the package and its files. This cannot be undone from here.';

  @override
  String pluginManagerRowsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count plugins',
      one: '1 plugin',
    );
    return '$_temp0';
  }

  @override
  String get pluginExemptionsTitle => 'Version exemptions';

  @override
  String get pluginExemptionsIntro =>
      'Packages this host has been told to run despite a version mismatch. Granting one accepts possible crashes and data loss.';

  @override
  String get pluginExemptionsEmpty =>
      'No package is exempt from the version check.';

  @override
  String get pluginExemptionsRevoke => 'Revoke';

  @override
  String get pluginInstallChecking => 'Checking the spec';

  @override
  String get pluginInstallStarting => 'Starting the installation';

  @override
  String get pluginInstallRunning => 'Installing';

  @override
  String get pluginInstallCancelling => 'Cancelling';

  @override
  String get pluginInstallApplying => 'Applying the change';

  @override
  String get pluginInstallUnconfirmed =>
      'The host never confirmed the result; reopen the plugin list to see what happened.';

  @override
  String get pluginInstallDone => 'Installed';

  @override
  String get pluginInstallFailed => 'Installation failed';

  @override
  String get pluginInstallApproveBuilds => 'Allow these scripts and retry';

  @override
  String get pluginInstallEnableNow => 'Enable now';

  @override
  String get pluginInstallRestartRequired =>
      'Restart the host for this to take effect.';

  @override
  String get pluginInstallSpecHint => 'Package name, path, git URL, or tarball';

  @override
  String get pluginInstallRegistry => 'Registry';

  @override
  String get pluginInstallAction => 'Install';

  @override
  String get automationTasksTitle => 'Automation tasks';

  @override
  String get automationTasksIntro =>
      'Reminders the host schedules for a session. They are created by asking the agent; here you can review, edit, and delete them.';

  @override
  String get automationTasksUnavailable =>
      'This host composes no scheduler, so scheduled tasks cannot be managed from here.';

  @override
  String get automationTasksEmpty => 'No scheduled task on this host.';

  @override
  String get automationTasksNoMatches => 'No task matches this search.';

  @override
  String get automationTasksSearchHint => 'Search tasks';

  @override
  String get automationTasksFilterAll => 'All';

  @override
  String get automationTasksFilterEnabled => 'Enabled';

  @override
  String get automationTasksFilterInactive => 'Inactive';

  @override
  String get automationTaskStatusInactive => 'inactive';

  @override
  String automationTaskNextRun(String target) {
    return 'next $target';
  }

  @override
  String get automationTaskRules => 'Rules';

  @override
  String get automationTaskRecords => 'Records';

  @override
  String get automationTaskName => 'Name';

  @override
  String get automationTaskInstruction => 'Instruction';

  @override
  String get automationTaskFrequency => 'Repeat';

  @override
  String get automationTaskNext => 'Next run';

  @override
  String get automationTaskId => 'Task id';

  @override
  String get automationTaskLastDelivery => 'Last delivery';

  @override
  String get automationTaskEdit => 'Edit';

  @override
  String get automationTaskSaved => 'Saved.';

  @override
  String get automationTaskConflict =>
      'This task changed elsewhere; reopen it and try again.';

  @override
  String get automationTaskEnded =>
      'This task has ended and can only be replaced by a new one.';

  @override
  String get automationTaskMissing => 'This task no longer exists.';

  @override
  String get automationTaskError => 'The host refused the change.';

  @override
  String get automationTaskDelete => 'Delete';

  @override
  String automationTaskDeleteTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get automationTaskDeleteBody =>
      'The task and its saved delivery records are removed from the host.';

  @override
  String get automationTaskRecordsEmpty => 'No delivery has been recorded yet.';

  @override
  String get automationTaskLoadOlder => 'Load older records';

  @override
  String get automationTaskCursorError =>
      'That page of records is gone; reopen the task.';

  @override
  String get automationTaskNotFound => 'The task is no longer on the host.';

  @override
  String get automationTaskLegacyRecord => 'Prompt not retained';

  @override
  String automationTaskRetention(int days, int records) {
    return 'Only the last $days days or $records records are kept.';
  }

  @override
  String get automationTaskEarlierUnavailable =>
      'Earlier records may be missing.';

  @override
  String automationFrequencyOnce(String target) {
    return 'Once, at $target';
  }

  @override
  String automationFrequencyEvery(int seconds) {
    return 'Every $seconds seconds';
  }

  @override
  String automationFrequencyDaily(String time, String zone) {
    return 'Daily at $time ($zone)';
  }

  @override
  String automationFrequencyWeekly(String days, String time, String zone) {
    return '$days at $time ($zone)';
  }

  @override
  String automationFrequencyCron(String expression, String zone) {
    return 'Cron $expression ($zone)';
  }

  @override
  String get automationWeekdayMon => 'Mon';

  @override
  String get automationWeekdayTue => 'Tue';

  @override
  String get automationWeekdayWed => 'Wed';

  @override
  String get automationWeekdayThu => 'Thu';

  @override
  String get automationWeekdayFri => 'Fri';

  @override
  String get automationWeekdaySat => 'Sat';

  @override
  String get automationWeekdaySun => 'Sun';

  @override
  String get scheduleEditRepeat => 'Repeat';

  @override
  String get scheduleKindOnce => 'Once';

  @override
  String get scheduleKindEvery => 'Every interval';

  @override
  String get scheduleKindDaily => 'Daily';

  @override
  String get scheduleKindWeekly => 'Weekly';

  @override
  String get scheduleKindCron => 'Cron expression';

  @override
  String get scheduleFieldDate => 'Date';

  @override
  String get scheduleFieldTime => 'Time';

  @override
  String get scheduleFieldZone => 'Time zone';

  @override
  String get scheduleFieldSeconds => 'Interval in seconds';

  @override
  String get scheduleFieldExpression => 'Expression';

  @override
  String get scheduleFieldWeekdays => 'Days';

  @override
  String get terminalInputHint => 'Type a command';

  @override
  String get terminalColorUnavailable =>
      'Colors and cursor addressing are not rendered.';

  @override
  String get terminalTitle => 'Terminal';

  @override
  String get terminalNew => 'New terminal';

  @override
  String get terminalActions => 'Terminal actions';

  @override
  String get terminalRename => 'Rename';

  @override
  String get terminalClose => 'Close terminal';

  @override
  String get terminalTakeControl => 'Take control';

  @override
  String get terminalReconnect => 'Reconnect';

  @override
  String get terminalPickShell => 'Choose a shell';

  @override
  String get terminalUnavailable => 'This host composes no terminal service.';

  @override
  String get terminalNoTerminal =>
      'No terminal is open in this session. Start one to run commands in the host workspace.';

  @override
  String get terminalStatusDetached => 'not attached';

  @override
  String get terminalStatusConnecting => 'connecting';

  @override
  String get terminalStatusRunning => 'running';

  @override
  String get terminalStatusDisconnected => 'disconnected';

  @override
  String terminalStatusExited(int code) {
    return 'exited ($code)';
  }

  @override
  String get terminalStatusFailed => 'failed to start';

  @override
  String terminalLimitReached(int limit) {
    return 'This session already holds its limit of $limit terminals.';
  }

  @override
  String get terminalOutputGap => 'Output was lost; the screen was re-read.';

  @override
  String get terminalInputTooLong =>
      'That input is longer than the host accepts.';

  @override
  String get terminalInvalidTitle =>
      'A terminal name needs 1 to 120 characters.';

  @override
  String get terminalCloseFailed =>
      'The host could not close this terminal; try again.';

  @override
  String get terminalReadOnly =>
      'Another window holds input; take control to type.';

  @override
  String get terminalNotRunning => 'The shell has exited.';

  @override
  String get terminalEntryTooltip => 'Terminal';

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
  String get jobKillStop => 'Stop';

  @override
  String get jobKillConfirm => 'Press again to stop';

  @override
  String get jobKillFailed => 'Stop refused';

  @override
  String get jobOutputGap => 'Earlier output was discarded';

  @override
  String jobOutputError(String error) {
    return 'Output stream interrupted: $error';
  }

  @override
  String get jobOutputEmpty => 'No output yet';

  @override
  String jobSettledCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count finished',
      one: '1 finished',
    );
    return '$_temp0';
  }

  @override
  String get jobClearSettled => 'Clear';

  @override
  String get jobExpand => 'Show output';

  @override
  String get jobCollapse => 'Hide output';

  @override
  String get copyTooltip => 'Copy';

  @override
  String get codeStreamingLabel => 'streaming';

  @override
  String get forkFromHere => 'Fork from here';

  @override
  String get copiedTooltip => 'Copied';

  @override
  String get steeringMessageBadge => 'Steering';

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
  String get settingsNavPlugins => 'Host namespace values';

  @override
  String get settingsNavPluginSettings => 'Host namespace values';

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
  String get settingsNavPermissionDefaults => 'Default permission preset';

  @override
  String get permissionDefaultsIntro =>
      'Which preset a new session starts on. The current session switches from the access chip in the composer; this row only changes the default.';

  @override
  String get permissionDefaultsLoading => 'Reading the permission table…';

  @override
  String get permissionDefaultsUnavailable =>
      'This deployment composes no permission preset catalog, so there is no default to set.';

  @override
  String get permissionDefaultsReadOnly =>
      'Settings are read-only on this deployment.';

  @override
  String get attachmentNotInSession =>
      'This image is no longer part of the session';

  @override
  String get permissionAutoReviewBadge => 'EXP';

  @override
  String get permissionAutoReviewLabel => 'Auto review';

  @override
  String get permissionAutoReviewDescription =>
      'Runs without a sandbox: every native tool call and PTC inner call is reviewed by the same model before it runs.';

  @override
  String get permissionAutoReviewConfirmTitle =>
      'Enable Auto review (experimental)?';

  @override
  String get permissionAutoReviewConfirmDescription =>
      'Auto review does not use a sandbox. Every native tool call and PTC inner call is reviewed by the same model as the current agent; a call the review rejects is yours to approve or deny. It is still experimental: it can let through or refuse the wrong call, and it costs extra tokens.';

  @override
  String get permissionAutoReviewConfirmAcknowledge =>
      'I understand these risks and want to continue';

  @override
  String get permissionAutoReviewConfirmEnable => 'Enable Auto review';

  @override
  String get agentPresetViewDeclaration => 'View';

  @override
  String get agentPresetDocumentTitle => 'Declared composition';

  @override
  String get agentPresetDocumentIntro =>
      'The child plugin list this preset declares, as YAML. A view: presets are composed on the host.';

  @override
  String get agentPresetDocumentUnavailable =>
      'The declaration could not be read from this host.';

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
      'A preset is the plugin composition one session\'s agent runs — its tools, prompt, and capabilities. Choose the one new sessions start with.';

  @override
  String get presetsFooter =>
      'Presets are declared on the host; this app reads the roster and picks the default new sessions start with.';

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
  String get pluginsRawNamespaceNotice =>
      'Raw Host values: this client does not receive a plugin\'s field labels or descriptions yet, so each key is shown as the Host sends it. A plugin\'s own configuration page belongs to the plugin that serves the namespace.';

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
  String get useDefaultWorkspace => 'Use the default workspace';

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
  String get modeUnknown => 'unknown mode';

  @override
  String get activityRunning => 'running';

  @override
  String get activityNotRunning => 'not running';

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
  String get unknownRecordBody =>
      'Read the child session to determine whether it can be continued.';

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
  String get openWorkspace => 'Open workspace';

  @override
  String get unarchiveSession => 'Unarchive session';

  @override
  String get archivedBadge => 'Archived';

  @override
  String get pinSession => 'Pin session';

  @override
  String get unpinSession => 'Unpin session';

  @override
  String get filterSessionsTooltip => 'Filter sessions';

  @override
  String get viewHideArchived => 'Hide archived';

  @override
  String get viewShowArchived => 'All conversations (show archived)';

  @override
  String get viewOnlyArchived => 'Archived only';

  @override
  String get noArchivedSessions => 'No archived sessions yet';

  @override
  String get viewOtherSessions => 'View other sessions';

  @override
  String get archiveConfirmTitle => 'Stop and archive this session?';

  @override
  String archiveConfirmBody(String title) {
    return '“$title” still has work in progress. Archiving stops it first; you can restore the session later from the “All conversations (show archived)” filter in the sidebar, and the stopped work will not resume on its own.';
  }

  @override
  String get archiveConfirmActivity => 'Work that will be stopped';

  @override
  String get archiveConfirmTurn => 'The turn in progress';

  @override
  String archiveConfirmSubagents(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count running subagents: $names',
      one: '1 running subagent: $names',
    );
    return '$_temp0';
  }

  @override
  String archiveConfirmJobs(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count background jobs: $names',
      one: '1 background job: $names',
    );
    return '$_temp0';
  }

  @override
  String archiveConfirmSchedules(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count scheduled reminders: $names',
      one: '1 scheduled reminder: $names',
    );
    return '$_temp0';
  }

  @override
  String archiveConfirmOther(int count, String kind) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count other items of work ($kind)',
      one: '1 other item of work ($kind)',
    );
    return '$_temp0';
  }

  @override
  String get archiveConfirmListSeparator => ', ';

  @override
  String get archiveConfirmAction => 'Stop and archive';

  @override
  String get archiveConfirmPending => 'Stopping and archiving…';

  @override
  String get archiveNoticeArchived => 'Session archived';

  @override
  String get archiveNoticeStopped => 'Session stopped and archived';

  @override
  String get archiveNotOpenableNotice =>
      'Archived sessions cannot be opened. Unarchive it to view.';

  @override
  String get archiveFailedNotice => 'Archiving failed. Try again later.';

  @override
  String get undoAction => 'Undo';

  @override
  String createSessionFailedNotice(String message) {
    return 'New session failed: $message';
  }

  @override
  String get pluginRefreshFailedNotice => 'Refresh failed. Please try again.';

  @override
  String get linkOpenFailedNotice => 'Could not open the link. Try again.';

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
  String get questionMinimize => 'Collapse the card';

  @override
  String get questionMaximize => 'Expand the card';

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
  String get attachFile => 'Attach a file';

  @override
  String get pickFileFromDevice => 'Pick from device storage';

  @override
  String fileUploading(String size) {
    return 'Uploading · $size';
  }

  @override
  String fileUploaded(String size) {
    return 'Uploaded · $size';
  }

  @override
  String get fileUploadFailed => 'Upload failed';

  @override
  String removeFile(String name) {
    return 'Remove $name';
  }

  @override
  String fileAttachmentNotReady(String name) {
    return '$name has not finished uploading';
  }

  @override
  String fileTooLarge(int limit) {
    return 'That file is larger than the $limit MB upload limit';
  }

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
  String commandFilesUnsupported(String command) {
    return '/$command does not accept attachments; remove them first';
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
  String get turnCompleteTitle => 'Reply ready';

  @override
  String get turnCompletionChannel => 'Turn completion';

  @override
  String get turnCompletionChannelDescription =>
      'Notifies when a running conversation turn finishes.';

  @override
  String get otherTurnCompleteTitle => 'New reply in another session';

  @override
  String get approvalRequestedTitle => 'Approval needed';

  @override
  String get planReviewRequestedTitle => 'Plan ready for review';

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
  String get notificationPermissionTitle => 'Turn on notifications?';

  @override
  String get notificationPermissionBody =>
      'Android needs your permission before the app can tell you when a session finishes or waits on your approval. Agent work keeps running either way.';

  @override
  String get notificationPermissionAllow => 'Allow';

  @override
  String get notificationPermissionLater => 'Not now';

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
  String get voiceModeKeyboard => 'Keyboard input';

  @override
  String get voiceHoldToTalk => 'Hold to talk';

  @override
  String get voiceInputReleaseToSend => 'Release to send';

  @override
  String get voiceInputSlideToSend => 'Release to send · slide up to cancel';

  @override
  String get voiceInputReleaseToCancel => 'Release to cancel';

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
  String get filePreviewTooLarge => 'This file is too large to preview.';

  @override
  String get filePreviewNotFound => 'This file is no longer there.';

  @override
  String get filePreviewUnsupported =>
      'This file type can\'t be previewed in the app.';

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
  String get presentedFilesLabel => 'Present files';

  @override
  String get presentedFilesOpen => 'Open';

  @override
  String presentedFilesOpenName(String name) {
    return 'Open $name';
  }

  @override
  String get presentedFilesFile => 'File';

  @override
  String presentedFilesAll(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return 'All $_temp0';
  }

  @override
  String get presentedFilesCollapse => 'Collapse';

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
  String get settingsTranscriptViewTitle => 'Work details';

  @override
  String get settingsTranscriptViewDescription =>
      'Choose how much detail to show for tool calls';

  @override
  String get settingsSessionLogTitle =>
      'Upload Session Log when using the official model API';

  @override
  String get settingsSessionLogDescription =>
      'Help improve DeepSeek models and products.';

  @override
  String get settingsSessionLogSaveFailed => 'Couldn\'t save the preference';

  @override
  String get settingsGesturesTitle => 'Gestures';

  @override
  String get settingsGesturesIntro =>
      'A phone has no keyboard shortcuts: the app\'s actions ride its controls and the gestures listed here.';

  @override
  String get settingsGesturesEditorNote =>
      'Recording or remapping key bindings belongs to the desktop app.';

  @override
  String get settingsGesturesMessageTitle => 'Long-press a message';

  @override
  String get settingsGesturesMessageBody =>
      'Copy it, or fork the conversation from it.';

  @override
  String get settingsGesturesSessionTitle => 'Long-press a session row';

  @override
  String get settingsGesturesSessionBody =>
      'Rename, fork, pin or archive that session.';

  @override
  String get settingsGesturesProjectTitle => 'Long-press a project header';

  @override
  String get settingsGesturesProjectBody =>
      'Start a new session in that project.';

  @override
  String get settingsGesturesVoiceTitle => 'Hold the microphone';

  @override
  String get settingsGesturesVoiceBody =>
      'Talk instead of typing while you hold it.';

  @override
  String get settingsGesturesHistoryTitle =>
      'Scroll to the top of the transcript';

  @override
  String get settingsGesturesHistoryBody =>
      'Loads the conversation\'s older history.';

  @override
  String get settingsTranscriptViewCompact => 'Compact';

  @override
  String get settingsTranscriptViewStandard => 'Standard';

  @override
  String get settingsTranscriptViewDetailed => 'Detailed';

  @override
  String get settingsTranscriptViewVerbose => 'Verbose';

  @override
  String get settingsTranscriptViewUnavailable =>
      'Host Chat settings are unavailable.';

  @override
  String get settingsTranscriptViewSaveFailed =>
      'Couldn\'t save the work-details choice.';

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

  @override
  String get stepProcessThinking => 'Analyzing the request';

  @override
  String get stepProcessRead => 'Reading files';

  @override
  String get stepProcessReadImage => 'Reading images';

  @override
  String get stepProcessWrite => 'Writing files';

  @override
  String get stepProcessSearch => 'Searching code';

  @override
  String get stepProcessEdit => 'Editing files';

  @override
  String get stepProcessCommands => 'Running commands';

  @override
  String get stepProcessCode => 'Running code';

  @override
  String get stepProcessWebSearch => 'Searching the web';

  @override
  String get stepProcessWebFetch => 'Visiting web pages';

  @override
  String get stepProcessSubagents => 'Coordinating subagents';

  @override
  String get stepProcessPlan => 'Updating the plan';

  @override
  String get stepProcessQuestions => 'Waiting for your action';

  @override
  String get stepProcessTools => 'Calling tools';

  @override
  String get stepProcessPrepareRead => 'Preparing to read files';

  @override
  String get stepProcessPrepareReadImage => 'Preparing to read images';

  @override
  String get stepProcessPrepareWrite => 'Preparing to write files';

  @override
  String get stepProcessPrepareSearch => 'Preparing to search code';

  @override
  String get stepProcessPrepareEdit => 'Preparing to edit files';

  @override
  String get stepProcessPrepareCommands => 'Preparing to run commands';

  @override
  String get stepProcessPrepareCode => 'Preparing to run code';

  @override
  String get stepProcessPrepareWebSearch => 'Preparing to search the web';

  @override
  String get stepProcessPrepareWebFetch => 'Preparing to visit web pages';

  @override
  String get stepProcessPrepareSubagents => 'Preparing to coordinate subagents';

  @override
  String get stepProcessPreparePlan => 'Preparing to update the plan';

  @override
  String get stepProcessPrepareQuestions => 'Preparing questions';

  @override
  String get stepProcessPrepareTools => 'Preparing tool calls';

  @override
  String get stepProcessDoneThinking => 'Analysis completed';

  @override
  String get stepProcessDoneRead => 'Read files';

  @override
  String get stepProcessDoneReadImage => 'Read images';

  @override
  String get stepProcessDoneWrite => 'Wrote files';

  @override
  String get stepProcessDoneSearch => 'Searched code';

  @override
  String get stepProcessDoneEdit => 'Edited files';

  @override
  String get stepProcessDoneCommands => 'Ran commands';

  @override
  String get stepProcessDoneCode => 'Ran code';

  @override
  String get stepProcessDoneWebSearch => 'Searched the web';

  @override
  String get stepProcessDoneWebFetch => 'Visited web pages';

  @override
  String get stepProcessDoneSubagents => 'Coordinated subagents';

  @override
  String get stepProcessDonePlan => 'Updated the plan';

  @override
  String get stepProcessDoneQuestions => 'Asked questions';

  @override
  String get stepProcessDoneTools => 'Called tools';

  @override
  String stepProcessJoinTwo(String first, String second) {
    return '$first and $second';
  }

  @override
  String get stepProcessComma => ', ';

  @override
  String get stepProcessSharedPrefix => '';

  @override
  String stepProcessMore(String title) {
    return '$title, etc.';
  }

  @override
  String get turnProcessDeepDiving => 'Deep diving';

  @override
  String turnProcessDeepDivingFor(String duration) {
    return 'Deep diving for $duration ···';
  }

  @override
  String get turnProcessTook => 'Completed in ';

  @override
  String get turnProcessWorked => 'Completed';

  @override
  String get turnProcessFailed => 'Failed';

  @override
  String get turnProcessStopped => 'Stopped';

  @override
  String get turnProcessSeparator => ' · ';

  @override
  String get runDurationHourUnit => 'h ';

  @override
  String get runDurationMinuteUnit => 'm ';

  @override
  String get runDurationSecondUnit => 's';

  @override
  String get settingsNavAccount => 'Account';

  @override
  String get accountIntro =>
      'The account credential this host stores, the DeepSeek Platform profile and balance it reports, and any granted bonus it has not yet recorded as displayed.';

  @override
  String get accountLoading => 'Loading account facts…';

  @override
  String get accountUnavailable => 'This host reports no account plane';

  @override
  String get accountUnavailableBody =>
      'This deployment does not compose the account service, so there is no sign-in state, profile, or balance to show.';

  @override
  String get accountSignedOut => 'Not signed in to DeepSeek';

  @override
  String get accountSignedOutBody =>
      'This host stores no account credential, so it reports no profile and no balance.';

  @override
  String get accountSignedIn => 'Signed in to DeepSeek';

  @override
  String get accountProfileUnavailable =>
      'The host could not read the Platform profile.';

  @override
  String accountProfileId(String id) {
    return 'Account id $id';
  }

  @override
  String get accountBalance => 'Topped-up balance';

  @override
  String get accountBonusBalance => 'Granted balance';

  @override
  String get accountBalanceUnavailable =>
      'The host could not read the balance.';

  @override
  String get accountBalanceAbsent =>
      'The host reports no balance for this account.';

  @override
  String get accountBonusUnavailable =>
      'The host could not read granted bonuses.';

  @override
  String get accountBonusAbsent => 'The host reports no unseen bonus.';

  @override
  String get accountBalanceNone => 'No topped-up wallet reported.';

  @override
  String get accountBonusNone => 'No granted wallet reported.';

  @override
  String get accountUnseenBonus => 'Unseen bonus';

  @override
  String get accountBonusTitle => 'Bonus credited';

  @override
  String accountBonusWindow(String grantedAt, String expiresAt) {
    return 'Granted $grantedAt, expires $expiresAt';
  }

  @override
  String get accountBonusAck => 'Got it';

  @override
  String get accountBonusAckFailed =>
      'The host did not record this bonus as displayed.';

  @override
  String get accountBonusAckRetry => 'Try again';

  @override
  String get fileReferenceSectionTitle => 'Files & folders';

  @override
  String get sessionReferenceSectionTitle => 'Sessions';

  @override
  String get settingsNavShell => 'Shell';

  @override
  String get settingsShellDescription =>
      'Limit how long each command may run and how much it may output.';

  @override
  String get settingsShellTimeoutMsLabel => 'Command timeout (ms)';

  @override
  String get settingsShellTimeoutMsHint =>
      'How long one command may run before it is terminated.';

  @override
  String get settingsShellMaxOutputBytesLabel =>
      'Output cap per stream (bytes)';

  @override
  String get settingsShellMaxOutputBytesHint =>
      'Output beyond this spills to a temporary file rather than being lost.';

  @override
  String get settingsNavWebSearch => 'Web search';

  @override
  String get settingsWebSearchDescription =>
      'Set up the DeepSeek search provider.';

  @override
  String get settingsWebSearchApiKeyLabel => 'API key';

  @override
  String get settingsWebSearchApiKeyHint =>
      'Stored outside the settings file. Leave blank to keep the current key.';

  @override
  String get settingsWebSearchApiKeySet => 'A key is configured.';

  @override
  String get settingsWebSearchApiKeyUnset =>
      'No key is configured; only conversations using a DeepSeek Account model can search, through the default endpoint.';

  @override
  String get settingsWebSearchBaseUrlLabel => 'Endpoint';

  @override
  String get settingsWebSearchBaseUrlHint =>
      'Leave blank to use the provider default.';

  @override
  String get settingsWebSearchMaxUsesLabel => 'Max searches per request';

  @override
  String get settingsWebSearchMaxUsesHint =>
      'How many times one request may search before it must answer.';

  @override
  String get settingsFormOverridden => 'Overridden';

  @override
  String get settingsFormReset => 'Reset to default';

  @override
  String get settingsFormReadOnly =>
      'This deployment stores settings read-only.';

  @override
  String get settingsFormUnavailable =>
      'This plugin is not loaded, so it cannot be configured right now.';

  @override
  String get settingsFormSaving => 'Saving…';

  @override
  String get settingsFormSaveFailed =>
      'The deployment did not accept these values; they were left for you to correct.';

  @override
  String get settingsFormInvalidNumber =>
      'Enter a number, or leave blank to use the default.';

  @override
  String get settingsAgentLoopTitle => 'Agent loop';

  @override
  String get settingsSubagentTitle => 'Subagents';

  @override
  String get settingsSubagentMaxDepth => 'Maximum depth';

  @override
  String get settingsSubagentMaxActive => 'Maximum active subagents';

  @override
  String get settingsSubagentLimitRejected =>
      'Enter a whole number at or above the minimum.';

  @override
  String get settingsSubagentModelSelection => 'Model selection';

  @override
  String get settingsSubagentModelSelectionBody =>
      'Let new sessions choose a child model route.';

  @override
  String get settingsSubagentUnavailable => 'Unavailable';

  @override
  String get settingsSubagentSave => 'Save';

  @override
  String get settingsSubagentSaveFailed =>
      'Couldn\'t save the subagent settings';

  @override
  String get settingsAgentLoopDescription => 'How the agent batches its work.';

  @override
  String get settingsAgentLoopMaxParallel => 'Parallel tool calls per step';

  @override
  String get settingsAgentLoopUnpublished =>
      'This host does not publish an agent-loop setting.';

  @override
  String get settingsAgentLoopSaveFailed => 'Could not save the limit';

  @override
  String get accessModeIntro =>
      'What the agent may do in this conversation. Picking one switches this session\'s permission preset; the default for new sessions lives in Settings.';

  @override
  String get accessModeLoading => 'Reading the access modes…';

  @override
  String get accessModeUnavailable =>
      'This deployment composes no access modes to switch between.';

  @override
  String get accessModeLoadFailed => 'Could not read the access modes.';
}
