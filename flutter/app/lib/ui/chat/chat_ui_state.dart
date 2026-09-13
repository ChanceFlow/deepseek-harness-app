/// Chat screen UI state and user intents (UDF).
library;

import 'package:domain/model/command.dart';
import 'package:domain/model/cordis.dart';
import 'package:domain/model/goal.dart';
import 'package:domain/model/jobs.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/attachment.dart';
import 'package:domain/model/permission_select.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/sandbox.dart';
import 'package:domain/model/schedule.dart';
import 'package:domain/model/todo.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/session_window_stats.dart';
import 'package:domain/model/skills.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/foundation.dart' show listEquals;

import 'chat_local_state.dart';

final class ChatUiState {
  const ChatUiState({
    this.sessions = const <SessionSummary>[],
    this.workspaces = const <WorkspaceSummary>[],
    this.selectedSessionId,
    this.selectionRequestSeq = 0,
    this.selectionLandsAtLatest = false,
    this.timeline = const <TimelineItem>[],
    this.hasMoreOlder = false,
    this.isLoadingOlder = false,
    this.isTimelineLoading = false,
    this.searchResults = const <SessionSearchResult>[],
    this.isSending = false,
    this.errorMessage,
    this.commandFailed = false,
    this.imageRejections = const <ImageRejection>[],
    this.pendingImages = const <PendingImage>[],
    this.imageLimits = const ImageLimits(),
    this.plan,
    this.todos,
    this.skills = const <SkillEntry>[],
    this.contextPressure,
    this.contextBreakdown,
    this.sessionStats = const SessionWindowStats(),
    this.goal,
    this.models,
    this.jobs = const <JobView>[],
    this.permissions,
    this.agentPresets,
    this.modelPrefs,
    this.sessionLogExport,
    this.canExportSessionLog = false,
    this.cordisRunRequests = const <CordisRunRequest>[],
    this.cordisAnswerFailed = false,
    this.commands,
    this.sandboxMode,
    this.schedules,
  });

  final List<SessionSummary> sessions;
  final List<WorkspaceSummary> workspaces;
  final String? selectedSessionId;

  /// Monotonic count of user selection requests handled by the controller.
  /// A re-selection of the session already on screen publishes the same
  /// [selectedSessionId]; this counter is how the view still sees that a
  /// request happened (the notification deep link depends on it).
  final int selectionRequestSeq;

  /// Whether the request that produced the current selection asked the
  /// transcript to land on the newest content instead of the reader's
  /// persisted reading position. Only the notification entry sets it;
  /// ordinary list taps keep restoring where the reader left off.
  final bool selectionLandsAtLatest;

  final List<TimelineItem> timeline;
  final bool hasMoreOlder;
  final bool isLoadingOlder;

  /// The selected session's first full timeline load (or a reconnect
  /// resync) is in flight. While true with an empty [timeline], the chat
  /// body renders a loading indicator instead of the empty hero.
  final bool isTimelineLoading;
  final List<SessionSearchResult> searchResults;
  final bool isSending;
  final String? errorMessage;

  /// A host command executed but returned an error outcome with no
  /// message; the UI renders the localized [l10n.commandFailed] line
  /// (the controller stays locale-free).
  final bool commandFailed;

  /// Picked images refused admission this load, with the reason (facts for
  /// the UI layer to localize); cleared on the next admission pass.
  final List<ImageRejection> imageRejections;

  /// Composer images awaiting the next send.
  final List<PendingImage> pendingImages;

  /// Host image admission limits; defaults until the projection arrives.
  final ImageLimits imageLimits;

  /// Plan collaboration state of the selected session; null = not composed.
  final PlanState? plan;

  /// Standing todo list (the `todos` projection): the latest whole
  /// `todo/write` list, cleared at the next `turn/start`.
  final List<TodoItem>? todos;

  /// Skill catalog of the selected session, backing the `/` composer
  /// source.
  final List<SkillEntry> skills;

  /// Context occupancy of the selected session (composer status ring).
  final ContextPressure? contextPressure;

  /// Heuristic composition shown in the ring's panel.
  final ContextBreakdown? contextBreakdown;

  /// Window stats for the composer stats line.
  final SessionWindowStats sessionStats;

  /// Goal projection of the selected session (composer dock strip).
  final GoalProjection? goal;

  /// Model directory of the selected session (composer model seat).
  final SessionModels? models;

  /// Background jobs of the selected session (header action).
  final List<JobView> jobs;

  /// Permission-preset projection of the selected session (composer
  /// access chip); null while the host composes no permission service
  /// or the session is not bound.
  final PermissionSelect? permissions;

  /// The deployment's agent-preset roster (hero chip, blank-session
  /// switch, header label); null while unloaded or on load failure —
  /// every preset surface then stays hidden.
  final AgentPresetRoster? agentPresets;

  /// Remembered composer model-seat preferences (effort prefill when a
  /// model is picked again); null while persistence is absent or still
  /// loading, in which case the seat opens on the model's own default.
  final ModelSeatPreferences? modelPrefs;

  /// The session-log export this screen is running or last finished; null
  /// before any export.
  final SessionLogExportState? sessionLogExport;

  /// Whether this deployment composed a session-log export seam. False
  /// hides the header action entirely rather than offering a seat that can
  /// only fail.
  final bool canExportSessionLog;

  /// Pending dynamic-Cordis plugin activation requests the host forwarded
  /// (`cordis/request-run`). A request stays here until a client answers it
  /// or `cordis/request-run-resolved` reports it settled; an empty list is
  /// the settled state.
  final List<CordisRunRequest> cordisRunRequests;

  /// The host refused the last Cordis rejection this client sent; the UI
  /// renders the localized [l10n.cordisAnswerFailed] line (the controller
  /// stays locale-free).
  final bool cordisAnswerFailed;

  /// The selected session's live host-command roster (`commands/list`), in
  /// the host's name-sorted order. Null means no pull has settled — either
  /// it never ran or it failed (a subagent-owned session answers
  /// `session/agent-busy`) — and the static roster stands in as the
  /// pre-first-pull fallback. A non-null value, including an empty list, is
  /// the host's own roster and overrides the static list.
  final List<CommandDescriptor>? commands;

  /// The selected session's effective sandbox-mode fact, folded from its
  /// `sandbox/mode` events. Null means no such fact has arrived: the
  /// deployment default applies and the client does not know which mode
  /// that is. Never substitute a default here — an unknown mode renders as
  /// unknown.
  final SandboxModeFact? sandboxMode;

  /// The selected session's active durable reminders, folded from its
  /// versioned `schedule/change` stream. Null means nothing has been
  /// published for this session yet (the pinned `dsh web` composes no
  /// `schedule` projection, so the event stream is the only source); an
  /// empty list is the host's own "no active reminders".
  final List<ScheduleReminder>? schedules;
}

/// Where one session-log export stands. Facts only — the UI layer owns the
/// localized wording, and [location] arrives verbatim from the platform
/// save step on success.
enum SessionLogExportPhase { exporting, saved, failed }

/// One export's progress. [location] is the platform's user-facing save
/// target on success and null otherwise; a failure's cause is recorded
/// through the error-log collector rather than shown untranslated.
final class SessionLogExportState {
  const SessionLogExportState.exporting()
    : phase = SessionLogExportPhase.exporting,
      location = null;

  const SessionLogExportState.saved(String this.location)
    : phase = SessionLogExportPhase.saved;

  const SessionLogExportState.failed()
    : phase = SessionLogExportPhase.failed,
      location = null;

  final SessionLogExportPhase phase;
  final String? location;

  /// Value equality lets the success affordance fire on a transition rather
  /// than on every rebuild: a second attempt republishes `exporting` first,
  /// so `saved` is never a no-op repeat.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionLogExportState &&
          other.phase == phase &&
          other.location == location);

  @override
  int get hashCode => Object.hash(phase, location);
}

/// Base intent type; subclasses carry value equality like the Kotlin
/// data classes they replace.
sealed class ChatAction {
  const ChatAction();
}

/// Download the session's log archive and hand it to the platform save
/// path. Both the header action and a bare `/export` submission dispatch
/// this; a no-op when the deployment composed no export seam.
final class ExportSessionLog extends ChatAction {
  const ExportSessionLog(this.sessionId);

  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is ExportSessionLog && other.sessionId == sessionId;

  @override
  int get hashCode => sessionId.hashCode;
}

final class SelectSession extends ChatAction {
  const SelectSession(this.sessionId, {this.landAtLatest = false});

  final String sessionId;

  /// Selects the session and asks the transcript to land on its newest
  /// content rather than the reader's persisted reading position. The
  /// notification entry (toast tap, system-notification tap, cold-start
  /// deep link) sets it; a list tap leaves it false so the reader
  /// resumes where they left off.
  final bool landAtLatest;

  @override
  bool operator ==(Object other) =>
      other is SelectSession &&
      other.sessionId == sessionId &&
      other.landAtLatest == landAtLatest;

  @override
  int get hashCode => Object.hash(sessionId, landAtLatest);
}

final class SendPrompt extends ChatAction {
  const SendPrompt(this.text, {this.mode = PromptMode.queue, this.onSettled});

  final String text;
  final PromptMode mode;

  /// One-shot settle notice for a composer dispatch: `true` when the host
  /// accepted the submission, `false` when it failed. The composer holds
  /// the draft (and defers the cleared marker) until this lands, so a
  /// failed send never loses the reader's words. Programmatic dispatches
  /// (plan chip, permission seat) carry no notice — they consume nothing
  /// the reader wrote. The notice is plumbing, not intent: value identity
  /// stays the submitted text and mode.
  final void Function(bool accepted)? onSettled;

  @override
  bool operator ==(Object other) =>
      other is SendPrompt && other.text == text && other.mode == mode;

  @override
  int get hashCode => Object.hash(text, mode);
}

final class CancelTurnAction extends ChatAction {
  const CancelTurnAction();

  @override
  bool operator ==(Object other) => other is CancelTurnAction;

  @override
  int get hashCode => 'cancel'.hashCode;
}

final class CreateSessionAction extends ChatAction {
  const CreateSessionAction();

  @override
  bool operator ==(Object other) => other is CreateSessionAction;

  @override
  int get hashCode => 'create'.hashCode;
}

final class CreateSessionInWorkspace extends ChatAction {
  const CreateSessionInWorkspace(this.workspaceId, {this.agentPreset});

  final String? workspaceId;

  /// Agent preset the new session is composed from (the hero chip's
  /// staged choice); null composes the deployment default.
  final String? agentPreset;

  @override
  bool operator ==(Object other) =>
      other is CreateSessionInWorkspace &&
      other.workspaceId == workspaceId &&
      other.agentPreset == agentPreset;

  @override
  int get hashCode => Object.hash('create-in', workspaceId, agentPreset);
}

final class DismissError extends ChatAction {
  const DismissError();

  @override
  bool operator ==(Object other) => other is DismissError;

  @override
  int get hashCode => 'dismiss'.hashCode;
}

final class RetrySessions extends ChatAction {
  const RetrySessions();

  @override
  bool operator ==(Object other) => other is RetrySessions;

  @override
  int get hashCode => 'retry'.hashCode;
}

final class LoadOlderHistoryAction extends ChatAction {
  const LoadOlderHistoryAction();

  @override
  bool operator ==(Object other) => other is LoadOlderHistoryAction;

  @override
  int get hashCode => 'load-older'.hashCode;
}

final class RespondApproval extends ChatAction {
  const RespondApproval({
    required this.requestId,
    required this.approvalId,
    required this.allowed,
  });

  final String requestId;
  final String approvalId;
  final bool allowed;

  @override
  bool operator ==(Object other) =>
      other is RespondApproval &&
      other.requestId == requestId &&
      other.approvalId == approvalId &&
      other.allowed == allowed;

  @override
  int get hashCode => Object.hash(requestId, approvalId, allowed);
}

final class AnswerQuestionAction extends ChatAction {
  const AnswerQuestionAction({required this.requestId, required this.answers});

  final String requestId;
  final List<QuestionAnswer> answers;

  @override
  bool operator ==(Object other) =>
      other is AnswerQuestionAction &&
      other.requestId == requestId &&
      listEquals(other.answers, answers);

  @override
  int get hashCode => Object.hash(requestId, Object.hashAll(answers));
}

/// Dismiss a pending question request without answering; the host resolves
/// the asker's call as cancelled.
final class DismissQuestionAction extends ChatAction {
  const DismissQuestionAction({required this.requestId});

  final String requestId;

  @override
  bool operator ==(Object other) =>
      other is DismissQuestionAction && other.requestId == requestId;

  @override
  int get hashCode => Object.hash('dismiss-question', requestId);
}

final class SearchSessions extends ChatAction {
  const SearchSessions(this.query);

  final String query;

  @override
  bool operator ==(Object other) =>
      other is SearchSessions && other.query == query;

  @override
  int get hashCode => query.hashCode;
}

final class RenameSession extends ChatAction {
  const RenameSession(this.sessionId, this.title);

  final String sessionId;
  final String title;

  @override
  bool operator ==(Object other) =>
      other is RenameSession &&
      other.sessionId == sessionId &&
      other.title == title;

  @override
  int get hashCode => Object.hash(sessionId, title);
}

final class ArchiveSession extends ChatAction {
  const ArchiveSession(this.sessionId);

  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is ArchiveSession && other.sessionId == sessionId;

  @override
  int get hashCode => sessionId.hashCode;
}

final class ForkSession extends ChatAction {
  const ForkSession(this.sessionId, {this.atSeq});

  final String sessionId;

  /// Log position the cut anchors to: the host forks at the end of the
  /// turn containing it, so a message's own seq forks after that whole
  /// exchange. Null cuts at the source's last completed turn.
  final int? atSeq;

  @override
  bool operator ==(Object other) =>
      other is ForkSession &&
      other.sessionId == sessionId &&
      other.atSeq == atSeq;

  @override
  int get hashCode => Object.hash(sessionId, atSeq);
}

final class UpdateQueueAction extends ChatAction {
  const UpdateQueueAction({
    required this.itemId,
    required this.kind,
    this.text,
  });

  final String itemId;
  final QueueUpdateKind kind;
  final String? text;

  @override
  bool operator ==(Object other) =>
      other is UpdateQueueAction &&
      other.itemId == itemId &&
      other.kind == kind &&
      other.text == text;

  @override
  int get hashCode => Object.hash(itemId, kind, text);
}

/// Picked images encoded by the picker interop, ready for admission.
final class ImagesLoaded extends ChatAction {
  const ImagesLoaded(this.images);

  final List<PendingImage> images;

  @override
  bool operator ==(Object other) =>
      other is ImagesLoaded && listEquals(other.images, images);

  @override
  int get hashCode => Object.hashAll(images);
}

final class RemovePendingImage extends ChatAction {
  const RemovePendingImage(this.id);

  final String id;

  @override
  bool operator ==(Object other) =>
      other is RemovePendingImage && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Composer model seat selection (web conversation.input.model).
final class SelectModelSeat extends ChatAction {
  const SelectModelSeat(this.selection);

  final ModelSelection selection;

  @override
  bool operator ==(Object other) =>
      other is SelectModelSeat && other.selection == selection;

  @override
  int get hashCode => Object.hash('select-model-seat', selection);
}

/// GoalBar pause/resume toggle (composer dock strip).
final class ToggleGoalPause extends ChatAction {
  const ToggleGoalPause();

  @override
  bool operator ==(Object other) => other is ToggleGoalPause;

  @override
  int get hashCode => 'toggle-goal-pause'.hashCode;
}

/// GoalBar clear (composer dock strip): deletes the goal from any phase
/// (web GoalBar ships the trash action beside pause/resume).
final class ClearGoal extends ChatAction {
  const ClearGoal();

  @override
  bool operator ==(Object other) => other is ClearGoal;

  @override
  int get hashCode => 'clear-goal-chat'.hashCode;
}

/// GoalBar edit objective (composer dock strip — web GoalBar inline edit).
final class EditGoal extends ChatAction {
  const EditGoal(this.objective);

  final String objective;

  @override
  bool operator ==(Object other) =>
      other is EditGoal && other.objective == objective;

  @override
  int get hashCode => Object.hash('edit-goal', objective);
}

/// Picker/read failures surface in the shared error strip.
final class ImagePickError extends ChatAction {
  const ImagePickError(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is ImagePickError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

/// The composer refused a submission carrying images for a host command
/// that does not accept them (web envelope policy): nothing was sent,
/// and the draft and images stay in place. The message is localized at
/// the dispatch site; the controller only relays it.
final class CommandImageRefusal extends ChatAction {
  const CommandImageRefusal(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is CommandImageRefusal && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

/// Why one picked image was refused admission, locale-free facts for the
/// UI layer to format (the controller never composes user-facing copy).
sealed class ImageRejection {
  const ImageRejection();
}

/// The host does not accept this media type.
final class UnsupportedImageType extends ImageRejection {
  const UnsupportedImageType(this.name, this.mediaType);

  final String? name;
  final String mediaType;

  @override
  bool operator ==(Object other) =>
      other is UnsupportedImageType &&
      other.name == name &&
      other.mediaType == mediaType;

  @override
  int get hashCode => Object.hash(name, mediaType);
}

/// The image exceeds the host's per-image byte ceiling.
final class ImageTooLarge extends ImageRejection {
  const ImageTooLarge(this.name, this.maxBytes);

  final String? name;
  final int maxBytes;

  @override
  bool operator ==(Object other) =>
      other is ImageTooLarge &&
      other.name == name &&
      other.maxBytes == maxBytes;

  @override
  int get hashCode => Object.hash(name, maxBytes);
}

/// The composer's per-message seat is full.
final class NoImageRoom extends ImageRejection {
  const NoImageRoom(this.room);

  final int room;

  @override
  bool operator ==(Object other) => other is NoImageRoom && other.room == room;

  @override
  int get hashCode => room.hashCode;
}

/// Switch a blank session's agent preset (web AgentPresetSeat select).
/// The host refuses a session that already ran (`agent-preset-locked`);
/// the refusal surfaces through the shared error strip.
final class SelectAgentPreset extends ChatAction {
  const SelectAgentPreset({required this.sessionId, required this.agentPreset});

  final String sessionId;
  final String agentPreset;

  @override
  bool operator ==(Object other) =>
      other is SelectAgentPreset &&
      other.sessionId == sessionId &&
      other.agentPreset == agentPreset;

  @override
  int get hashCode => Object.hash(sessionId, agentPreset);
}

/// Reject one pending dynamic-Cordis activation request.
///
/// Rejection is the only decision this client delivers honestly. An
/// approval's `ok:true` arm names the exact Client activation
/// (`CordisRunApproved.pluginRunId`) the answering page created or attached
/// to, and only a browser plugin runtime can produce one; the host rejects a
/// resolution whose run id does not match the active half. A rejection needs
/// no such identity, refuses both halves, and is what releases the blocked
/// `cordis_run` tool call.
final class RejectCordisRun extends ChatAction {
  const RejectCordisRun(this.requestId);

  final String requestId;

  @override
  bool operator ==(Object other) =>
      other is RejectCordisRun && other.requestId == requestId;

  @override
  int get hashCode => Object.hash('reject-cordis-run', requestId);
}
