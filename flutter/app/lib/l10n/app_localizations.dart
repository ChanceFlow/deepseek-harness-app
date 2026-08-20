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
  /// **'DeepSeek Harness'**
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
  /// **'No current goal'**
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
  /// **'Pause'**
  String get pause;

  /// Resume a paused goal.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// Clear a goal.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// Complete a goal.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get complete;

  /// Edit a goal.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// Goal phase label, active.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE'**
  String get goalPhaseActive;

  /// Goal phase label, paused.
  ///
  /// In en, this message translates to:
  /// **'PAUSED'**
  String get goalPhasePaused;

  /// Goal phase label, blocked.
  ///
  /// In en, this message translates to:
  /// **'BLOCKED'**
  String get goalPhaseBlocked;

  /// Goal phase label, complete.
  ///
  /// In en, this message translates to:
  /// **'COMPLETE'**
  String get goalPhaseComplete;

  /// No description provided for @goalStatusLine.
  ///
  /// In en, this message translates to:
  /// **'{phase} · revision {revision} · rounds {started}/{max}'**
  String goalStatusLine(
    Object max,
    Object phase,
    Object revision,
    Object started,
  );

  /// No description provided for @contextUsedPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}% of context used'**
  String contextUsedPercent(Object percent);

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
  /// **'Conversation'**
  String get conversationLabel;

  /// No description provided for @contextTokens.
  ///
  /// In en, this message translates to:
  /// **'~{used} / {window}'**
  String contextTokens(Object used, Object window);

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

  /// No description provided for @modelCurrent.
  ///
  /// In en, this message translates to:
  /// **'{name} (current)'**
  String modelCurrent(Object name);

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

  /// No description provided for @todoCountDone.
  ///
  /// In en, this message translates to:
  /// **'{count} completed'**
  String todoCountDone(Object count);

  /// No description provided for @todoCountActive.
  ///
  /// In en, this message translates to:
  /// **'{count} active'**
  String todoCountActive(Object count);

  /// No description provided for @todoCountPending.
  ///
  /// In en, this message translates to:
  /// **'{count} pending'**
  String todoCountPending(Object count);

  /// Background-jobs sheet title.
  ///
  /// In en, this message translates to:
  /// **'Background jobs'**
  String get backgroundJobsTitle;

  /// No description provided for @jobCountRunning.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 background job running} other{{count} background jobs running}}'**
  String jobCountRunning(num count);

  /// No description provided for @jobCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 background job} other{{count} background jobs}}'**
  String jobCount(num count);

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

  /// No description provided for @jobDurationHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String jobDurationHoursMinutes(Object hours, Object minutes);

  /// No description provided for @jobDurationMinutesSeconds.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m {seconds}s'**
  String jobDurationMinutesSeconds(Object minutes, Object seconds);

  /// No description provided for @jobDurationSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String jobDurationSeconds(Object seconds);

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

  /// No description provided for @approveToolFallback.
  ///
  /// In en, this message translates to:
  /// **'Approve tool: {tool}'**
  String approveToolFallback(Object tool);

  /// No description provided for @toolRequestsPrivileged.
  ///
  /// In en, this message translates to:
  /// **'Tool {tool} requests privileged execution'**
  String toolRequestsPrivileged(Object tool);

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

  /// No description provided for @accessModeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Access mode: {label}'**
  String accessModeTooltip(Object label);

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
  /// **'Provider default'**
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

  /// No description provided for @toolTodoPlanCompleted.
  ///
  /// In en, this message translates to:
  /// **'{done}/{total} completed'**
  String toolTodoPlanCompleted(Object done, Object total);

  /// No description provided for @statsTurnsSteps.
  ///
  /// In en, this message translates to:
  /// **'{turns} turns · {steps} steps'**
  String statsTurnsSteps(Object steps, Object turns);

  /// No description provided for @statsLlmDuration.
  ///
  /// In en, this message translates to:
  /// **'LLM {duration}'**
  String statsLlmDuration(Object duration);

  /// No description provided for @statsToolDuration.
  ///
  /// In en, this message translates to:
  /// **'Tool call {duration}'**
  String statsToolDuration(Object duration);

  /// No description provided for @statsTtftAvg.
  ///
  /// In en, this message translates to:
  /// **'TTFT avg {duration}'**
  String statsTtftAvg(Object duration);

  /// No description provided for @statsTokensPerSecond.
  ///
  /// In en, this message translates to:
  /// **'{rate} tok/s'**
  String statsTokensPerSecond(Object rate);

  /// No description provided for @statsCacheHit.
  ///
  /// In en, this message translates to:
  /// **'Cache hit {percent}%'**
  String statsCacheHit(Object percent);

  /// No description provided for @statsInputTokens.
  ///
  /// In en, this message translates to:
  /// **'Input {tokens} tok'**
  String statsInputTokens(Object tokens);

  /// No description provided for @statsOutputTokens.
  ///
  /// In en, this message translates to:
  /// **'Output {tokens} tok'**
  String statsOutputTokens(Object tokens);

  /// No description provided for @credentialStateUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Credential state unavailable: {error}'**
  String credentialStateUnavailable(Object error);

  /// No description provided for @storeCredentialTitle.
  ///
  /// In en, this message translates to:
  /// **'Store {ref}'**
  String storeCredentialTitle(Object ref);

  /// No description provided for @namespaceMetaApplies.
  ///
  /// In en, this message translates to:
  /// **'applies: {name}'**
  String namespaceMetaApplies(Object name);

  /// No description provided for @namespaceMetaRevision.
  ///
  /// In en, this message translates to:
  /// **'revision: {revision}'**
  String namespaceMetaRevision(Object revision);

  /// No description provided for @credentialMetaSource.
  ///
  /// In en, this message translates to:
  /// **'source: {source}'**
  String credentialMetaSource(Object source);

  /// No description provided for @casRevisionLine.
  ///
  /// In en, this message translates to:
  /// **'CAS revision {revision}; host validates against the schema'**
  String casRevisionLine(Object revision);

  /// No description provided for @newSessionInWorkspace.
  ///
  /// In en, this message translates to:
  /// **'New session in {title}'**
  String newSessionInWorkspace(Object title);

  /// No description provided for @workspaceActionsFor.
  ///
  /// In en, this message translates to:
  /// **'Workspace actions for {title}'**
  String workspaceActionsFor(Object title);

  /// No description provided for @workspaceNameExists.
  ///
  /// In en, this message translates to:
  /// **'A workspace named \"{name}\" already exists.'**
  String workspaceNameExists(Object name);

  /// No description provided for @deleteWorkspaceConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete workspace \"{name}\"? Its sessions stay; the connector is removed.'**
  String deleteWorkspaceConfirm(Object name);

  /// No description provided for @newFolderIn.
  ///
  /// In en, this message translates to:
  /// **'New folder in \"{parent}\"'**
  String newFolderIn(Object parent);

  /// No description provided for @secretsSetCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 secret set} other{{count} secrets set}}'**
  String secretsSetCount(num count);

  /// No description provided for @workspaceSessionCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 session} other{{count} sessions}}'**
  String workspaceSessionCount(num count);

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
  /// **'Applies only while an agent is running.'**
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
  /// **'A preset is the plugin composition one session\'\'s agent runs — its tools, prompt, and capabilities.'**
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
