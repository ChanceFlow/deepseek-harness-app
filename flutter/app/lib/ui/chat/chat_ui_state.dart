/// Chat screen UI state and user intents (UDF).
library;

import 'package:domain/model/connection_state.dart';
import 'package:domain/model/goal.dart';
import 'package:domain/model/jobs.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/context_pressure.dart';
import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/attachment.dart';
import 'package:domain/model/permission_select.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/todo.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/session_window_stats.dart';
import 'package:domain/model/skills.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/foundation.dart' show listEquals;

final class ChatUiState {
  const ChatUiState({
    this.connection = const ConnectionState(),
    this.sessions = const <SessionSummary>[],
    this.workspaces = const <WorkspaceSummary>[],
    this.selectedSessionId,
    this.timeline = const <TimelineItem>[],
    this.hasMoreOlder = false,
    this.isLoadingOlder = false,
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
  });

  final ConnectionState connection;
  final List<SessionSummary> sessions;
  final List<WorkspaceSummary> workspaces;
  final String? selectedSessionId;
  final List<TimelineItem> timeline;
  final bool hasMoreOlder;
  final bool isLoadingOlder;
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
}

/// Base intent type; subclasses carry value equality like the Kotlin
/// data classes they replace.
sealed class ChatAction {
  const ChatAction();
}

final class SelectSession extends ChatAction {
  const SelectSession(this.sessionId);

  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is SelectSession && other.sessionId == sessionId;

  @override
  int get hashCode => sessionId.hashCode;
}

final class SendPrompt extends ChatAction {
  const SendPrompt(this.text, {this.mode = PromptMode.queue});

  final String text;
  final PromptMode mode;

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
  const ForkSession(this.sessionId);

  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is ForkSession && other.sessionId == sessionId;

  @override
  int get hashCode => sessionId.hashCode;
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
