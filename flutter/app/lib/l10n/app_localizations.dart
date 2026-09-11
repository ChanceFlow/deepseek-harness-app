import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// Application title used in the OS task switcher and window title.
  ///
  /// In en, this message translates to:
  /// **'DSH Mobile'**
  String get appTitle;

  /// Generic cancel action.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Generic save action.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Generic create action.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// Generic refresh action.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// Generic retry action.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Manual reconnect action for an unreachable host.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get reconnect;

  /// Connection banner naming the unreachable host.
  ///
  /// In en, this message translates to:
  /// **'Can\'\'t reach {host}'**
  String connectionHostUnreachable(String host);

  /// Back navigation tooltip.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// Generic close action.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Dismiss an error banner.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// Generic delete action.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Generic rename action.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// Generic open action.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @defaultBadge.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultBadge;

  /// Bottom navigation label for the chat surface.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get destinationChat;

  /// Bottom navigation label for the workspace browser.
  ///
  /// In en, this message translates to:
  /// **'Workspaces'**
  String get destinationWorkspaces;

  /// Bottom navigation label for host configuration.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get destinationSettings;

  /// Goal screen app bar title.
  ///
  /// In en, this message translates to:
  /// **'Goal'**
  String get goalTitle;

  /// Section label naming the selected session.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get sessionLabel;

  /// Section label naming model providers.
  ///
  /// In en, this message translates to:
  /// **'Providers'**
  String get providersLabel;

  /// Empty state when no goal is active.
  ///
  /// In en, this message translates to:
  /// **'No ongoing goal'**
  String get noCurrentGoal;

  /// Hint and edit-field label for the goal objective text.
  ///
  /// In en, this message translates to:
  /// **'Goal objective'**
  String get goalObjectiveHint;

  /// Hint for the optional max-rounds field.
  ///
  /// In en, this message translates to:
  /// **'Max goal rounds (optional)'**
  String get maxGoalRoundsHint;

  /// Pause an active goal.
  ///
  /// In en, this message translates to:
  /// **'Pause goal'**
  String get pause;

  /// Resume a paused goal.
  ///
  /// In en, this message translates to:
  /// **'Resume goal'**
  String get resume;

  /// Clear a goal.
  ///
  /// In en, this message translates to:
  /// **'Clear goal'**
  String get clear;

  /// Complete a goal.
  ///
  /// In en, this message translates to:
  /// **'Complete goal'**
  String get complete;

  /// Edit a goal.
  ///
  /// In en, this message translates to:
  /// **'Edit goal'**
  String get edit;

  /// Goal phase label, active.
  ///
  /// In en, this message translates to:
  /// **'Ongoing Goal'**
  String get goalPhaseActive;

  /// Goal phase label, paused.
  ///
  /// In en, this message translates to:
  /// **'Paused Goal'**
  String get goalPhasePaused;

  /// Goal phase label, blocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked Goal'**
  String get goalPhaseBlocked;

  /// Goal phase label, complete.
  ///
  /// In en, this message translates to:
  /// **'Completed Goal'**
  String get goalPhaseComplete;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{phase} · revision {revision} · rounds {started}/{max}'**
  String goalStatusLine(int max, String phase, int revision, int started);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{percent}% of context used'**
  String contextUsedPercent(int percent);

  /// Composer context ring label while no usage sample exists.
  ///
  /// In en, this message translates to:
  /// **'Context'**
  String get contextLabel;

  /// Context composition legend, system prompt row.
  ///
  /// In en, this message translates to:
  /// **'System prompt'**
  String get systemPromptLabel;

  /// Context composition legend, tools row.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get toolsLabel;

  /// Context composition legend, conversation row.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get conversationLabel;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'~{used} / {window}'**
  String contextTokens(String used, String window);

  /// Empty-chat hero headline.
  ///
  /// In en, this message translates to:
  /// **'Into the Unknown'**
  String get heroHeadline;

  /// Preview badge on the hero.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get heroPreview;

  /// Workspace chip label and tooltip on the empty hero.
  ///
  /// In en, this message translates to:
  /// **'Choose workspace'**
  String get heroChooseWorkspace;

  /// Models screen app bar title.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get modelsTitle;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{name} (current)'**
  String modelCurrent(String name);

  /// Section label for reasoning effort chips.
  ///
  /// In en, this message translates to:
  /// **'Reasoning effort'**
  String get reasoningEffortLabel;

  /// Plan-strip header label.
  ///
  /// In en, this message translates to:
  /// **'To-dos'**
  String get todosLabel;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{count} completed'**
  String todoCountDone(int count);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{count} in progress'**
  String todoCountActive(int count);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{count} pending'**
  String todoCountPending(int count);

  /// Background-jobs sheet title.
  ///
  /// In en, this message translates to:
  /// **'Background jobs'**
  String get backgroundJobsTitle;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 background job running} other{{count} background jobs running}}'**
  String jobCountRunning(int count);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 background job} other{{count} background jobs}}'**
  String jobCount(int count);

  /// Job status label, running.
  ///
  /// In en, this message translates to:
  /// **'running'**
  String get jobStatusRunning;

  /// Job status label, stopping.
  ///
  /// In en, this message translates to:
  /// **'stopping'**
  String get jobStatusStopping;

  /// Job status label, completed.
  ///
  /// In en, this message translates to:
  /// **'completed'**
  String get jobStatusCompleted;

  /// Job status label, cancelled.
  ///
  /// In en, this message translates to:
  /// **'cancelled'**
  String get jobStatusKilled;

  /// Job status label, failed.
  ///
  /// In en, this message translates to:
  /// **'failed'**
  String get jobStatusFailed;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String jobDurationHoursMinutes(int hours, int minutes);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m {seconds}s'**
  String jobDurationMinutesSeconds(int minutes, int seconds);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String jobDurationSeconds(int seconds);

  /// Copy-message icon tooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyTooltip;

  /// Code block label while the fence has not closed yet.
  ///
  /// In en, this message translates to:
  /// **'streaming'**
  String get codeStreamingLabel;

  /// Message verb: cut a new session at this message (session.fork atSeq).
  ///
  /// In en, this message translates to:
  /// **'Fork from here'**
  String get forkFromHere;

  /// Copy-message icon tooltip after a successful copy.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copiedTooltip;

  /// Approval panel header strip.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval'**
  String get waitingForApproval;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Approve tool: {tool}'**
  String approveToolFallback(String tool);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Tool {tool} requests privileged execution'**
  String toolRequestsPrivileged(String tool);

  /// Reject an approval request.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// Allow a privileged execution a single time.
  ///
  /// In en, this message translates to:
  /// **'Allow once'**
  String get allowOnce;

  /// Label for the agent-preset seat and sheet title.
  ///
  /// In en, this message translates to:
  /// **'Agent preset'**
  String get agentPresetLabel;

  /// Tooltip explaining the preset seat.
  ///
  /// In en, this message translates to:
  /// **'Agent preset for the session you are about to start'**
  String get agentPresetTooltip;

  /// Access-mode sheet title.
  ///
  /// In en, this message translates to:
  /// **'Access mode'**
  String get accessModeLabel;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Access mode: {label}'**
  String accessModeTooltip(String label);

  /// Product label for the danger-full-access permission value.
  ///
  /// In en, this message translates to:
  /// **'Full access'**
  String get fullAccessOption;

  /// Risk-confirmation dialog title.
  ///
  /// In en, this message translates to:
  /// **'Enable Full access?'**
  String get enableFullAccessTitle;

  /// Risk-confirmation dialog body.
  ///
  /// In en, this message translates to:
  /// **'Full access reduces confirmation steps and lets the agent perform more actions directly, including sensitive operations, file changes, or external commands. Only use it when you trust the current task.'**
  String get fullAccessRisks;

  /// Acknowledgement checkbox in the risk-confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'I understand the risks and want to continue'**
  String get acknowledgeRisks;

  /// Confirm button in the risk-confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Enable Full access'**
  String get enableFullAccess;

  /// Model seat label and sheet menu row.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get modelLabel;

  /// Reasoning-effort seat label and sheet menu row.
  ///
  /// In en, this message translates to:
  /// **'Effort'**
  String get effortLabel;

  /// Effort option meaning the provider's default effort.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get providerDefault;

  /// Built-in agent preset display name.
  ///
  /// In en, this message translates to:
  /// **'Standard mode'**
  String get presetStandardName;

  /// Built-in agent preset display description.
  ///
  /// In en, this message translates to:
  /// **'Full coding agent with file editing, shell, file and web search, skills, planning, goals, subagents, and workflows.'**
  String get presetStandardDescription;

  /// Built-in agent preset display name.
  ///
  /// In en, this message translates to:
  /// **'Code mode'**
  String get presetCodeName;

  /// Built-in agent preset display description.
  ///
  /// In en, this message translates to:
  /// **'All Standard mode capabilities, with tools exposed through the Code Mode SDK so the model can combine multi-step operations in one TypeScript program.'**
  String get presetCodeDescription;

  /// Built-in agent preset display name.
  ///
  /// In en, this message translates to:
  /// **'Minimal mode'**
  String get presetMinimalName;

  /// Built-in agent preset display description.
  ///
  /// In en, this message translates to:
  /// **'Two-tool coding agent with persistent bash and str_replace_editor.'**
  String get presetMinimalDescription;

  /// Built-in agent preset display name.
  ///
  /// In en, this message translates to:
  /// **'Creator mode'**
  String get presetCordisName;

  /// Built-in agent preset display description.
  ///
  /// In en, this message translates to:
  /// **'Built for creating custom agent presets, with all Standard mode capabilities plus runtime inspection, plugin experiments, and preset-authoring guidance.'**
  String get presetCordisDescription;

  /// Tool row title for search variants.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get toolSearchTitle;

  /// Tool row title for read variants.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get toolReadTitle;

  /// Tool row title for bash variants.
  ///
  /// In en, this message translates to:
  /// **'Bash'**
  String get toolBashTitle;

  /// Tool row title for write variants.
  ///
  /// In en, this message translates to:
  /// **'Write'**
  String get toolWriteTitle;

  /// Tool row title for edit variants.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get toolEditTitle;

  /// Tool row title for code variants.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get toolCodeTitle;

  /// Tool row title for other variants.
  ///
  /// In en, this message translates to:
  /// **'Tool call'**
  String get toolCallTitle;

  /// Tool title for cordis inspection tools.
  ///
  /// In en, this message translates to:
  /// **'Inspect'**
  String get toolInspectTitle;

  /// Tool title for running a Cordis plugin.
  ///
  /// In en, this message translates to:
  /// **'Run Cordis Plugin'**
  String get toolRunCordisPlugin;

  /// Tool title for stopping a Cordis plugin.
  ///
  /// In en, this message translates to:
  /// **'Stop Cordis Plugin'**
  String get toolStopCordisPlugin;

  /// Tool title for removing a Cordis plugin.
  ///
  /// In en, this message translates to:
  /// **'Remove Cordis Plugin'**
  String get toolRemoveCordisPlugin;

  /// Tool title for the PowerShell shell tool.
  ///
  /// In en, this message translates to:
  /// **'Pwsh'**
  String get toolPwshTitle;

  /// Tool row title for the todo_write tool.
  ///
  /// In en, this message translates to:
  /// **'Update to-do list'**
  String get toolUpdateTodoTitle;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{done}/{total} completed'**
  String toolTodoPlanCompleted(int done, int total);

  /// Collapsed thought block header with completed duration.
  ///
  /// In en, this message translates to:
  /// **'Thought {duration}'**
  String thoughtDuration(String duration);

  /// Active in-flight thought header with ticking duration.
  ///
  /// In en, this message translates to:
  /// **'Thinking · {duration}'**
  String thinkingDuration(String duration);

  /// Collapsed action summary when both files were explored and searches were conducted.
  ///
  /// In en, this message translates to:
  /// **'{files, plural, =1{Explored 1 file} other{Explored {files} files}}, {searches, plural, =1{1 search} other{{searches} searches}}'**
  String exploredFilesAndSearches(int files, int searches);

  /// Collapsed action summary for explored files.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Explored 1 file} other{Explored {count} files}}'**
  String exploredFiles(int count);

  /// In-flight action summary for exploring files.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Exploring 1 file} other{Exploring {count} files}}'**
  String exploringFiles(int count);

  /// Action summary for search operations.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 search} other{{count} searches}}'**
  String searchedCount(int count);

  /// Action summary for file edits/writes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Modified 1 file} other{Modified {count} files}}'**
  String modifiedFiles(int count);

  /// Action summary for executed terminal commands.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Ran 1 command} other{Ran {count} commands}}'**
  String ranCommands(int count);

  /// In-flight action summary for executing terminal commands.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Running 1 command} other{Running {count} commands}}'**
  String runningCommands(int count);

  /// Fallback action summary count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 operation} other{{count} operations}}'**
  String toolGroupOperations(int count);

  /// In-flight multi-step action header.
  ///
  /// In en, this message translates to:
  /// **'Working ({count, plural, =1{1 step} other{{count} steps}})'**
  String toolWorkingSteps(int count);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{turns} turns · {steps} steps'**
  String statsTurnsSteps(int steps, int turns);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'LLM {duration}'**
  String statsLlmDuration(String duration);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Tool call {duration}'**
  String statsToolDuration(String duration);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'TTFT avg {duration}'**
  String statsTtftAvg(String duration);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{rate} tok/s'**
  String statsTokensPerSecond(String rate);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Cache hit {percent}%'**
  String statsCacheHit(int percent);

  /// Composer stats: billed input token count.
  ///
  /// In en, this message translates to:
  /// **'Input {tokens} tok'**
  String statsInputTokens(String tokens);

  /// Composer stats: output token count.
  ///
  /// In en, this message translates to:
  /// **'Output {tokens} tok'**
  String statsOutputTokens(String tokens);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Credential state unavailable: {error}'**
  String credentialStateUnavailable(String error);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Store {ref}'**
  String storeCredentialTitle(String ref);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'applies: {name}'**
  String namespaceMetaApplies(String name);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'revision: {revision}'**
  String namespaceMetaRevision(int revision);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'source: {source}'**
  String credentialMetaSource(String source);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'CAS revision {revision}; host validates against the schema'**
  String casRevisionLine(int revision);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'New session in {title}'**
  String newSessionInWorkspace(String title);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Workspace actions for {title}'**
  String workspaceActionsFor(String title);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Session actions for {title}'**
  String sessionActionsFor(String title);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'A workspace named “{name}” already exists.'**
  String workspaceNameExists(String name);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'This removes “{name}” from the workspace list. The folder and session logs will be kept. Its sessions will appear under {ungroupedLabel}.'**
  String deleteWorkspaceConfirm(String name, String ungroupedLabel);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'New folder in \"{parent}\"'**
  String newFolderIn(String parent);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 secret set} other{{count} secrets set}}'**
  String secretsSetCount(int count);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 session} other{{count} sessions}}'**
  String workspaceSessionCount(int count);

  /// No description provided for @settingsCategoryApp.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get settingsCategoryApp;

  /// No description provided for @settingsCategoryHost.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get settingsCategoryHost;

  /// No description provided for @settingsSectionHost.
  ///
  /// In en, this message translates to:
  /// **'Host & connection'**
  String get settingsSectionHost;

  /// No description provided for @settingsSectionApp.
  ///
  /// In en, this message translates to:
  /// **'App preferences'**
  String get settingsSectionApp;

  /// No description provided for @settingsSectionChat.
  ///
  /// In en, this message translates to:
  /// **'Chat & agent'**
  String get settingsSectionChat;

  /// No description provided for @settingsSectionModels.
  ///
  /// In en, this message translates to:
  /// **'Models & credentials'**
  String get settingsSectionModels;

  /// No description provided for @settingsSectionPlugins.
  ///
  /// In en, this message translates to:
  /// **'Plugins & advanced'**
  String get settingsSectionPlugins;

  /// No description provided for @manageHosts.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get manageHosts;

  /// No description provided for @appSettingsIntro.
  ///
  /// In en, this message translates to:
  /// **'Preferences stored on this device — they apply everywhere, with or without a connected host.'**
  String get appSettingsIntro;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// No description provided for @languageDescription.
  ///
  /// In en, this message translates to:
  /// **'The app interface language; Follow system tracks the device language.'**
  String get languageDescription;

  /// No description provided for @languageOptionSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get languageOptionSystem;

  /// No description provided for @languageOptionZh.
  ///
  /// In en, this message translates to:
  /// **'中文'**
  String get languageOptionZh;

  /// No description provided for @languageOptionEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageOptionEn;

  /// No description provided for @settingsNavGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsNavGeneral;

  /// No description provided for @settingsNavModels.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get settingsNavModels;

  /// No description provided for @settingsNavPlugins.
  ///
  /// In en, this message translates to:
  /// **'Plugins'**
  String get settingsNavPlugins;

  /// No description provided for @settingsNavAgentPresets.
  ///
  /// In en, this message translates to:
  /// **'Agent presets'**
  String get settingsNavAgentPresets;

  /// No description provided for @settingsNavCredentials.
  ///
  /// In en, this message translates to:
  /// **'Credentials'**
  String get settingsNavCredentials;

  /// No description provided for @settingsScopeTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a host'**
  String get settingsScopeTitle;

  /// No description provided for @settingsScopeHint.
  ///
  /// In en, this message translates to:
  /// **'These settings pages describe the chosen host - independent of the host Chat uses.'**
  String get settingsScopeHint;

  /// No description provided for @settingsScopeFollowActive.
  ///
  /// In en, this message translates to:
  /// **'Follow the active host'**
  String get settingsScopeFollowActive;

  /// No description provided for @settingsLoopbackHint.
  ///
  /// In en, this message translates to:
  /// **'settings/credentials are loopback-only on the host; connect via adb reverse'**
  String get settingsLoopbackHint;

  /// No description provided for @setChatHost.
  ///
  /// In en, this message translates to:
  /// **'Set as chat host'**
  String get setChatHost;

  /// No description provided for @addBackend.
  ///
  /// In en, this message translates to:
  /// **'Add host'**
  String get addBackend;

  /// No description provided for @editBackend.
  ///
  /// In en, this message translates to:
  /// **'Edit host'**
  String get editBackend;

  /// No description provided for @removeActiveBackendFirst.
  ///
  /// In en, this message translates to:
  /// **'Switch away before removing the active host.'**
  String get removeActiveBackendFirst;

  /// No description provided for @cannotRemoveLastBackend.
  ///
  /// In en, this message translates to:
  /// **'The last host cannot be removed.'**
  String get cannotRemoveLastBackend;

  /// Error displayed when the host registry JSON file is unparseable.
  ///
  /// In en, this message translates to:
  /// **'Host configuration file contains invalid JSON.'**
  String get backendErrorInvalidJson;

  /// Error displayed when the host registry JSON has invalid fields or shape.
  ///
  /// In en, this message translates to:
  /// **'Host configuration file contains malformed data.'**
  String get backendErrorMalformedEntry;

  /// Error displayed when a host URL is invalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid host base URL: {baseUrl}'**
  String backendErrorBadBaseUrl(String baseUrl);

  /// Error displayed when a host URL is invalid without detail.
  ///
  /// In en, this message translates to:
  /// **'Invalid host base URL.'**
  String get backendErrorInvalidBaseUrl;

  /// Error displayed when the host registry contains no entries.
  ///
  /// In en, this message translates to:
  /// **'Host configuration list is empty.'**
  String get backendErrorEmptyList;

  /// Error displayed when reading the host registry file fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to read host configuration file.'**
  String get backendErrorReadFailed;

  /// Error displayed when writing the host registry file fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to save host configuration file.'**
  String get backendErrorWriteFailed;

  /// Error displayed when a host label is empty.
  ///
  /// In en, this message translates to:
  /// **'Host label cannot be empty.'**
  String get backendErrorEmptyLabel;

  /// Error displayed when referring to an unknown host ID.
  ///
  /// In en, this message translates to:
  /// **'Unknown host: {id}'**
  String backendErrorUnknownBackend(String id);

  /// Error displayed when referring to an unknown host.
  ///
  /// In en, this message translates to:
  /// **'Unknown host.'**
  String get backendErrorUnknown;

  /// Generic fallback when a host-configuration failure cannot be classified.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load host configuration.'**
  String get backendErrorLoadFailed;

  /// Error displayed when attempting to activate a disabled host.
  ///
  /// In en, this message translates to:
  /// **'Enable the host before activating it.'**
  String get backendErrorDisabled;

  /// Error displayed when a host ID is duplicated.
  ///
  /// In en, this message translates to:
  /// **'A host with ID “{id}” already exists.'**
  String backendErrorDuplicateId(String id);

  /// No description provided for @backendStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get backendStatusActive;

  /// No description provided for @backendStatusStandby.
  ///
  /// In en, this message translates to:
  /// **'Standby'**
  String get backendStatusStandby;

  /// No description provided for @backendStatusDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get backendStatusDisabled;

  /// No description provided for @backendEnableTooltip.
  ///
  /// In en, this message translates to:
  /// **'Enable this host'**
  String get backendEnableTooltip;

  /// No description provided for @backendDisableTooltip.
  ///
  /// In en, this message translates to:
  /// **'Disable this host'**
  String get backendDisableTooltip;

  /// No description provided for @hostSettingsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Host settings unavailable'**
  String get hostSettingsUnavailable;

  /// No description provided for @hostSettingsUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'The host did not answer. Repoint it, or choose another host.'**
  String get hostSettingsUnavailableBody;

  /// No description provided for @hostWritesLabel.
  ///
  /// In en, this message translates to:
  /// **'Host writes'**
  String get hostWritesLabel;

  /// No description provided for @hostWritesDescription.
  ///
  /// In en, this message translates to:
  /// **'Whether the host accepts settings and credential writes.'**
  String get hostWritesDescription;

  /// No description provided for @writableValue.
  ///
  /// In en, this message translates to:
  /// **'Writable'**
  String get writableValue;

  /// No description provided for @readOnlyValue.
  ///
  /// In en, this message translates to:
  /// **'Read-only'**
  String get readOnlyValue;

  /// No description provided for @settingsDocumentLabel.
  ///
  /// In en, this message translates to:
  /// **'Settings document'**
  String get settingsDocumentLabel;

  /// No description provided for @settingsDocumentDescription.
  ///
  /// In en, this message translates to:
  /// **'Whether a user settings document backs the namespaces.'**
  String get settingsDocumentDescription;

  /// No description provided for @presentValue.
  ///
  /// In en, this message translates to:
  /// **'Present'**
  String get presentValue;

  /// No description provided for @noneValue.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get noneValue;

  /// No description provided for @generalIntro.
  ///
  /// In en, this message translates to:
  /// **'New-session defaults and the host settings plane.'**
  String get generalIntro;

  /// No description provided for @busyPreferenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Enter behavior while busy'**
  String get busyPreferenceLabel;

  /// No description provided for @busyPreferenceDescription.
  ///
  /// In en, this message translates to:
  /// **'Busy only; Cmd/Ctrl+Enter uses the other behavior'**
  String get busyPreferenceDescription;

  /// No description provided for @busyBehaviorQueue.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get busyBehaviorQueue;

  /// No description provided for @busyBehaviorSteer.
  ///
  /// In en, this message translates to:
  /// **'Steer'**
  String get busyBehaviorSteer;

  /// No description provided for @agentPresetPreferenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Agent preset'**
  String get agentPresetPreferenceLabel;

  /// No description provided for @agentPresetPreferenceDescription.
  ///
  /// In en, this message translates to:
  /// **'Applies to sessions you start from now on. Running sessions keep the preset they began with.'**
  String get agentPresetPreferenceDescription;

  /// No description provided for @agentPresetsIntro.
  ///
  /// In en, this message translates to:
  /// **'A preset is the plugin composition one session\'\'s agent runs — its tools, prompt, and capabilities. Duplicate an existing one and make it yours, or let the agent draft one for you in Creator mode.'**
  String get agentPresetsIntro;

  /// No description provided for @presetGroupBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get presetGroupBuiltIn;

  /// No description provided for @presetGroupCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get presetGroupCustom;

  /// No description provided for @presetsFooter.
  ///
  /// In en, this message translates to:
  /// **'Presets are authored on the host: copy, edit, and delete them from the desktop settings.'**
  String get presetsFooter;

  /// No description provided for @noDescription.
  ///
  /// In en, this message translates to:
  /// **'No description.'**
  String get noDescription;

  /// No description provided for @presetBrokenBadge.
  ///
  /// In en, this message translates to:
  /// **'Failed to load'**
  String get presetBrokenBadge;

  /// No description provided for @presetInUseBadge.
  ///
  /// In en, this message translates to:
  /// **'In use'**
  String get presetInUseBadge;

  /// No description provided for @pluginsIntro.
  ///
  /// In en, this message translates to:
  /// **'Configure and inspect the plugins installed in this deployment.'**
  String get pluginsIntro;

  /// No description provided for @noPluginSettings.
  ///
  /// In en, this message translates to:
  /// **'This deployment exposes no plugin settings.'**
  String get noPluginSettings;

  /// Settings section title listing the host's loaded plugins and agent-preset compositions.
  ///
  /// In en, this message translates to:
  /// **'Plugin inventory'**
  String get settingsSectionPluginInventory;

  /// Settings section intro describing what the read-only plugin inventory covers.
  ///
  /// In en, this message translates to:
  /// **'The plugins this host loads and the composition each agent preset builds.'**
  String get pluginInventoryIntro;

  /// Notice stating the inventory surface cannot change plugin configuration.
  ///
  /// In en, this message translates to:
  /// **'Read-only. Enable, disable, and configure plugins on the host.'**
  String get pluginInventoryReadOnlyNotice;

  /// Placeholder and accessible name for the inventory filter field.
  ///
  /// In en, this message translates to:
  /// **'Search module name or entry ID'**
  String get pluginInventorySearchHint;

  /// Loading state while the plugin inventory is being read.
  ///
  /// In en, this message translates to:
  /// **'Reading plugins…'**
  String get pluginInventoryLoading;

  /// Empty state when the snapshot carries no entries and no presets.
  ///
  /// In en, this message translates to:
  /// **'This host exposes no plugins.'**
  String get pluginInventoryEmpty;

  /// Empty state when the inventory query matches nothing.
  ///
  /// In en, this message translates to:
  /// **'No plugins match this search.'**
  String get pluginInventoryNoMatch;

  /// Generic failure state for the inventory read; deliberately omits transport details.
  ///
  /// In en, this message translates to:
  /// **'Plugins are temporarily unavailable.'**
  String get pluginInventoryLoadFailed;

  /// Enablement tag for an unconditionally enabled plugin.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get pluginInventoryEnabledTag;

  /// Enablement tag for a disabled plugin.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get pluginInventoryDisabledTag;

  /// Enablement tag for a plugin gated by an unresolved condition.
  ///
  /// In en, this message translates to:
  /// **'Conditional'**
  String get pluginInventoryConditionalTag;

  /// Tag replacing the enablement tag when the plugin's root fiber failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get pluginInventoryFailedTag;

  /// Group title for agent-preset plugin compositions.
  ///
  /// In en, this message translates to:
  /// **'Session plugins'**
  String get pluginInventoryPresetGroupTitle;

  /// Group subtitle explaining preset compositions are per session.
  ///
  /// In en, this message translates to:
  /// **'Composed per session by agent presets.'**
  String get pluginInventoryPresetGroupIntro;

  /// Group title for the Loader's global plugin entries.
  ///
  /// In en, this message translates to:
  /// **'Global plugins'**
  String get pluginInventoryGlobalGroupTitle;

  /// Group subtitle explaining the global plugin plane.
  ///
  /// In en, this message translates to:
  /// **'Shared by the system and every session.'**
  String get pluginInventoryGlobalGroupIntro;

  /// Plugin count for a group or preset.
  ///
  /// In en, this message translates to:
  /// **'{count} plugins'**
  String pluginInventoryPluginCount(int count);

  /// Count of failed plugin entries in the global group.
  ///
  /// In en, this message translates to:
  /// **'{count} failed'**
  String pluginInventoryFailedCount(int count);

  /// Badge on the agent preset a session naming no preset composes.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get pluginInventoryDefaultBadge;

  /// Label prefixing the host-reported reason a preset composition cannot be read.
  ///
  /// In en, this message translates to:
  /// **'Composition unavailable'**
  String get pluginInventoryPresetBrokenLabel;

  /// Detail label for the full module specifier.
  ///
  /// In en, this message translates to:
  /// **'Module'**
  String get pluginInventoryModuleLabel;

  /// Detail label for the plugin's root-fiber phase.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get pluginInventoryStatusLabel;

  /// Detail label for a preset row's disabled condition expression.
  ///
  /// In en, this message translates to:
  /// **'Disabled when'**
  String get pluginInventoryConditionLabel;

  /// Fiber phase label: the entry is waiting on dependencies.
  ///
  /// In en, this message translates to:
  /// **'Waiting for dependencies'**
  String get pluginInventoryPhasePending;

  /// Fiber phase label: the entry is loading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get pluginInventoryPhaseLoading;

  /// Fiber phase label: the entry's root fiber is active.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get pluginInventoryPhaseActive;

  /// Fiber phase label: the entry's root fiber failed to start.
  ///
  /// In en, this message translates to:
  /// **'Failed to start'**
  String get pluginInventoryPhaseFailed;

  /// Fiber phase label: the entry's root fiber is unloading.
  ///
  /// In en, this message translates to:
  /// **'Unloading'**
  String get pluginInventoryPhaseUnloading;

  /// No description provided for @modelsIntro.
  ///
  /// In en, this message translates to:
  /// **'Enter your API keys to use models from the following providers.'**
  String get modelsIntro;

  /// No description provided for @settingsReadOnlyNotice.
  ///
  /// In en, this message translates to:
  /// **'The settings document is read-only in this deployment.'**
  String get settingsReadOnlyNotice;

  /// No description provided for @modelsFooter.
  ///
  /// In en, this message translates to:
  /// **'Provider credentials live on the host; the Providers section below adds, keys, and removes them from this device.'**
  String get modelsFooter;

  /// No description provided for @apiKeyConfigured.
  ///
  /// In en, this message translates to:
  /// **'API key configured'**
  String get apiKeyConfigured;

  /// No description provided for @apiKeyMissing.
  ///
  /// In en, this message translates to:
  /// **'API key missing'**
  String get apiKeyMissing;

  /// No description provided for @credentialsIntro.
  ///
  /// In en, this message translates to:
  /// **'Secret references named by the host namespaces.'**
  String get credentialsIntro;

  /// No description provided for @noCredentialsReferenced.
  ///
  /// In en, this message translates to:
  /// **'No credentials referenced.'**
  String get noCredentialsReferenced;

  /// No description provided for @patchKey.
  ///
  /// In en, this message translates to:
  /// **'Patch key'**
  String get patchKey;

  /// No description provided for @replaceSection.
  ///
  /// In en, this message translates to:
  /// **'Replace section'**
  String get replaceSection;

  /// No description provided for @topLevelKey.
  ///
  /// In en, this message translates to:
  /// **'Top-level key'**
  String get topLevelKey;

  /// No description provided for @wholeUserLayerJson.
  ///
  /// In en, this message translates to:
  /// **'Whole user-layer JSON object'**
  String get wholeUserLayerJson;

  /// No description provided for @jsonValue.
  ///
  /// In en, this message translates to:
  /// **'JSON value'**
  String get jsonValue;

  /// No description provided for @jsonKeyValueExampleHint.
  ///
  /// In en, this message translates to:
  /// **'\'{\' \"key\": value \'}\''**
  String get jsonKeyValueExampleHint;

  /// No description provided for @jsonValueExampleHint.
  ///
  /// In en, this message translates to:
  /// **'true / 42 / \"text\" / \'{\'…\'}\''**
  String get jsonValueExampleHint;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @stateConfigured.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get stateConfigured;

  /// No description provided for @stateNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get stateNotSet;

  /// No description provided for @credentialReadOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Read-only on this connection; the stored value cannot be changed from this client.'**
  String get credentialReadOnlyHint;

  /// No description provided for @unset.
  ///
  /// In en, this message translates to:
  /// **'Unset'**
  String get unset;

  /// No description provided for @secretValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Secret value'**
  String get secretValueLabel;

  /// No description provided for @secretValueHint.
  ///
  /// In en, this message translates to:
  /// **'secret value'**
  String get secretValueHint;

  /// No description provided for @secretValueHintLine.
  ///
  /// In en, this message translates to:
  /// **'Stored on the host; the value never rides a response.'**
  String get secretValueHintLine;

  /// No description provided for @backendLabel.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get backendLabel;

  /// No description provided for @backendLabelHint.
  ///
  /// In en, this message translates to:
  /// **'Laptop host, build box, …'**
  String get backendLabelHint;

  /// No description provided for @backendBaseUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get backendBaseUrlLabel;

  /// No description provided for @backendBaseUrlHint.
  ///
  /// In en, this message translates to:
  /// **'http://127.0.0.1:3080'**
  String get backendBaseUrlHint;

  /// No description provided for @baseUrlDerivationHint.
  ///
  /// In en, this message translates to:
  /// **'RPC and event paths derive from this base.'**
  String get baseUrlDerivationHint;

  /// No description provided for @baseUrlValidHint.
  ///
  /// In en, this message translates to:
  /// **'http or https with a host, e.g. http://127.0.0.1:3080'**
  String get baseUrlValidHint;

  /// No description provided for @backendTrustCertificateTitle.
  ///
  /// In en, this message translates to:
  /// **'Trust this host\'\'s certificate'**
  String get backendTrustCertificateTitle;

  /// No description provided for @backendTrustCertificateDescription.
  ///
  /// In en, this message translates to:
  /// **'Accept this host\'\'s TLS certificate even when Android cannot verify it — for a self-signed or internal-CA gateway. Only this host is affected, and anyone who can intercept the connection could impersonate it. Leave off unless you control the gateway.'**
  String get backendTrustCertificateDescription;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @userLayerLabel.
  ///
  /// In en, this message translates to:
  /// **'user layer'**
  String get userLayerLabel;

  /// No description provided for @credentialMetaConfigured.
  ///
  /// In en, this message translates to:
  /// **'configured'**
  String get credentialMetaConfigured;

  /// No description provided for @credentialMetaNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'not configured'**
  String get credentialMetaNotConfigured;

  /// No description provided for @credentialMetaWritable.
  ///
  /// In en, this message translates to:
  /// **'writable'**
  String get credentialMetaWritable;

  /// No description provided for @credentialMetaReadOnly.
  ///
  /// In en, this message translates to:
  /// **'read-only'**
  String get credentialMetaReadOnly;

  /// No description provided for @workspacesNavTitle.
  ///
  /// In en, this message translates to:
  /// **'Workspaces'**
  String get workspacesNavTitle;

  /// No description provided for @searchWorkspacesHint.
  ///
  /// In en, this message translates to:
  /// **'Search workspaces...'**
  String get searchWorkspacesHint;

  /// No description provided for @noMatchingWorkspaces.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get noMatchingWorkspaces;

  /// No description provided for @noWorkspacesYet.
  ///
  /// In en, this message translates to:
  /// **'No workspaces yet'**
  String get noWorkspacesYet;

  /// No description provided for @moveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get moveUp;

  /// No description provided for @moveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get moveDown;

  /// No description provided for @deleteWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Delete workspace'**
  String get deleteWorkspace;

  /// No description provided for @renameWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Rename workspace'**
  String get renameWorkspace;

  /// No description provided for @renameWorkspaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename workspace'**
  String get renameWorkspaceTitle;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get newFolder;

  /// No description provided for @untitledFolderHint.
  ///
  /// In en, this message translates to:
  /// **'Untitled folder'**
  String get untitledFolderHint;

  /// No description provided for @homeCrumb.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeCrumb;

  /// No description provided for @selectWorkspaceDirectoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Workspace Directory'**
  String get selectWorkspaceDirectoryTitle;

  /// No description provided for @editPathTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit path'**
  String get editPathTooltip;

  /// No description provided for @unableToLoadDirectory.
  ///
  /// In en, this message translates to:
  /// **'Unable to load directory'**
  String get unableToLoadDirectory;

  /// No description provided for @noFolders.
  ///
  /// In en, this message translates to:
  /// **'No folders'**
  String get noFolders;

  /// No description provided for @tooManyFoldersHint.
  ///
  /// In en, this message translates to:
  /// **'Too many folders to list; only the beginning is shown.'**
  String get tooManyFoldersHint;

  /// No description provided for @showHiddenFiles.
  ///
  /// In en, this message translates to:
  /// **'Show hidden files'**
  String get showHiddenFiles;

  /// No description provided for @pathLabel.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get pathLabel;

  /// No description provided for @ungroupedLabel.
  ///
  /// In en, this message translates to:
  /// **'Ungrouped'**
  String get ungroupedLabel;

  /// No description provided for @openSidebar.
  ///
  /// In en, this message translates to:
  /// **'Open sidebar'**
  String get openSidebar;

  /// No description provided for @collapseSidebar.
  ///
  /// In en, this message translates to:
  /// **'Collapse sidebar'**
  String get collapseSidebar;

  /// No description provided for @newSession.
  ///
  /// In en, this message translates to:
  /// **'New session'**
  String get newSession;

  /// No description provided for @searchSessions.
  ///
  /// In en, this message translates to:
  /// **'Search sessions'**
  String get searchSessions;

  /// No description provided for @searchSessionsHint.
  ///
  /// In en, this message translates to:
  /// **'Search sessions...'**
  String get searchSessionsHint;

  /// No description provided for @noSessionsYet.
  ///
  /// In en, this message translates to:
  /// **'No sessions yet'**
  String get noSessionsYet;

  /// No description provided for @noMatchingSessions.
  ///
  /// In en, this message translates to:
  /// **'No matching sessions'**
  String get noMatchingSessions;

  /// No description provided for @relativeTimeNow.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get relativeTimeNow;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{minutes}min'**
  String relativeTimeMinutes(int minutes);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{hours}h'**
  String relativeTimeHours(int hours);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{days}d'**
  String relativeTimeDays(int days);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{months}mo'**
  String relativeTimeMonths(int months);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{years}y'**
  String relativeTimeYears(int years);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 session} other{{count} sessions}}'**
  String sessionCount(int count);

  /// No description provided for @showLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get showLess;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Show all {count}'**
  String showAll(int count);

  /// No description provided for @noWorkspacesRegistered.
  ///
  /// In en, this message translates to:
  /// **'No workspaces registered.'**
  String get noWorkspacesRegistered;

  /// No description provided for @noWorkspacesRegisteredBody.
  ///
  /// In en, this message translates to:
  /// **'Use the Workspaces tab to register a directory first, or choose Default to create an unaccounted session.'**
  String get noWorkspacesRegisteredBody;

  /// No description provided for @chooseWorkspaceOrDefault.
  ///
  /// In en, this message translates to:
  /// **'Choose a workspace or keep the default.'**
  String get chooseWorkspaceOrDefault;

  /// No description provided for @subagentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Subagents'**
  String get subagentsTitle;

  /// No description provided for @selectParentSession.
  ///
  /// In en, this message translates to:
  /// **'Select a parent session'**
  String get selectParentSession;

  /// No description provided for @noSubagents.
  ///
  /// In en, this message translates to:
  /// **'No subagents'**
  String get noSubagents;

  /// No description provided for @loadingSubagents.
  ///
  /// In en, this message translates to:
  /// **'Loading subagents…'**
  String get loadingSubagents;

  /// No description provided for @unableToLoadSubagents.
  ///
  /// In en, this message translates to:
  /// **'Unable to load subagents'**
  String get unableToLoadSubagents;

  /// No description provided for @messageSelectedSubagentHint.
  ///
  /// In en, this message translates to:
  /// **'Message selected subagent'**
  String get messageSelectedSubagentHint;

  /// No description provided for @sending.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get sending;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @stopTooltip.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stopTooltip;

  /// No description provided for @modeOneShot.
  ///
  /// In en, this message translates to:
  /// **'one-shot'**
  String get modeOneShot;

  /// No description provided for @modeContinuable.
  ///
  /// In en, this message translates to:
  /// **'continuable'**
  String get modeContinuable;

  /// No description provided for @activityRunning.
  ///
  /// In en, this message translates to:
  /// **'running'**
  String get activityRunning;

  /// No description provided for @activityNotRunning.
  ///
  /// In en, this message translates to:
  /// **'not running'**
  String get activityNotRunning;

  /// No description provided for @diagnosticCorrupt.
  ///
  /// In en, this message translates to:
  /// **'corrupted session record'**
  String get diagnosticCorrupt;

  /// No description provided for @diagnosticUnsupported.
  ///
  /// In en, this message translates to:
  /// **'unsupported subagent record version'**
  String get diagnosticUnsupported;

  /// No description provided for @diagnosticUnavailable.
  ///
  /// In en, this message translates to:
  /// **'session record temporarily unavailable'**
  String get diagnosticUnavailable;

  /// No description provided for @oneShotRecordTitle.
  ///
  /// In en, this message translates to:
  /// **'One-shot subagent record'**
  String get oneShotRecordTitle;

  /// No description provided for @parentUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'This subagent is read-only for now'**
  String get parentUnavailableTitle;

  /// No description provided for @oneShotRecordBody.
  ///
  /// In en, this message translates to:
  /// **'One-shot tasks do not accept follow-ups; review the full execution record here.'**
  String get oneShotRecordBody;

  /// No description provided for @parentUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'The parent session is offline; reopen it to continue sending messages.'**
  String get parentUnavailableBody;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'v{version}'**
  String backendVersion(String version);

  /// No description provided for @outlineTooltip.
  ///
  /// In en, this message translates to:
  /// **'Outline'**
  String get outlineTooltip;

  /// No description provided for @subagentsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Subagents'**
  String get subagentsTooltip;

  /// Tooltip for the phone app bar overflow menu holding the session verbs.
  ///
  /// In en, this message translates to:
  /// **'Session menu'**
  String get sessionMenuTooltip;

  /// No description provided for @renameSession.
  ///
  /// In en, this message translates to:
  /// **'Rename session'**
  String get renameSession;

  /// No description provided for @forkSession.
  ///
  /// In en, this message translates to:
  /// **'Fork session'**
  String get forkSession;

  /// No description provided for @archiveSession.
  ///
  /// In en, this message translates to:
  /// **'Archive session'**
  String get archiveSession;

  /// No description provided for @archiveSessionBody.
  ///
  /// In en, this message translates to:
  /// **'The session log and its workspace seat are kept; this row is hidden from all grouping surfaces.'**
  String get archiveSessionBody;

  /// No description provided for @archive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive;

  /// No description provided for @expandAll.
  ///
  /// In en, this message translates to:
  /// **'Expand all'**
  String get expandAll;

  /// No description provided for @planBadge.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get planBadge;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **' · {name}'**
  String imagePlaceholderSuffix(String name);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'image {width}×{height} ({bytes} bytes){suffix}'**
  String imageLoadingPlaceholder(
    int bytes,
    int height,
    String suffix,
    int width,
  );

  /// No description provided for @semanticsRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get semanticsRunning;

  /// No description provided for @semanticsFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get semanticsFailed;

  /// No description provided for @inputLabel.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get inputLabel;

  /// No description provided for @diffLabel.
  ///
  /// In en, this message translates to:
  /// **'Diff'**
  String get diffLabel;

  /// No description provided for @viewDiff.
  ///
  /// In en, this message translates to:
  /// **'Diff'**
  String get viewDiff;

  /// No description provided for @viewFullFile.
  ///
  /// In en, this message translates to:
  /// **'Full file'**
  String get viewFullFile;

  /// No description provided for @outputLabel.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get outputLabel;

  /// No description provided for @runStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Running…'**
  String get runStatusRunning;

  /// No description provided for @turnStatusWorking.
  ///
  /// In en, this message translates to:
  /// **'Deep diving…'**
  String get turnStatusWorking;

  /// No description provided for @runStatusDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get runStatusDone;

  /// No description provided for @runStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get runStatusFailed;

  /// No description provided for @pauseGoal.
  ///
  /// In en, this message translates to:
  /// **'Pause goal'**
  String get pauseGoal;

  /// No description provided for @resumeGoal.
  ///
  /// In en, this message translates to:
  /// **'Resume goal'**
  String get resumeGoal;

  /// No description provided for @clearGoal.
  ///
  /// In en, this message translates to:
  /// **'Clear goal'**
  String get clearGoal;

  /// No description provided for @openGoal.
  ///
  /// In en, this message translates to:
  /// **'Open goal'**
  String get openGoal;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 queued message} other{{count} queued messages}}'**
  String queuedMessagesCount(int count);

  /// No description provided for @editQueuedMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Edit queued message'**
  String get editQueuedMessageHint;

  /// No description provided for @saveQueuedMessage.
  ///
  /// In en, this message translates to:
  /// **'Save queued message'**
  String get saveQueuedMessage;

  /// No description provided for @cancelEdit.
  ///
  /// In en, this message translates to:
  /// **'Cancel editing'**
  String get cancelEdit;

  /// No description provided for @steer.
  ///
  /// In en, this message translates to:
  /// **'Steer'**
  String get steer;

  /// No description provided for @steeringPending.
  ///
  /// In en, this message translates to:
  /// **'Steering'**
  String get steeringPending;

  /// No description provided for @removeQueuedMessage.
  ///
  /// In en, this message translates to:
  /// **'Remove queued message'**
  String get removeQueuedMessage;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Approve tool: {tool}'**
  String approveTool(String tool);

  /// No description provided for @allow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get allow;

  /// No description provided for @answer.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get answer;

  /// No description provided for @planReview.
  ///
  /// In en, this message translates to:
  /// **'Plan review'**
  String get planReview;

  /// No description provided for @skipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get skipped;

  /// No description provided for @answerInstead.
  ///
  /// In en, this message translates to:
  /// **'Answer instead'**
  String get answerInstead;

  /// No description provided for @typeYourAnswerHint.
  ///
  /// In en, this message translates to:
  /// **'Type your answer'**
  String get typeYourAnswerHint;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @questionPrev.
  ///
  /// In en, this message translates to:
  /// **'Previous question'**
  String get questionPrev;

  /// No description provided for @questionNext.
  ///
  /// In en, this message translates to:
  /// **'Next question'**
  String get questionNext;

  /// No description provided for @questionCancel.
  ///
  /// In en, this message translates to:
  /// **'Dismiss all questions'**
  String get questionCancel;

  /// No description provided for @questionRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get questionRecommended;

  /// No description provided for @questionErrorIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Please complete this question first.'**
  String get questionErrorIncomplete;

  /// No description provided for @questionErrorUnanswered.
  ///
  /// In en, this message translates to:
  /// **'Please select an option or enter a custom answer.'**
  String get questionErrorUnanswered;

  /// No description provided for @questionSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get questionSubmit;

  /// No description provided for @questionSubmitNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get questionSubmitNext;

  /// No description provided for @planApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get planApprove;

  /// No description provided for @planDecline.
  ///
  /// In en, this message translates to:
  /// **'Refuse'**
  String get planDecline;

  /// No description provided for @planDiscuss.
  ///
  /// In en, this message translates to:
  /// **'Chat about it'**
  String get planDiscuss;

  /// No description provided for @planPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'describe your task to generate plan'**
  String get planPlaceholder;

  /// No description provided for @messagePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Message the agent'**
  String get messagePlaceholder;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}'**
  String removeImage(String name);

  /// No description provided for @delivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get delivery;

  /// No description provided for @commandsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Commands'**
  String get commandsTooltip;

  /// No description provided for @attachImages.
  ///
  /// In en, this message translates to:
  /// **'Attach images'**
  String get attachImages;

  /// No description provided for @pickFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Pick from gallery'**
  String get pickFromGallery;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'unknown image type for {name}'**
  String unknownImageType(String name);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Before first turn · {count, plural, =1{1 message} other{{count} messages}}'**
  String beforeFirstTurnHeader(int count);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Turn {turn} · {count, plural, =1{1 message} other{{count} messages}} · {toolCount, plural, =1{1 tool} other{{toolCount} tools}}'**
  String turnHeader(int count, int toolCount, int turn);

  /// Failure count appended to a collapsed turn header's tool summary.
  ///
  /// In en, this message translates to:
  /// **'{count} failed'**
  String turnFailedCount(int count);

  /// No description provided for @contextCompacted.
  ///
  /// In en, this message translates to:
  /// **'Context compacted'**
  String get contextCompacted;

  /// Running state summary for /compact command.
  ///
  /// In en, this message translates to:
  /// **'Compacting context…'**
  String get compactionRunning;

  /// Completed compaction caption with items and tokens counts.
  ///
  /// In en, this message translates to:
  /// **'Compacted {items} history items (~{tokens} tokens)'**
  String compactionCompleted(int items, int tokens);

  /// Fallback summary label when compaction counts are missing but summary is expandable.
  ///
  /// In en, this message translates to:
  /// **'View compaction summary'**
  String get compactionViewSummary;

  /// Fallback summary label when both compaction counts and summary are unavailable.
  ///
  /// In en, this message translates to:
  /// **'Compaction summary unavailable'**
  String get compactionSummaryUnavailable;

  /// No description provided for @recallLabel.
  ///
  /// In en, this message translates to:
  /// **'Session recall'**
  String get recallLabel;

  /// No description provided for @contextInjectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Context injection'**
  String get contextInjectionLabel;

  /// No description provided for @chatGoalPhaseActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get chatGoalPhaseActive;

  /// No description provided for @chatGoalPhasePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get chatGoalPhasePaused;

  /// No description provided for @chatGoalPhaseBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get chatGoalPhaseBlocked;

  /// Button to load earlier conversation history at the top of the transcript.
  ///
  /// In en, this message translates to:
  /// **'Load earlier'**
  String get chatLoadOlder;

  /// Progress state while earlier conversation history is being loaded.
  ///
  /// In en, this message translates to:
  /// **'Loading earlier…'**
  String get chatLoadingOlder;

  /// Notice shown at the very top of the transcript when all earlier history has been loaded.
  ///
  /// In en, this message translates to:
  /// **'Beginning of conversation'**
  String get chatBeginningOfHistory;

  /// Retry affordance when loading older history fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load earlier messages. Tap to retry.'**
  String get chatLoadOlderRetry;

  /// No description provided for @queue.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get queue;

  /// No description provided for @thinkLabel.
  ///
  /// In en, this message translates to:
  /// **'Think'**
  String get thinkLabel;

  /// No description provided for @commandPlanDescription.
  ///
  /// In en, this message translates to:
  /// **'Enter or leave plan mode'**
  String get commandPlanDescription;

  /// No description provided for @commandGoalDescription.
  ///
  /// In en, this message translates to:
  /// **'set or view the goal for a long-running task'**
  String get commandGoalDescription;

  /// No description provided for @commandCompactDescription.
  ///
  /// In en, this message translates to:
  /// **'Compact older conversation history'**
  String get commandCompactDescription;

  /// No description provided for @commandPermissionDescription.
  ///
  /// In en, this message translates to:
  /// **'Switch the permission preset (sandbox mode + approval policy)'**
  String get commandPermissionDescription;

  /// No description provided for @commandFeedbackDescription.
  ///
  /// In en, this message translates to:
  /// **'record feedback about this session'**
  String get commandFeedbackDescription;

  /// No description provided for @commandExportDescription.
  ///
  /// In en, this message translates to:
  /// **'Download this session log as a ZIP archive'**
  String get commandExportDescription;

  /// No description provided for @sessionLogExportTooltip.
  ///
  /// In en, this message translates to:
  /// **'Download session log'**
  String get sessionLogExportTooltip;

  /// Confirmation that the session-log archive was written, naming where it landed.
  ///
  /// In en, this message translates to:
  /// **'Session log saved to {location}'**
  String sessionLogExportSaved(String location);

  /// Failure notice when the session-log archive could not be downloaded or saved.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t export the session log'**
  String get sessionLogExportFailed;

  /// Composer refusal for a submission carrying images bound for a host command that does not accept them.
  ///
  /// In en, this message translates to:
  /// **'/{command} does not accept image attachments; remove them first'**
  String commandImagesUnsupported(String command);

  /// No description provided for @parentSession.
  ///
  /// In en, this message translates to:
  /// **'Parent session'**
  String get parentSession;

  /// No description provided for @addWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Add workspace'**
  String get addWorkspace;

  /// No description provided for @searchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchTooltip;

  /// No description provided for @namespaceReadOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Host is read-only on this connection; namespace edits are unavailable.'**
  String get namespaceReadOnlyHint;

  /// Turn boundary micro-label.
  ///
  /// In en, this message translates to:
  /// **'Turn {turn}'**
  String turnNumberLabel(int turn);

  /// No description provided for @attachmentName.
  ///
  /// In en, this message translates to:
  /// **'attachment'**
  String get attachmentName;

  /// Picked image refused: media type not supported.
  ///
  /// In en, this message translates to:
  /// **'{name}: unsupported type {type}'**
  String imageRejectionUnsupported(String name, String type);

  /// Picked image refused: exceeds host byte ceiling.
  ///
  /// In en, this message translates to:
  /// **'{name}: exceeds {maxBytes} bytes'**
  String imageRejectionTooLarge(String name, int maxBytes);

  /// Picked image refused: composer seat full.
  ///
  /// In en, this message translates to:
  /// **'Only {room} more image(s) allowed per message'**
  String imageRejectionNoRoom(int room);

  /// No description provided for @commandFailed.
  ///
  /// In en, this message translates to:
  /// **'Command failed'**
  String get commandFailed;

  /// Turn/end error line with host detail.
  ///
  /// In en, this message translates to:
  /// **'This turn failed: {detail}'**
  String turnFailed(String detail);

  /// No description provided for @unknownModelFailure.
  ///
  /// In en, this message translates to:
  /// **'unknown model failure'**
  String get unknownModelFailure;

  /// No description provided for @turnStopped.
  ///
  /// In en, this message translates to:
  /// **'Turn stopped'**
  String get turnStopped;

  /// No description provided for @turnInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Turn interrupted'**
  String get turnInterrupted;

  /// No description provided for @turnBlocked.
  ///
  /// In en, this message translates to:
  /// **'Turn blocked'**
  String get turnBlocked;

  /// No description provided for @turnMaxTokens.
  ///
  /// In en, this message translates to:
  /// **'Output token limit reached'**
  String get turnMaxTokens;

  /// No description provided for @turnCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn complete'**
  String get turnCompleteTitle;

  /// No description provided for @turnCompletionChannel.
  ///
  /// In en, this message translates to:
  /// **'Turn completion'**
  String get turnCompletionChannel;

  /// No description provided for @turnCompletionChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'Notifies when a running conversation turn finishes.'**
  String get turnCompletionChannelDescription;

  /// No description provided for @otherTurnCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'New turn in another session'**
  String get otherTurnCompleteTitle;

  /// No description provided for @approvalRequestedTitle.
  ///
  /// In en, this message translates to:
  /// **'Approval requested'**
  String get approvalRequestedTitle;

  /// No description provided for @planReviewRequestedTitle.
  ///
  /// In en, this message translates to:
  /// **'Plan review requested'**
  String get planReviewRequestedTitle;

  /// No description provided for @approvalChannel.
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get approvalChannel;

  /// No description provided for @approvalChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'Notifies when a session waits on your approval.'**
  String get approvalChannelDescription;

  /// No description provided for @planReviewChannel.
  ///
  /// In en, this message translates to:
  /// **'Plan reviews'**
  String get planReviewChannel;

  /// No description provided for @planReviewChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'Notifies when a session waits on your plan review.'**
  String get planReviewChannelDescription;

  /// No description provided for @notificationDismissTooltip.
  ///
  /// In en, this message translates to:
  /// **'Dismiss notification'**
  String get notificationDismissTooltip;

  /// No description provided for @workingChannel.
  ///
  /// In en, this message translates to:
  /// **'Working sessions'**
  String get workingChannel;

  /// No description provided for @workingChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'Shows a silent, persistent notice while a session is working or waiting on you.'**
  String get workingChannelDescription;

  /// No description provided for @workingNotificationBody.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get workingNotificationBody;

  /// No description provided for @waitingApprovalBody.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your approval'**
  String get waitingApprovalBody;

  /// No description provided for @waitingPlanReviewBody.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your plan review'**
  String get waitingPlanReviewBody;

  /// No description provided for @waitingAnswerBody.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your answer'**
  String get waitingAnswerBody;

  /// Tooltip for the floating button that scrolls the timeline to its newest message.
  ///
  /// In en, this message translates to:
  /// **'Jump to bottom'**
  String get jumpToBottomTooltip;

  /// No description provided for @settingsSectionAsr.
  ///
  /// In en, this message translates to:
  /// **'Voice recognition'**
  String get settingsSectionAsr;

  /// No description provided for @asrModelsTitle.
  ///
  /// In en, this message translates to:
  /// **'ASR Models'**
  String get asrModelsTitle;

  /// No description provided for @asrModelsDescription.
  ///
  /// In en, this message translates to:
  /// **'Download and manage on-device speech recognition models for offline voice input.'**
  String get asrModelsDescription;

  /// Installed count badge for ASR models.
  ///
  /// In en, this message translates to:
  /// **'{installed}/{total} installed'**
  String asrInstalledCount(int installed, int total);

  /// No description provided for @asrDefaultSource.
  ///
  /// In en, this message translates to:
  /// **'Default download source'**
  String get asrDefaultSource;

  /// No description provided for @asrDefaultSourceDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose preferred model mirror repository'**
  String get asrDefaultSourceDesc;

  /// No description provided for @asrAllowCellular.
  ///
  /// In en, this message translates to:
  /// **'Allow cellular downloads'**
  String get asrAllowCellular;

  /// No description provided for @asrAllowCellularDesc.
  ///
  /// In en, this message translates to:
  /// **'Download models over mobile data (may incur carrier data fees)'**
  String get asrAllowCellularDesc;

  /// No description provided for @asrModelStatusIdle.
  ///
  /// In en, this message translates to:
  /// **'Not downloaded'**
  String get asrModelStatusIdle;

  /// No description provided for @asrModelStatusDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get asrModelStatusDownloading;

  /// No description provided for @asrModelStatusDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get asrModelStatusDownloaded;

  /// No description provided for @asrModelStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get asrModelStatusFailed;

  /// No description provided for @asrModelStatusCanceled.
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get asrModelStatusCanceled;

  /// No description provided for @asrModelDiscontinued.
  ///
  /// In en, this message translates to:
  /// **'Discontinued · local copy only'**
  String get asrModelDiscontinued;

  /// No description provided for @asrDownloadButton.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get asrDownloadButton;

  /// No description provided for @asrCancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get asrCancelButton;

  /// No description provided for @asrDeleteButton.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get asrDeleteButton;

  /// No description provided for @asrRetryButton.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get asrRetryButton;

  /// Button to retry download using alternate source.
  ///
  /// In en, this message translates to:
  /// **'Retry from {source}'**
  String asrSwitchSourceRetry(String source);

  /// No description provided for @asrDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete model'**
  String get asrDeleteConfirmTitle;

  /// Confirmation dialog body for deleting an ASR model.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete {modelName}? You can download it again anytime.'**
  String asrDeleteConfirmBody(String modelName);

  /// Disk usage label.
  ///
  /// In en, this message translates to:
  /// **'Disk: {size}'**
  String asrDiskUsage(String size);

  /// Model source label.
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String asrSourceLabel(String source);

  /// No description provided for @asrLanguagesLabel.
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get asrLanguagesLabel;

  /// No description provided for @asrLicenseLabel.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get asrLicenseLabel;

  /// Download speed label.
  ///
  /// In en, this message translates to:
  /// **'{speed}/s'**
  String asrSpeedLabel(String speed);

  /// No description provided for @voiceInputTooltip.
  ///
  /// In en, this message translates to:
  /// **'Voice input'**
  String get voiceInputTooltip;

  /// No description provided for @voiceInputNoModelTitle.
  ///
  /// In en, this message translates to:
  /// **'Speech Model Required'**
  String get voiceInputNoModelTitle;

  /// No description provided for @voiceInputNoModelBody.
  ///
  /// In en, this message translates to:
  /// **'Download an on-device speech recognition model in Settings to enable offline voice input.'**
  String get voiceInputNoModelBody;

  /// No description provided for @voiceInputGoToSettings.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings'**
  String get voiceInputGoToSettings;

  /// No description provided for @voiceInputCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get voiceInputCancel;

  /// No description provided for @voiceInputDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get voiceInputDone;

  /// No description provided for @voiceInputSlideToSend.
  ///
  /// In en, this message translates to:
  /// **'Release to send · slide up to cancel'**
  String get voiceInputSlideToSend;

  /// No description provided for @voiceInputReleaseToCancel.
  ///
  /// In en, this message translates to:
  /// **'Release to cancel'**
  String get voiceInputReleaseToCancel;

  /// No description provided for @voiceInputTapToFinish.
  ///
  /// In en, this message translates to:
  /// **'Tap the mic to finish'**
  String get voiceInputTapToFinish;

  /// No description provided for @voiceInputInitializing.
  ///
  /// In en, this message translates to:
  /// **'Getting ready…'**
  String get voiceInputInitializing;

  /// No description provided for @voiceInputFinalizing.
  ///
  /// In en, this message translates to:
  /// **'Transcribing…'**
  String get voiceInputFinalizing;

  /// No description provided for @voiceInputPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission is required for voice input.'**
  String get voiceInputPermissionDenied;

  /// No description provided for @voiceInputRecordFailed.
  ///
  /// In en, this message translates to:
  /// **'Voice recording could not start. Check that your microphone is available and try again.'**
  String get voiceInputRecordFailed;

  /// No description provided for @voiceInputSilentInput.
  ///
  /// In en, this message translates to:
  /// **'No audio signal detected from the microphone. Check the mic access toggle and that no other app is using it.'**
  String get voiceInputSilentInput;

  /// No description provided for @voiceInputInputFailed.
  ///
  /// In en, this message translates to:
  /// **'Voice input stopped unexpectedly. Please try again.'**
  String get voiceInputInputFailed;

  /// No description provided for @voiceInputModelUnsupported.
  ///
  /// In en, this message translates to:
  /// **'The selected speech model is not supported. Pick another installed model in Settings.'**
  String get voiceInputModelUnsupported;

  /// No description provided for @asrActiveModel.
  ///
  /// In en, this message translates to:
  /// **'Active speech model'**
  String get asrActiveModel;

  /// No description provided for @asrActiveModelDesc.
  ///
  /// In en, this message translates to:
  /// **'Model used for voice transcription in chat.'**
  String get asrActiveModelDesc;

  /// No description provided for @asrNoModelInstalled.
  ///
  /// In en, this message translates to:
  /// **'None (download a model below)'**
  String get asrNoModelInstalled;

  /// No description provided for @asrVoiceInputModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice input mode'**
  String get asrVoiceInputModeTitle;

  /// No description provided for @asrVoiceInputModeDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose whether speech recognition runs on-device or via an online speech service.'**
  String get asrVoiceInputModeDesc;

  /// No description provided for @asrVoiceInputModeOffline.
  ///
  /// In en, this message translates to:
  /// **'On-device'**
  String get asrVoiceInputModeOffline;

  /// No description provided for @asrVoiceInputModeOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get asrVoiceInputModeOnline;

  /// No description provided for @asrOnlineProviderVolcengine.
  ///
  /// In en, this message translates to:
  /// **'Volcengine · Doubao'**
  String get asrOnlineProviderVolcengine;

  /// No description provided for @asrOnlineProviderVolcengineHint.
  ///
  /// In en, this message translates to:
  /// **'Doubao streaming speech recognition, authenticated with an X-Api-Key.'**
  String get asrOnlineProviderVolcengineHint;

  /// No description provided for @asrOnlineProviderTencent.
  ///
  /// In en, this message translates to:
  /// **'Tencent Cloud · Hunyuan'**
  String get asrOnlineProviderTencent;

  /// No description provided for @asrOnlineProviderTencentHint.
  ///
  /// In en, this message translates to:
  /// **'Real-time speech recognition Hy-ASR-3.0-preview, authenticated with signed credentials.'**
  String get asrOnlineProviderTencentHint;

  /// No description provided for @asrOnlineVolcengineApiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get asrOnlineVolcengineApiKeyLabel;

  /// No description provided for @asrOnlineVolcengineApiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'From the Volcengine speech console'**
  String get asrOnlineVolcengineApiKeyHint;

  /// No description provided for @asrOnlineTencentAppIdLabel.
  ///
  /// In en, this message translates to:
  /// **'AppID'**
  String get asrOnlineTencentAppIdLabel;

  /// No description provided for @asrOnlineTencentSecretIdLabel.
  ///
  /// In en, this message translates to:
  /// **'SecretId'**
  String get asrOnlineTencentSecretIdLabel;

  /// No description provided for @asrOnlineTencentSecretKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'SecretKey'**
  String get asrOnlineTencentSecretKeyLabel;

  /// No description provided for @asrOnlineEndpointLabel.
  ///
  /// In en, this message translates to:
  /// **'Endpoint (optional)'**
  String get asrOnlineEndpointLabel;

  /// No description provided for @asrOnlineTencentLimit.
  ///
  /// In en, this message translates to:
  /// **'The Hunyuan preview accepts 16 kHz mono PCM only and recognizes at most 1 minute per session.'**
  String get asrOnlineTencentLimit;

  /// No description provided for @asrOnlinePrivacyNote.
  ///
  /// In en, this message translates to:
  /// **'Keys are stored on this device only; audio is sent only to the selected provider.'**
  String get asrOnlinePrivacyNote;

  /// No description provided for @asrOnlineSaved.
  ///
  /// In en, this message translates to:
  /// **'Voice input settings saved'**
  String get asrOnlineSaved;

  /// No description provided for @voiceInputCloudSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Online Speech Setup Required'**
  String get voiceInputCloudSetupTitle;

  /// No description provided for @voiceInputCloudSetupBody.
  ///
  /// In en, this message translates to:
  /// **'Add your online speech service credentials in Settings to enable online voice input.'**
  String get voiceInputCloudSetupBody;

  /// No description provided for @voiceInputCloudNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Online voice input needs credentials. Add them in Settings → Speech recognition.'**
  String get voiceInputCloudNotConfigured;

  /// No description provided for @voiceInputCloudConnectFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the online speech service. Check your network and credentials, then try again.'**
  String get voiceInputCloudConnectFailed;

  /// No description provided for @voiceInputCloudFailed.
  ///
  /// In en, this message translates to:
  /// **'Online speech recognition failed. Check your credentials and try again.'**
  String get voiceInputCloudFailed;

  /// No description provided for @errorLogsTitle.
  ///
  /// In en, this message translates to:
  /// **'Error Logs'**
  String get errorLogsTitle;

  /// No description provided for @errorLogsDescription.
  ///
  /// In en, this message translates to:
  /// **'View and export application error logs'**
  String get errorLogsDescription;

  /// No description provided for @errorLogsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No Error Logs'**
  String get errorLogsEmptyTitle;

  /// No description provided for @errorLogsEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Application is running smoothly with no errors captured.'**
  String get errorLogsEmptySubtitle;

  /// No description provided for @errorLogsFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get errorLogsFilterAll;

  /// No description provided for @errorLogsFilterFatal.
  ///
  /// In en, this message translates to:
  /// **'Fatal'**
  String get errorLogsFilterFatal;

  /// No description provided for @errorLogsFilterError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get errorLogsFilterError;

  /// No description provided for @errorLogsFilterWarn.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get errorLogsFilterWarn;

  /// No description provided for @errorLogsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search errors or stack trace…'**
  String get errorLogsSearchHint;

  /// No description provided for @errorLogsCopyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy All'**
  String get errorLogsCopyAll;

  /// No description provided for @errorLogsCopyAllSuccess.
  ///
  /// In en, this message translates to:
  /// **'All error logs copied to clipboard'**
  String get errorLogsCopyAllSuccess;

  /// No description provided for @errorLogsCopyEntry.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get errorLogsCopyEntry;

  /// No description provided for @errorLogsCopyEntrySuccess.
  ///
  /// In en, this message translates to:
  /// **'Error details copied to clipboard'**
  String get errorLogsCopyEntrySuccess;

  /// No description provided for @errorLogsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get errorLogsClear;

  /// No description provided for @errorLogsClearConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear Error Logs'**
  String get errorLogsClearConfirmTitle;

  /// No description provided for @errorLogsClearConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear all recorded error logs? This cannot be undone.'**
  String get errorLogsClearConfirmMessage;

  /// No description provided for @errorLogsClearSuccess.
  ///
  /// In en, this message translates to:
  /// **'Error logs cleared'**
  String get errorLogsClearSuccess;

  /// No description provided for @errorLogsStackTrace.
  ///
  /// In en, this message translates to:
  /// **'Stack Trace'**
  String get errorLogsStackTrace;

  /// No description provided for @errorLogsBreadcrumbs.
  ///
  /// In en, this message translates to:
  /// **'Related Logs'**
  String get errorLogsBreadcrumbs;

  /// No description provided for @errorLogsContext.
  ///
  /// In en, this message translates to:
  /// **'Context'**
  String get errorLogsContext;

  /// No description provided for @errorLogsSystemInfo.
  ///
  /// In en, this message translates to:
  /// **'System & Build Info'**
  String get errorLogsSystemInfo;

  /// No description provided for @errorLogsCopySystemInfo.
  ///
  /// In en, this message translates to:
  /// **'Copy System Info'**
  String get errorLogsCopySystemInfo;

  /// No description provided for @errorLogsSystemInfoCopied.
  ///
  /// In en, this message translates to:
  /// **'System info copied to clipboard'**
  String get errorLogsSystemInfoCopied;

  /// Error count badge label.
  ///
  /// In en, this message translates to:
  /// **'{count} errors'**
  String errorLogsCountBadge(int count);

  /// No description provided for @errorLogsNoSearchResults.
  ///
  /// In en, this message translates to:
  /// **'No errors match your filter.'**
  String get errorLogsNoSearchResults;

  /// Button label to preview a generated or edited file.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get previewFile;

  /// Button label to copy file path.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get copyPath;

  /// Button label to copy file content in preview.
  ///
  /// In en, this message translates to:
  /// **'Copy content'**
  String get copyContent;

  /// Feedback message when content is copied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedFeedback;

  /// Error message when file preview cannot be loaded.
  ///
  /// In en, this message translates to:
  /// **'Failed to load file preview'**
  String get filePreviewFailed;

  /// Preview notice for a binary or undecodable file.
  ///
  /// In en, this message translates to:
  /// **'This file isn\'\'t text, so it can\'\'t be previewed.'**
  String get filePreviewBinary;

  /// Preview notice for a zero-byte text file.
  ///
  /// In en, this message translates to:
  /// **'This file is empty.'**
  String get filePreviewEmpty;

  /// Notice banner when file preview is truncated.
  ///
  /// In en, this message translates to:
  /// **'Previewing first {count} lines'**
  String filePreviewTruncated(int count);

  /// Error message when a session write lease is held by another process.
  ///
  /// In en, this message translates to:
  /// **'This session is currently locked by another process or CLI.'**
  String get sessionAlreadyOwnedError;

  /// Headline for a chat action that failed; the host detail follows.
  ///
  /// In en, this message translates to:
  /// **'That action couldn\'\'t be completed.'**
  String get chatActionFailed;

  /// Full-screen error when the chat state stream fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load this conversation.'**
  String get chatLoadFailed;

  /// Notice when system prompt is replaced or appended mid-conversation.
  ///
  /// In en, this message translates to:
  /// **'System prompt updated'**
  String get systemPromptUpdated;

  /// App-bar and entry label for the session trajectory ledger view.
  ///
  /// In en, this message translates to:
  /// **'Trajectory'**
  String get trajectoryTitle;

  /// Placeholder for the trajectory ledger's local search field.
  ///
  /// In en, this message translates to:
  /// **'Search ledger'**
  String get trajectorySearchHint;

  /// Tooltip for the button clearing the trajectory search query.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get trajectorySearchClear;

  /// Trajectory search result count; matches out of the records loaded in the window.
  ///
  /// In en, this message translates to:
  /// **'{matches} of {total}'**
  String trajectorySearchMatches(int matches, int total);

  /// Button loading the previous session history page into the ledger.
  ///
  /// In en, this message translates to:
  /// **'Load older history'**
  String get trajectoryLoadOlder;

  /// Button label while an older history page is in flight.
  ///
  /// In en, this message translates to:
  /// **'Loading older history…'**
  String get trajectoryLoadingOlder;

  /// Retry hint shown when an older history page request failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load older history. Try again.'**
  String get trajectoryLoadOlderFailed;

  /// Empty state when the local ledger search matches nothing.
  ///
  /// In en, this message translates to:
  /// **'No records match this search in the loaded window.'**
  String get trajectoryNoMatches;

  /// Empty state when the session log has produced no ledger records.
  ///
  /// In en, this message translates to:
  /// **'This session has no trajectory records yet.'**
  String get trajectoryEmpty;

  /// Turn rule heading for rows logged before the session's first turn/start.
  ///
  /// In en, this message translates to:
  /// **'Before the first turn'**
  String get trajectoryBeforeFirstTurn;

  /// Turn rule heading naming one turn number.
  ///
  /// In en, this message translates to:
  /// **'Turn {turn}'**
  String trajectoryTurnLabel(int turn);

  /// Turn rule metadata: record and tool counts for one turn.
  ///
  /// In en, this message translates to:
  /// **'{records, plural, =1{1 record} other{{records} records}} · {tools, plural, =1{1 tool} other{{tools} tools}}'**
  String trajectoryTurnSummary(int records, int tools);

  /// Inline marker opening one step inside a turn.
  ///
  /// In en, this message translates to:
  /// **'Step {step}'**
  String trajectoryStepLabel(int step);

  /// Record count shown beside a step marker.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 record} other{{count} records}}'**
  String trajectoryStepRecordCount(int count);

  /// Ledger record kind label for a user prompt.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get trajectoryKindUser;

  /// Ledger record kind label for injected context (non-user role message).
  ///
  /// In en, this message translates to:
  /// **'Context'**
  String get trajectoryKindContext;

  /// Ledger record kind label for an assistant message.
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get trajectoryKindAssistant;

  /// Ledger record kind label for a tool call.
  ///
  /// In en, this message translates to:
  /// **'Tool'**
  String get trajectoryKindTool;

  /// Ledger record kind label for a context compaction.
  ///
  /// In en, this message translates to:
  /// **'Compacted'**
  String get trajectoryKindCompaction;

  /// Ledger record kind label for a host slash command.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get trajectoryKindCommand;

  /// Ledger record kind label for a turn or session error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get trajectoryKindError;

  /// Status shown for an assistant record still receiving tokens.
  ///
  /// In en, this message translates to:
  /// **'Streaming'**
  String get trajectoryStatusStreaming;

  /// Inspector field label for the record's turn number.
  ///
  /// In en, this message translates to:
  /// **'Turn'**
  String get trajectoryFactTurn;

  /// Inspector field label for the record's step number.
  ///
  /// In en, this message translates to:
  /// **'Step'**
  String get trajectoryFactStep;

  /// Inspector field label for the record kind.
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get trajectoryFactKind;

  /// Inspector field label for the record lifecycle state.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get trajectoryFactStatus;

  /// Inspector field label for the record's logged start timestamp.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get trajectoryFactStarted;

  /// Inspector field label for the first model output token of a recorded assistant stream.
  ///
  /// In en, this message translates to:
  /// **'First token'**
  String get trajectoryFactFirstToken;

  /// Inspector field label for a record's own duration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get trajectoryFactDuration;

  /// Inspector field label naming the root call that owns a nested code-dispatch call.
  ///
  /// In en, this message translates to:
  /// **'Parent call'**
  String get trajectoryFactParentCall;

  /// Inspector value for a row that belongs to no logged step.
  ///
  /// In en, this message translates to:
  /// **'Outside a step'**
  String get trajectoryFactOutsideStep;

  /// Inspector value when the session log does not carry the requested fact.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get trajectoryFactUnavailable;

  /// Inspector value when the session log carries no timing boundary for the record.
  ///
  /// In en, this message translates to:
  /// **'Not recorded'**
  String get trajectoryTimingNotRecorded;

  /// Inspector note explaining why a duration cannot be computed.
  ///
  /// In en, this message translates to:
  /// **'The session log carries no settle timestamp for this record.'**
  String get trajectoryDurationNotRecorded;

  /// Inspector section heading for provider token accounting.
  ///
  /// In en, this message translates to:
  /// **'Token usage'**
  String get trajectoryUsageSection;

  /// Inspector notice when a record carries no token accounting.
  ///
  /// In en, this message translates to:
  /// **'The host reported no usage for this record.'**
  String get trajectoryUsageNotReported;

  /// Inspector usage row label for billed input tokens.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get trajectoryUsageInput;

  /// Inspector usage row label for input tokens served from a provider cache.
  ///
  /// In en, this message translates to:
  /// **'Cache read'**
  String get trajectoryUsageCachedRead;

  /// Inspector usage row label for input tokens written into a provider cache.
  ///
  /// In en, this message translates to:
  /// **'Cache write'**
  String get trajectoryUsageCacheWrite;

  /// Inspector usage row label for completion tokens.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get trajectoryUsageOutput;

  /// Inspector usage row label for reasoning tokens within the output count.
  ///
  /// In en, this message translates to:
  /// **'Reasoning'**
  String get trajectoryUsageReasoning;

  /// Inspector section heading for a record's full input payload.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get trajectoryInputSection;

  /// Inspector section heading for a record's full output payload.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get trajectoryOutputSection;

  /// Token count shown in the inspector.
  ///
  /// In en, this message translates to:
  /// **'{value} tok'**
  String trajectoryTokenCount(int value);

  /// Turn rule token summary: compact billed input and output counts.
  ///
  /// In en, this message translates to:
  /// **'in {input} · out {output}'**
  String trajectoryTurnUsage(String input, String output);

  /// Tooltip for the chat header action that opens the trajectory ledger.
  ///
  /// In en, this message translates to:
  /// **'Trajectory'**
  String get trajectoryEntryTooltip;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Providers'**
  String get settingsSectionProviders;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Add a provider, enter its API key, and discover the models it serves.'**
  String get providersIntro;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'The settings document is read-only in this deployment.'**
  String get providersReadOnlyNotice;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t load providers: {error}'**
  String providersLoadFailed(String error);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Credential state unavailable: {error}'**
  String providerCredentialUnavailable(String error);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get providerStateLive;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Dormant'**
  String get providerStateDormant;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Hand-declared'**
  String get providerDeclared;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Needs repair: {error}'**
  String providerNeedsRepair(String error);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'No configurable providers on this host.'**
  String get providersEmpty;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Add provider'**
  String get addProvider;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Settings family'**
  String get addProviderFamilyLabel;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Route id'**
  String get addProviderRouteLabel;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'acme-gateway'**
  String get addProviderRouteHint;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Use lower-case letters, digits, and single hyphens, starting with a letter.'**
  String get addProviderRouteInvalid;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'That route already exists.'**
  String get addProviderRouteTaken;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Display name (optional)'**
  String get addProviderDisplayNameLabel;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Base URL (optional)'**
  String get addProviderBaseUrlLabel;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Enter an http:// or https:// URL.'**
  String get addProviderBaseUrlInvalid;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Protocol (optional)'**
  String get addProviderProtocolLabel;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Model ids, one per line (optional)'**
  String get addProviderModelsLabel;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'A route the adapter does not already know needs at least one.'**
  String get addProviderModelsHint;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Route {route}'**
  String providerRouteLine(String route);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Key reference {ref}'**
  String providerKeyRefLine(String ref);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'The value goes to the host credential store and is never shown again.'**
  String get providerKeyHint;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Remove provider'**
  String get providerRemoveAction;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String providerRemoveConfirm(String name);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'The stored profile is removed. A stored API key is left in place.'**
  String get providerRemoveBody;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Discover models'**
  String get discoverModels;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'The endpoint advertised no models.'**
  String get discoverModelsEmpty;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Model discovery failed: {error}'**
  String discoverModelsFailed(String error);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Advertised models'**
  String get discoveredModelsTitle;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Context {tokens}'**
  String modelContextWindowLine(int tokens);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Max output {tokens}'**
  String modelMaxTokensLine(int tokens);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Provider routes and profiles live in the host settings document; keys ride the host credential plane.'**
  String get providerFooter;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsSectionAbout;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'App version'**
  String get aboutVersionLabel;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'{version} (build {build})'**
  String aboutVersionLine(String version, String build);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Documentation'**
  String get aboutDocs;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Report a bug or send feedback'**
  String get aboutFeedback;

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t open that link.'**
  String get aboutLinkFailed;

  /// Caption above the produced-file chips a finished turn closes with.
  ///
  /// In en, this message translates to:
  /// **'Files changed'**
  String get producedFilesLabel;

  /// Overflow counter after the produced-file chips shown.
  ///
  /// In en, this message translates to:
  /// **'+ {count, plural, =1{1 file} other{{count} files}}'**
  String producedFilesMore(int count);

  /// Accessible label of one produced-file chip; the name is the path.
  ///
  /// In en, this message translates to:
  /// **'Open {name}'**
  String producedFilesOpen(String name);

  /// Decode throughput on a finalized assistant message's action row.
  ///
  /// In en, this message translates to:
  /// **'{tps} tok/s'**
  String messageTokensPerSecond(String tps);

  /// Reported token total on a finalized assistant message's action row.
  ///
  /// In en, this message translates to:
  /// **'{tokens} tok'**
  String messageTokenUsage(String tokens);

  /// Settings row title for the light/dark/OLED/system theme choice.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearanceTitle;

  /// Theme preference segment for the light color scheme.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsAppearanceLight;

  /// Theme preference segment for the dark color scheme.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsAppearanceDark;

  /// Theme preference segment for the pure-black OLED appearance.
  ///
  /// In en, this message translates to:
  /// **'OLED'**
  String get settingsAppearanceOled;

  /// Theme preference segment following the device setting.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsAppearanceSystem;

  /// Stated when the host does not expose the ui-theme preference field.
  ///
  /// In en, this message translates to:
  /// **'Host theme settings are unavailable.'**
  String get settingsAppearanceUnavailable;

  /// Stated when the host refused the appearance write.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'\'t save the theme choice.'**
  String get settingsAppearanceSaveFailed;

  /// Header band of the card shown while a dynamic Cordis plugin activation waits on the reader's decision.
  ///
  /// In en, this message translates to:
  /// **'Plugin approval'**
  String get cordisApprovalHeader;

  /// Label above the purpose the model supplied at cordis_define time, on the Cordis approval card.
  ///
  /// In en, this message translates to:
  /// **'Purpose'**
  String get cordisPurposeLabel;

  /// Label for the stable plugin instance id on the Cordis approval card.
  ///
  /// In en, this message translates to:
  /// **'Plugin ID'**
  String get cordisPluginIdLabel;

  /// Label for the package version id on the Cordis approval card.
  ///
  /// In en, this message translates to:
  /// **'Package ID'**
  String get cordisPackageIdLabel;

  /// Lifecycle-intent chip for a first-time Cordis plugin activation.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get cordisModeRun;

  /// Lifecycle-intent chip for a Cordis plugin activation that updates an already-loaded package.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get cordisModeUpdate;

  /// Explains why the Cordis approval card offers Reject only.
  ///
  /// In en, this message translates to:
  /// **'This phone can only reject: approving needs the browser plugin runtime that reports the activation it created, and this client doesn\'\'t have one. Rejecting releases the blocked tool call and runs neither half.'**
  String get cordisRejectOnlyNotice;

  /// Stated when dynamicCordisRunner/resolveRequestRun refused the rejection this client sent.
  ///
  /// In en, this message translates to:
  /// **'The host didn\'\'t accept the plugin decision.'**
  String get cordisAnswerFailed;

  /// Host edit-sheet button that runs the reachability probe for the typed base URL.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get backendTestConnection;

  /// Bounded in-progress line while the reachability probe is in flight.
  ///
  /// In en, this message translates to:
  /// **'Testing connection…'**
  String get backendProbeRunning;

  /// Probe outcome: a well-formed answer (including a business error) came back.
  ///
  /// In en, this message translates to:
  /// **'Reachable. The host answered the dsh contract.'**
  String get backendProbeReachable;

  /// Probe outcome: connection refused, DNS failure, or the request deadline elapsed.
  ///
  /// In en, this message translates to:
  /// **'No dsh answered at this address. Check the base URL, that the gateway is running, and that this phone can reach it.'**
  String get backendProbeUnreachable;

  /// Probe outcome: TLS handshake failure, pointing at the per-host certificate-trust toggle.
  ///
  /// In en, this message translates to:
  /// **'TLS handshake failed. The host\'\'s certificate is not trusted — if you control this gateway, turn on “Trust this host\'\'s certificate” above.'**
  String get backendProbeCertificateNotTrusted;

  /// Probe outcome: HTTP 401; the deployment authenticates (or dsh web requires its printed URL token) and this client performs none.
  ///
  /// In en, this message translates to:
  /// **'The gateway requires pairing or credentials this client does not have (deployment authentication, or the URL token dsh web prints). This client performs no authentication.'**
  String get backendProbeAuthenticationRequired;

  /// Probe outcome: HTTP 404 on the probe route, distinct from a connect failure.
  ///
  /// In en, this message translates to:
  /// **'Something answered, but it is not a dsh host: there is no dsh RPC route at this address.'**
  String get backendProbeNotDshSurface;

  /// Probe outcome: a non-2xx status other than 401 or 404.
  ///
  /// In en, this message translates to:
  /// **'The host answered HTTP {status}, which the dsh contract does not use.'**
  String backendProbeUnexpectedStatus(int status);

  /// Probe outcome: a 2xx body that does not decode as a JSON-RPC envelope.
  ///
  /// In en, this message translates to:
  /// **'The host answered, but not with a dsh JSON-RPC response.'**
  String get backendProbeUnenvelopedResponse;

  /// Probe outcome: a failure outside the transport's recognized vocabulary.
  ///
  /// In en, this message translates to:
  /// **'Could not classify the connection failure.'**
  String get backendProbeUnknown;

  /// Caveat shown when a TLS handshake failed without naming a certificate, so the class cannot be proven.
  ///
  /// In en, this message translates to:
  /// **'The failure was a TLS handshake error; it may be a certificate the system rejects or another TLS mismatch.'**
  String get backendProbeAmbiguousTls;

  /// Stated with a failed probe so the user knows the host still saves.
  ///
  /// In en, this message translates to:
  /// **'Saving is not blocked — a host can be offline while you configure it.'**
  String get backendProbeSaveNotBlocked;

  /// Member count on a workflow-run card header and on each phase header.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1 {1 member} other {{count} members}}'**
  String workflowMemberCount(int count);

  /// Shown inside an expanded workflow-run card whose run recorded no members.
  ///
  /// In en, this message translates to:
  /// **'No members started'**
  String get workflowRunEmpty;

  /// Phase header for a workflow member whose event carried no phase field.
  ///
  /// In en, this message translates to:
  /// **'Unphased'**
  String get workflowPhaseUnassigned;

  /// Phase header for a workflow member whose phase field was the empty string.
  ///
  /// In en, this message translates to:
  /// **'Empty phase name'**
  String get workflowPhaseEmpty;

  /// Member row label for a workflow member whose label was the empty string.
  ///
  /// In en, this message translates to:
  /// **'Empty member name'**
  String get workflowMemberEmpty;

  /// Accessibility label of a workflow member row that opens the member's child transcript.
  ///
  /// In en, this message translates to:
  /// **'Open {name}'**
  String workflowMemberOpen(String name);

  /// Workflow run or member status.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get workflowStatusRunning;

  /// Workflow run or member status.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get workflowStatusCompleted;

  /// Workflow run or member status.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get workflowStatusFailed;

  /// Workflow run or member status.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get workflowStatusCancelled;

  /// Workflow run or member status for a run whose turn closed with no terminal event.
  ///
  /// In en, this message translates to:
  /// **'Interrupted'**
  String get workflowStatusInterrupted;

  /// Phase status roll-up fragment.
  ///
  /// In en, this message translates to:
  /// **'Running {count}'**
  String workflowStatusCountRunning(int count);

  /// Phase status roll-up fragment.
  ///
  /// In en, this message translates to:
  /// **'Completed {count}'**
  String workflowStatusCountCompleted(int count);

  /// Phase status roll-up fragment.
  ///
  /// In en, this message translates to:
  /// **'Failed {count}'**
  String workflowStatusCountFailed(int count);

  /// Phase status roll-up fragment.
  ///
  /// In en, this message translates to:
  /// **'Cancelled {count}'**
  String workflowStatusCountCancelled(int count);

  /// Phase status roll-up fragment.
  ///
  /// In en, this message translates to:
  /// **'Interrupted {count}'**
  String workflowStatusCountInterrupted(int count);

  /// Hook audit row whose hook/result has not folded yet.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get hookAuditPending;

  /// The durable decision a hook returned (for example deny or allow).
  ///
  /// In en, this message translates to:
  /// **'{decision}'**
  String hookAuditDecision(String decision);

  /// Hook run duration shown on the collapsed audit row.
  ///
  /// In en, this message translates to:
  /// **'{durationMs} ms'**
  String hookAuditDurationMs(int durationMs);

  /// Label for the hook point (PreToolUse, Stop, ...) in the audit detail.
  ///
  /// In en, this message translates to:
  /// **'Point'**
  String get hookAuditPoint;

  /// Label for the hook bridge dialect in the audit detail.
  ///
  /// In en, this message translates to:
  /// **'Dialect'**
  String get hookAuditDialect;

  /// Hook bridge dialect name.
  ///
  /// In en, this message translates to:
  /// **'Claude Code'**
  String get hookDialectClaudeCode;

  /// Hook bridge dialect name.
  ///
  /// In en, this message translates to:
  /// **'Codex'**
  String get hookDialectCodex;

  /// Label for the matcher pattern that selected the hook, when it declared one.
  ///
  /// In en, this message translates to:
  /// **'Matcher'**
  String get hookAuditMatcher;

  /// Label for the hook decision in the audit detail.
  ///
  /// In en, this message translates to:
  /// **'Decision'**
  String get hookAuditDecisionLabel;

  /// Label for the hook process exit code in the audit detail.
  ///
  /// In en, this message translates to:
  /// **'Exit code'**
  String get hookAuditExitCode;

  /// Value for a hook audit field the host did not report, such as an exit code for a hook that never ran.
  ///
  /// In en, this message translates to:
  /// **'Not reported'**
  String get hookAuditUnknown;

  /// Label for the trimmed stderr summary in the audit detail.
  ///
  /// In en, this message translates to:
  /// **'Stderr'**
  String get hookAuditStderr;

  /// Value when a hook wrote nothing to stderr.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get hookAuditNoStderr;

  /// Tooltip of the composer sandbox chip while the mode fact is unreported.
  ///
  /// In en, this message translates to:
  /// **'This session has not reported its sandbox mode. The host\'\'s deployment default applies.'**
  String get sandboxModeUnknownTooltip;

  /// Tooltip of the composer sandbox chip when the mode is known.
  ///
  /// In en, this message translates to:
  /// **'Sandbox: {mode}'**
  String sandboxModeTooltip(String mode);

  /// Sandbox mode name.
  ///
  /// In en, this message translates to:
  /// **'Read only'**
  String get sandboxModeReadOnly;

  /// Sandbox mode name.
  ///
  /// In en, this message translates to:
  /// **'Workspace write'**
  String get sandboxModeWorkspaceWrite;

  /// Sandbox mode name.
  ///
  /// In en, this message translates to:
  /// **'Full access'**
  String get sandboxModeDangerFullAccess;

  /// Title of the composer dock's active-reminder strip.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get scheduleStripTitle;

  /// Active reminder count on the strip header.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1 {1 reminder} other {{count} reminders}}'**
  String scheduleReminderCount(int count);

  /// The session's reminder set before the schedule/change stream has published anything; distinct from an empty set.
  ///
  /// In en, this message translates to:
  /// **'Not reported by this host'**
  String get scheduleUnknown;

  /// The session's reminder set is known and empty.
  ///
  /// In en, this message translates to:
  /// **'None active'**
  String get scheduleEmpty;

  /// The next reminder target on the collapsed strip header.
  ///
  /// In en, this message translates to:
  /// **'Next {at}'**
  String scheduleNextAt(String at);

  /// Count of reminders whose target has passed.
  ///
  /// In en, this message translates to:
  /// **'{count} overdue'**
  String scheduleOverdueCount(int count);

  /// Reminders past the strip's row cap.
  ///
  /// In en, this message translates to:
  /// **'+{count} more'**
  String scheduleMoreCount(int count);

  /// Frequency of a one-shot reminder.
  ///
  /// In en, this message translates to:
  /// **'Once'**
  String get scheduleFrequencyOnce;

  /// Frequency of a fixed-rate reminder.
  ///
  /// In en, this message translates to:
  /// **'Every {value} {unit}'**
  String scheduleFrequencyEvery(int value, String unit);

  /// Singular day unit for a fixed-rate reminder.
  ///
  /// In en, this message translates to:
  /// **'day'**
  String get scheduleUnitDay;

  /// Plural day unit for a fixed-rate reminder.
  ///
  /// In en, this message translates to:
  /// **'days'**
  String get scheduleUnitDays;

  /// Singular hour unit for a fixed-rate reminder.
  ///
  /// In en, this message translates to:
  /// **'hour'**
  String get scheduleUnitHour;

  /// Plural hour unit for a fixed-rate reminder.
  ///
  /// In en, this message translates to:
  /// **'hours'**
  String get scheduleUnitHours;

  /// Singular minute unit for a fixed-rate reminder.
  ///
  /// In en, this message translates to:
  /// **'minute'**
  String get scheduleUnitMinute;

  /// Plural minute unit for a fixed-rate reminder.
  ///
  /// In en, this message translates to:
  /// **'minutes'**
  String get scheduleUnitMinutes;

  /// Singular second unit for a fixed-rate reminder.
  ///
  /// In en, this message translates to:
  /// **'second'**
  String get scheduleUnitSecond;

  /// Plural second unit for a fixed-rate reminder.
  ///
  /// In en, this message translates to:
  /// **'seconds'**
  String get scheduleUnitSeconds;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
