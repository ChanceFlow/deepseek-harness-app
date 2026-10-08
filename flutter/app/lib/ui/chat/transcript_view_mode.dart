/// The transcript view mode — the reference's work-details preference, and the
/// presentation policy the transcript's folding seats select from.
///
/// The pin keeps the mode in the Host user-settings document, namespace
/// `ui-chat`, field `transcriptView` (`ui-chat/src/chat-settings.ts:6`, `:9`),
/// as one of four options with a legacy pair that reads back as `detailed` and
/// is never written again (`:12-27`). What the mode is *for* is the policy
/// table in `ui-chat/src/client/presentation-policy.ts`: `foldCompletedTurns`
/// stays true in compact, standard and detailed and turns false only in
/// `verbose` (`:27`, `:34`, `:41`, `:48`), beside `stepGrouping`,
/// `liveProcessDetail` and `settledReasoningPreview` (`:17`). Renderers select
/// one field of the policy; none of them compares the enum (`:1-5`).
///
/// One seat of that policy is wired here: a completed Turn folds its process
/// behind the Turn control unless the policy says otherwise. The other three
/// fields are carried so a later seat can select them without touching the
/// table, which is what keeps "add a mode" a one-line change.
library;

import 'dart:async';
import 'dart:convert';

import 'package:domain/repository/chat_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../state_stream.dart';

/// The Host settings namespace the Chat target owns.
const String kChatSettingsNamespace = 'ui-chat';

/// The field carrying the transcript view mode.
const String kTranscriptViewField = 'transcriptView';

/// The mode a device that never chose one reads as. The reference takes
/// `standard` on desktop and this value elsewhere (`chat-settings.ts:32`,
/// `apply.ts:149`); this client is the phone.
const TranscriptViewMode kDefaultTranscriptViewMode =
    TranscriptViewMode.detailed;

/// How much of a Turn's work the transcript shows.
enum TranscriptViewMode {
  /// Folded groups, no live call detail, no settled reasoning preview.
  compact,

  /// Folded groups with live call detail and the reasoning preview.
  standard,

  /// Standard, with group headers for historical Turns.
  detailed,

  /// Nothing folds and no group header collapses: the Turn shows its work.
  verbose;

  /// The stored form (the wire value), the same four names the pin accepts.
  String get wireName => name;

  /// The policy this mode selects.
  ChatPresentationPolicy get policy => presentationPolicyFor(this);

  /// Resolve a stored value; null when it names no mode, so an unknown value
  /// leaves the client default standing. The two saved values from the older
  /// two-mode generation read as [detailed] (`chat-settings.ts:20-27`).
  static TranscriptViewMode? fromStored(Object? stored) {
    for (final mode in TranscriptViewMode.values) {
      if (mode.wireName == stored) return mode;
    }
    if (stored == 'normal' || stored == 'expanded') {
      return TranscriptViewMode.detailed;
    }
    return null;
  }
}

/// Collapsible group headers for all Turns, historical Turns only, or none.
enum StepGrouping { collapsed, history, none }

/// The presentation capabilities one mode enables — the pin's
/// `ChatPresentationPolicy`, field for field.
final class ChatPresentationPolicy {
  const ChatPresentationPolicy({
    required this.mode,
    required this.foldCompletedTurns,
    required this.stepGrouping,
    required this.liveProcessDetail,
    required this.settledReasoningPreview,
  });

  /// The mode this policy was derived from; for diagnostics, never for
  /// branching in a renderer.
  final TranscriptViewMode mode;

  /// Whether a normally completed Turn folds its process rows behind the
  /// whole-Turn control.
  final bool foldCompletedTurns;

  /// Collapsible group headers for all Turns, historical Turns only, or none.
  final StepGrouping stepGrouping;

  /// Show the running command, path, query or reasoning detail in group
  /// titles.
  final bool liveProcessDetail;

  /// Whether a settled reasoning row previews its first line beside its title.
  final bool settledReasoningPreview;
}

/// The policy each mode selects — the pin's table
/// (`presentation-policy.ts:18-49`), the only place a mode's behaviour is
/// named.
const ChatPresentationPolicy kCompactPresentation = ChatPresentationPolicy(
  mode: TranscriptViewMode.compact,
  foldCompletedTurns: true,
  stepGrouping: StepGrouping.collapsed,
  liveProcessDetail: false,
  settledReasoningPreview: false,
);

const ChatPresentationPolicy kStandardPresentation = ChatPresentationPolicy(
  mode: TranscriptViewMode.standard,
  foldCompletedTurns: true,
  stepGrouping: StepGrouping.collapsed,
  liveProcessDetail: true,
  settledReasoningPreview: true,
);

const ChatPresentationPolicy kDetailedPresentation = ChatPresentationPolicy(
  mode: TranscriptViewMode.detailed,
  foldCompletedTurns: true,
  stepGrouping: StepGrouping.history,
  liveProcessDetail: true,
  settledReasoningPreview: true,
);

const ChatPresentationPolicy kVerbosePresentation = ChatPresentationPolicy(
  mode: TranscriptViewMode.verbose,
  foldCompletedTurns: false,
  stepGrouping: StepGrouping.none,
  liveProcessDetail: false,
  settledReasoningPreview: true,
);

/// The policy a device that never chose a mode folds by.
const ChatPresentationPolicy kDefaultChatPresentationPolicy =
    kDetailedPresentation;

/// The policy for one mode.
ChatPresentationPolicy presentationPolicyFor(TranscriptViewMode mode) =>
    switch (mode) {
      TranscriptViewMode.compact => kCompactPresentation,
      TranscriptViewMode.standard => kStandardPresentation,
      TranscriptViewMode.detailed => kDetailedPresentation,
      TranscriptViewMode.verbose => kVerbosePresentation,
    };

/// One resolved transcript-view state.
final class TranscriptViewState {
  const TranscriptViewState({
    this.mode = kDefaultTranscriptViewMode,
    this.revision,
    this.exposed = false,
    this.writable = false,
    this.loading = false,
    this.saving = false,
    this.failed = false,
  });

  /// The persisted mode, or the client default while unread, unknown, or
  /// absent — the pin treats an absent field as "use the client default"
  /// (`chat-settings.ts:62-64`).
  final TranscriptViewMode mode;

  /// The `ui-chat` revision the last describe reported (the write's CAS
  /// guard); null before a successful describe.
  final int? revision;

  /// Whether the Host answered for the `ui-chat` namespace at all.
  final bool exposed;

  /// Whether the Host accepts settings writes.
  final bool writable;

  final bool loading;
  final bool saving;

  /// A read or write failed; the row states it and offers a retry.
  final bool failed;

  TranscriptViewState copyWith({
    TranscriptViewMode? mode,
    int? revision,
    bool? exposed,
    bool? writable,
    bool? loading,
    bool? saving,
    bool? failed,
  }) => TranscriptViewState(
    mode: mode ?? this.mode,
    revision: revision ?? this.revision,
    exposed: exposed ?? this.exposed,
    writable: writable ?? this.writable,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    failed: failed ?? this.failed,
  );
}

/// UDF controller over the Host `ui-chat` namespace: reads on construction,
/// publishes every change, and writes the mode with the described revision as
/// its CAS guard before confirming it with a fresh describe.
class TranscriptViewController {
  TranscriptViewController(this._repository) {
    unawaited(refresh());
  }

  final ChatRepository _repository;
  final AppStateStream<TranscriptViewState> _state =
      AppStateStream<TranscriptViewState>(const TranscriptViewState());

  TranscriptViewState get state => _state.value;
  Stream<TranscriptViewState> get uiState => _state.stream;

  void dispose() {
    unawaited(_state.close());
  }

  /// Re-describe the namespace and adopt what the Host reports.
  Future<void> refresh() async {
    _state.value = _state.value.copyWith(loading: true, failed: false);
    try {
      final snapshot = await _repository.describeSettings();
      final namespace = snapshot.namespaces
          .where((entry) => entry.ns == kChatSettingsNamespace)
          .firstOrNull;
      final value = namespace?.value;
      _state.value = TranscriptViewState(
        mode:
            (value is Map
                ? TranscriptViewMode.fromStored(value[kTranscriptViewField])
                : null) ??
            kDefaultTranscriptViewMode,
        revision: namespace?.revision,
        exposed: namespace != null,
        writable: snapshot.writable,
      );
    } catch (error) {
      _state.value = _state.value.copyWith(loading: false, failed: true);
      ErrorLogCollector.instance.addBreadcrumb(
        'Transcript view describe failed: $error',
        level: 'warning',
      );
    }
  }

  /// Persist one mode. The transcript re-folds optimistically with the tap and
  /// reverts when the Host refuses the write.
  Future<void> select(TranscriptViewMode mode) async {
    final before = _state.value;
    if (mode == before.mode || before.saving) return;
    _state.value = before.copyWith(mode: mode, saving: true, failed: false);
    try {
      await _repository.updateSetting(
        kChatSettingsNamespace,
        kTranscriptViewField,
        jsonEncode(mode.wireName),
        expectedRevision: before.revision,
      );
      await refresh();
    } catch (error) {
      _state.value = before.copyWith(saving: false, failed: true);
      ErrorLogCollector.instance.addBreadcrumb(
        'Transcript view write failed: $error',
        level: 'warning',
      );
    }
  }
}

/// One controller per backend: the describe and the CAS-guarded write share
/// the repository the rest of the settings surface uses.
final transcriptViewControllerProvider = Provider.family
    .autoDispose<TranscriptViewController, String>((ref, backendId) {
      final controller = TranscriptViewController(
        ref.watch(chatRepositoryProvider(backendId)),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

/// The one accessor the transcript reads: the Host's mode, or the client
/// default while the Host has not answered. The settings row writes through
/// the same controller, so a mid-session change reaches the transcript without
/// a wire round-trip.
final transcriptViewModeProvider =
    StreamProvider.family<TranscriptViewMode, String>((ref, backendId) async* {
      final controller = ref.watch(transcriptViewControllerProvider(backendId));
      yield* controller.uiState.map((state) => state.mode);
    });
