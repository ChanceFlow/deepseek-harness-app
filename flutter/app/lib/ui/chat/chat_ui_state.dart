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
  const CreateSessionInWorkspace(this.workspaceId);

  final String? workspaceId;

  @override
  bool operator ==(Object other) =>
      other is CreateSessionInWorkspace && other.workspaceId == workspaceId;

  @override
  int get hashCode => Object.hash('create-in', workspaceId);
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
