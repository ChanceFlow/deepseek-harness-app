/// Chat screen UI state and user intents (UDF).
library;

import 'package:domain/model/connection_state.dart';
import 'package:domain/model/attachment.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/skills.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/model/workspace.dart';

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
    this.pendingImages = const <PendingImage>[],
    this.imageLimits = const ImageLimits(),
    this.plan,
    this.skills = const <SkillEntry>[],
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

  /// Composer images awaiting the next send.
  final List<PendingImage> pendingImages;

  /// Host image admission limits; defaults until the projection arrives.
  final ImageLimits imageLimits;

  /// Plan collaboration state of the selected session; null = not composed.
  final PlanState? plan;

  /// Skill catalog of the selected session, backing the `/` composer
  /// source.
  final List<SkillEntry> skills;
}

sealed class ChatAction {
  const ChatAction();
}

final class SelectSession extends ChatAction {
  const SelectSession(this.sessionId);

  final String sessionId;
}

final class SendPrompt extends ChatAction {
  const SendPrompt(this.text, {this.mode = PromptMode.queue});

  final String text;
  final PromptMode mode;
}

final class CancelTurnAction extends ChatAction {
  const CancelTurnAction();
}

final class CreateSessionAction extends ChatAction {
  const CreateSessionAction();
}

final class CreateSessionInWorkspace extends ChatAction {
  const CreateSessionInWorkspace(this.workspaceId);

  final String? workspaceId;
}

final class DismissError extends ChatAction {
  const DismissError();
}

final class RetrySessions extends ChatAction {
  const RetrySessions();
}

final class LoadOlderHistoryAction extends ChatAction {
  const LoadOlderHistoryAction();
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
}

final class AnswerQuestionAction extends ChatAction {
  const AnswerQuestionAction({required this.requestId, required this.answers});

  final String requestId;
  final List<QuestionAnswer> answers;
}

final class SearchSessions extends ChatAction {
  const SearchSessions(this.query);

  final String query;
}

final class RenameSession extends ChatAction {
  const RenameSession(this.sessionId, this.title);

  final String sessionId;
  final String title;
}

final class ArchiveSession extends ChatAction {
  const ArchiveSession(this.sessionId);

  final String sessionId;
}

final class ForkSession extends ChatAction {
  const ForkSession(this.sessionId);

  final String sessionId;
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
}

/// Picked images encoded by the picker interop, ready for admission.
final class ImagesLoaded extends ChatAction {
  const ImagesLoaded(this.images);

  final List<PendingImage> images;
}

final class RemovePendingImage extends ChatAction {
  const RemovePendingImage(this.id);

  final String id;
}

/// Picker/read failures surface in the shared error strip.
final class ImagePickError extends ChatAction {
  const ImagePickError(this.message);

  final String message;
}
