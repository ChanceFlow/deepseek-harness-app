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
  String goalStatusLine(String phase, int revision, int started, int max) {
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
  String get conversationLabel => 'Conversation';

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
    return '$count active';
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
  String toolTodoPlanCompleted(int done, int total) {
    return '$done/$total completed';
  }

  @override
  String statsTurnsSteps(int turns, int steps) {
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
}
