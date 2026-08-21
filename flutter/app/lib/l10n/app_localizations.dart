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

  /// No description provided for @settingsNavBackends.
  ///
  /// In en, this message translates to:
  /// **'Backends'**
  String get settingsNavBackends;

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

  /// The backend whose host settings the Settings pages describe.
  ///
  /// In en, this message translates to:
  /// **'Configuring: {label}'**
  String settingsScopeLabel(String label);

  /// No description provided for @settingsScopeTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings backend'**
  String get settingsScopeTitle;

  /// No description provided for @settingsScopeHint.
  ///
  /// In en, this message translates to:
  /// **'Which backend the host-settings pages describe - independent of the active chat backend.'**
  String get settingsScopeHint;

  /// No description provided for @settingsScopeFollowActive.
  ///
  /// In en, this message translates to:
  /// **'Follow the active backend'**
  String get settingsScopeFollowActive;

  /// No description provided for @settingsLoopbackHint.
  ///
  /// In en, this message translates to:
  /// **'settings/credentials are loopback-only on the host; connect via adb reverse'**
  String get settingsLoopbackHint;

  /// No description provided for @backendsIntro.
  ///
  /// In en, this message translates to:
  /// **'Host endpoints this device keeps connected — every configured backend stays live; the active one drives Chat and these host-settings pages.'**
  String get backendsIntro;

  /// No description provided for @addBackend.
  ///
  /// In en, this message translates to:
  /// **'Add backend'**
  String get addBackend;

  /// No description provided for @editBackend.
  ///
  /// In en, this message translates to:
  /// **'Edit backend'**
  String get editBackend;

  /// No description provided for @removeActiveBackendFirst.
  ///
  /// In en, this message translates to:
  /// **'Switch away before removing the active backend.'**
  String get removeActiveBackendFirst;

  /// No description provided for @cannotRemoveLastBackend.
  ///
  /// In en, this message translates to:
  /// **'The last backend cannot be removed.'**
  String get cannotRemoveLastBackend;

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

  /// No description provided for @hostSettingsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Host settings unavailable'**
  String get hostSettingsUnavailable;

  /// No description provided for @hostSettingsUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'The active backend did not answer. Repoint or switch it from the Backends page.'**
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
  /// **'Custom providers are managed on the host: this client covers the DeepSeek API key only.'**
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
  /// **'http://10.0.2.2:3080'**
  String get backendBaseUrlHint;

  /// No description provided for @baseUrlDerivationHint.
  ///
  /// In en, this message translates to:
  /// **'RPC and event paths derive from this base.'**
  String get baseUrlDerivationHint;

  /// No description provided for @baseUrlValidHint.
  ///
  /// In en, this message translates to:
  /// **'http or https with a host, e.g. http://10.0.2.2:3080'**
  String get baseUrlValidHint;

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

  /// No description provided for @searchCommandsHint.
  ///
  /// In en, this message translates to:
  /// **'Search commands'**
  String get searchCommandsHint;

  /// No description provided for @noMatchingCommands.
  ///
  /// In en, this message translates to:
  /// **'No matching commands'**
  String get noMatchingCommands;

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
  /// **'Before first turn · {count} messages'**
  String beforeFirstTurnHeader(int count);

  /// Localized screen copy.
  ///
  /// In en, this message translates to:
  /// **'Turn {turn} · {count} messages · {toolCount} tools'**
  String turnHeader(int count, int toolCount, int turn);

  /// No description provided for @contextCompacted.
  ///
  /// In en, this message translates to:
  /// **'Context compacted'**
  String get contextCompacted;

  /// Compaction notice line count.
  ///
  /// In en, this message translates to:
  /// **'Compacted {count} history items'**
  String compactedHistoryCount(int count);

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
