/// Per-message human feedback for the assistant row's action strip.
///
/// Mirrors `packages/client/ui-message-feedback` (the Like/Dislike pair in the
/// conversation's assistant-actions strip, between copy and branch): one
/// `messageFeedback/list` read per Session seeds every row, a tap on a fresh
/// rating records it (`messageFeedback/put`), a tap on the recorded rating
/// retracts it (`messageFeedback/delete`), the recorded rating stays filled so
/// the signal survives the pointer leaving, and the host's stable refusal is
/// stated on the row that raised it without changing that row.
///
/// The host owns compare-and-set: every mutation carries the version this
/// controller last observed, and a `version-conflict` refusal answers the
/// authoritative item, so a lost race reconciles from the refusal itself
/// rather than refetching the Session
/// (`packages/client/ui-message-feedback/src/client/controller.ts`).
///
/// The web surface's note/category dialog is deliberately absent: the phone
/// records the bare judgment, and the DTOs still carry a note or category
/// another client stored. `/feedback <text>` — the host's Session-level
/// remark — already reaches the phone through the composer's command roster
/// (`commands/execute`), so no dedicated session-feedback seat exists here.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/message_feedback.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../state_stream.dart';

/// The host's stable compare-and-set refusal code. It is the one refusal the
/// surface words differently: the reply carries the authoritative item, which
/// this controller commits before stating the reason.
const String kMessageFeedbackVersionConflict = 'version-conflict';

/// Refusal code this client raises for a write that never reached a host
/// verdict (a transport failure). It never crosses the wire.
const String kMessageFeedbackTransportRefusal = 'transport';

/// Load state of the one list read that seeds every control of a Session.
enum MessageFeedbackLoadStatus { loading, ready, failed }

/// Immutable view published to every feedback control of one Session.
final class MessageFeedbackUiState {
  const MessageFeedbackUiState({
    this.status = MessageFeedbackLoadStatus.loading,
    this.items = const <String, MessageFeedbackItem>{},
    this.failures = const <String, String>{},
    this.pending = const <String>{},
  });

  final MessageFeedbackLoadStatus status;

  /// Current item per addressed message id; a message absent here is
  /// unrated.
  final Map<String, MessageFeedbackItem> items;

  /// The last refusal code per message id, keyed like [items]. A successful
  /// write clears its message's entry; another message's failure stays.
  final Map<String, String> failures;

  /// Message ids with a write in flight; their controls stay inert so a
  /// double tap cannot queue a second compare-and-set.
  final Set<String> pending;
}

/// One Session's feedback object layer: the single list read, the per-message
/// mutations, and the view every control of that Session renders from.
class MessageFeedbackController {
  MessageFeedbackController(
    this._repository, {
    required this.backendId,
    required this.sessionId,
  }) {
    unawaited(refresh());
  }

  final ChatRepository _repository;

  /// The backend owning the addressed Session; carried for the diagnostic
  /// record only — every call addresses the repository it was built with.
  final String backendId;

  final String sessionId;

  final AppStateStream<MessageFeedbackUiState> _state =
      AppStateStream<MessageFeedbackUiState>(const MessageFeedbackUiState());

  MessageFeedbackLoadStatus _status = MessageFeedbackLoadStatus.loading;
  Map<String, MessageFeedbackItem> _items =
      const <String, MessageFeedbackItem>{};
  final Map<String, String> _failures = <String, String>{};
  final Set<String> _pending = <String>{};
  bool _disposed = false;

  MessageFeedbackUiState get state => _state.value;
  Stream<MessageFeedbackUiState> get uiState => _state.stream;

  void dispose() {
    _disposed = true;
    unawaited(_state.close());
  }

  /// Re-read the authoritative list. A failure keeps the previous items and
  /// publishes [MessageFeedbackLoadStatus.failed], which the rows word as
  /// their load notice.
  Future<void> refresh() async {
    try {
      final List<MessageFeedbackItem> items = await _repository
          .listMessageFeedback(sessionId);
      if (_disposed) return;
      _items = <String, MessageFeedbackItem>{
        for (final MessageFeedbackItem item in items) item.messageId: item,
      };
      _status = MessageFeedbackLoadStatus.ready;
    } on Object catch (error, stackTrace) {
      if (_disposed) return;
      _status = MessageFeedbackLoadStatus.failed;
      _log(error, stackTrace, 'list');
    }
    _publish();
  }

  /// Create or replace one message's judgment, comparing against the version
  /// this controller last observed.
  Future<void> rate(String messageId, MessageFeedbackRating rating) => _mutate(
    messageId,
    () => _repository.putMessageFeedback(
      sessionId,
      messageId: messageId,
      rating: rating,
      ifVersion: _items[messageId]?.version,
    ),
  );

  /// Retract one message's matching judgment. A different (or absent) stored
  /// rating makes this a no-op, so a stale retraction can never delete a
  /// judgment the human did not ask to remove.
  Future<void> retract(String messageId, MessageFeedbackRating rating) {
    final MessageFeedbackItem? observed = _items[messageId];
    if (observed == null || observed.rating != rating) {
      return Future<void>.value();
    }
    return _mutate(
      messageId,
      () => _repository.deleteMessageFeedback(
        sessionId,
        messageId: messageId,
        ifVersion: observed.version,
      ),
    );
  }

  Future<void> _mutate(
    String messageId,
    Future<MessageFeedbackWrite> Function() write,
  ) async {
    if (_disposed || !_pending.add(messageId)) return;
    _publish();
    final MessageFeedbackWrite settled;
    try {
      settled = await write();
    } on Object catch (error, stackTrace) {
      _pending.remove(messageId);
      _failures[messageId] = kMessageFeedbackTransportRefusal;
      _log(error, stackTrace, 'write');
      _publish();
      return;
    }
    if (_disposed) return;
    _pending.remove(messageId);
    switch (settled) {
      case MessageFeedbackCommitted(:final MessageFeedbackItem? item):
        _commit(messageId, item);
        _failures.remove(messageId);
      case MessageFeedbackRefused(:final String code, :final current):
        // The refusal's authoritative value is the host's own answer to the
        // lost race, so the row reconciles before it states the reason.
        if (code == kMessageFeedbackVersionConflict) {
          _commit(messageId, current);
        }
        _failures[messageId] = code;
    }
    _publish();
  }

  /// Replace one message's entry, keeping every other entry's identity.
  void _commit(String messageId, MessageFeedbackItem? item) {
    final Map<String, MessageFeedbackItem> items =
        Map<String, MessageFeedbackItem>.of(_items);
    if (item == null) {
      items.remove(messageId);
    } else {
      items[messageId] = item;
    }
    _items = items;
  }

  void _publish() {
    _state.value = MessageFeedbackUiState(
      status: _status,
      items: Map<String, MessageFeedbackItem>.unmodifiable(_items),
      failures: Map<String, String>.unmodifiable(_failures),
      pending: Set<String>.unmodifiable(_pending),
    );
  }

  /// Record a raw failure for diagnostics; the row states the host's own
  /// code, never the transport text.
  void _log(Object error, StackTrace stackTrace, String action) {
    ErrorLogCollector.instance.captureError(
      error,
      stackTrace: stackTrace,
      context: <String, Object?>{
        'controller': 'MessageFeedbackController',
        'action': action,
        'backendId': backendId,
        'sessionId': sessionId,
      },
    );
  }
}

/// One feedback controller per backend + Session: the strip and its notice
/// share the single list read, and a Session switch binds its own controller.
final messageFeedbackControllerProvider = Provider.family
    .autoDispose<
      MessageFeedbackController,
      ({String backendId, String sessionId})
    >((ref, key) {
      final controller = MessageFeedbackController(
        ref.watch(chatRepositoryProvider(key.backendId)),
        backendId: key.backendId,
        sessionId: key.sessionId,
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

/// The assistant row's Like/Dislike pair, seated in the action strip between
/// copy and fork.
class MessageFeedbackActions extends ConsumerWidget {
  const MessageFeedbackActions({
    required this.backendId,
    required this.sessionId,
    required this.messageId,
    super.key,
  });

  final String backendId;
  final String sessionId;
  final String messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(
      messageFeedbackControllerProvider((
        backendId: backendId,
        sessionId: sessionId,
      )),
    );
    return StreamBuilder<MessageFeedbackUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<MessageFeedbackUiState> snapshot,
          ) {
            final MessageFeedbackUiState state =
                snapshot.data ?? controller.state;
            final MessageFeedbackRating? recorded =
                state.items[messageId]?.rating;
            // Until the seeding read settles a tap cannot know whether it records
            // or retracts, so the pair stays inert.
            final bool enabled =
                state.status != MessageFeedbackLoadStatus.loading &&
                !state.pending.contains(messageId);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _Thumb(
                  rating: MessageFeedbackRating.positive,
                  recorded: recorded == MessageFeedbackRating.positive,
                  enabled: enabled,
                  onPressed: () => _choose(
                    controller,
                    recorded,
                    messageId,
                    MessageFeedbackRating.positive,
                  ),
                ),
                _Thumb(
                  rating: MessageFeedbackRating.negative,
                  recorded: recorded == MessageFeedbackRating.negative,
                  enabled: enabled,
                  onPressed: () => _choose(
                    controller,
                    recorded,
                    messageId,
                    MessageFeedbackRating.negative,
                  ),
                ),
              ],
            );
          },
    );
  }

  /// A tap on the recorded rating retracts it; either other tap records the
  /// judgment.
  void _choose(
    MessageFeedbackController controller,
    MessageFeedbackRating? recorded,
    String messageId,
    MessageFeedbackRating next,
  ) {
    if (recorded == next) {
      unawaited(controller.retract(messageId, next));
      return;
    }
    unawaited(controller.rate(messageId, next));
  }
}

/// The row's feedback notice: the load failure, or the last write's reason.
/// Empty while the pair is seeded and no write has failed.
class MessageFeedbackNotice extends ConsumerWidget {
  const MessageFeedbackNotice({
    required this.backendId,
    required this.sessionId,
    required this.messageId,
    super.key,
  });

  final String backendId;
  final String sessionId;
  final String messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(
      messageFeedbackControllerProvider((
        backendId: backendId,
        sessionId: sessionId,
      )),
    );
    return StreamBuilder<MessageFeedbackUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<MessageFeedbackUiState> snapshot,
          ) {
            final MessageFeedbackUiState state =
                snapshot.data ?? controller.state;
            final String? notice = _notice(context, state);
            if (notice == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                notice,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            );
          },
    );
  }

  String? _notice(BuildContext context, MessageFeedbackUiState state) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final String? failure = state.failures[messageId];
    if (failure != null) {
      return failure == kMessageFeedbackVersionConflict
          ? l10n.feedbackChangedElsewhere
          : l10n.feedbackSaveFailed;
    }
    if (state.status == MessageFeedbackLoadStatus.failed) {
      return l10n.feedbackLoadFailed;
    }
    return null;
  }
}

/// One thumb of the pair. A recorded judgment fills its glyph and takes the
/// accent role, so the signal is visible without a pointer.
class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.rating,
    required this.recorded,
    required this.enabled,
    required this.onPressed,
  });

  /// The judgment this thumb records.
  final MessageFeedbackRating rating;

  /// Whether this thumb's judgment is the stored one.
  final bool recorded;

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final bool up = rating == MessageFeedbackRating.positive;
    final Color tint = !enabled
        ? scheme.onSurfaceVariant.withValues(alpha: 0.38)
        : recorded
        ? scheme.primary
        : scheme.onSurfaceVariant;
    final IconData glyph = up
        ? (recorded ? Icons.thumb_up : Icons.thumb_up_outlined)
        : (recorded ? Icons.thumb_down : Icons.thumb_down_outlined);
    return IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      tooltip: recorded
          ? l10n.feedbackRetract
          : (up ? l10n.feedbackRateUp : l10n.feedbackRateDown),
      onPressed: enabled ? onPressed : null,
      icon: Icon(glyph, color: tint),
    );
  }
}
