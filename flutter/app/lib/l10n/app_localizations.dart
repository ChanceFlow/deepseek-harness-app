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

  /// Goal metadata line under the objective.
  ///
  /// In en, this message translates to:
  /// **'{phase} · revision {revision} · rounds {started}/{max}'**
  String goalStatusLine(String phase, int revision, int started, int max);

  /// Context occupancy reading and its accessibility label.
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
  /// **'Conversation'**
  String get conversationLabel;

  /// Compact token figures for the context composition.
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

  /// Model row button label for the active model.
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

  /// Completed to-do count segment.
  ///
  /// In en, this message translates to:
  /// **'{count} completed'**
  String todoCountDone(int count);

  /// In-progress to-do count segment.
  ///
  /// In en, this message translates to:
  /// **'{count} active'**
  String todoCountActive(int count);

  /// Pending to-do count segment.
  ///
  /// In en, this message translates to:
  /// **'{count} pending'**
  String todoCountPending(int count);

  /// Background-jobs sheet title.
  ///
  /// In en, this message translates to:
  /// **'Background jobs'**
  String get backgroundJobsTitle;

  /// Header pill while jobs are still live.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 background job running} other{{count} background jobs running}}'**
  String jobCountRunning(int count);

  /// Header pill when all jobs are settled.
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

  /// Compact elapsed duration, hours and minutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String jobDurationHoursMinutes(int hours, int minutes);

  /// Compact elapsed duration, minutes and seconds.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m {seconds}s'**
  String jobDurationMinutesSeconds(int minutes, int seconds);

  /// Compact elapsed duration, seconds only.
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

  /// Approval justification fallback naming the tool.
  ///
  /// In en, this message translates to:
  /// **'Approve tool: {tool}'**
  String approveToolFallback(String tool);

  /// Approval panel secondary line.
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

  /// Access chip tooltip naming the current mode.
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

  /// Todo plan summary segment.
  ///
  /// In en, this message translates to:
  /// **'{done}/{total} completed'**
  String toolTodoPlanCompleted(int done, int total);

  /// Composer stats: turn and step counts.
  ///
  /// In en, this message translates to:
  /// **'{turns} turns · {steps} steps'**
  String statsTurnsSteps(int turns, int steps);

  /// Composer stats: LLM processing duration.
  ///
  /// In en, this message translates to:
  /// **'LLM {duration}'**
  String statsLlmDuration(String duration);

  /// Composer stats: tool-call duration.
  ///
  /// In en, this message translates to:
  /// **'Tool call {duration}'**
  String statsToolDuration(String duration);

  /// Composer stats: average time to first token.
  ///
  /// In en, this message translates to:
  /// **'TTFT avg {duration}'**
  String statsTtftAvg(String duration);

  /// Composer stats: decode throughput.
  ///
  /// In en, this message translates to:
  /// **'{rate} tok/s'**
  String statsTokensPerSecond(String rate);

  /// Composer stats: cache hit percentage.
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
