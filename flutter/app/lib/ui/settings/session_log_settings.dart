/// Session-log upload row — the reference's General-settings switch over the
/// Host's `session-log-deepseek` configuration.
///
/// Pin: `ui-settings-session-log/src/client/index.ts:45-46` registers
/// `UploadRow` on `settings.general.item` while the Host serves the namespace's
/// config form, and `UploadRow.tsx:29-36` renders the accepted value of one
/// boolean as a switch beside the title and description. The write is
/// `upload-preference.ts:33-46`: `form.set('enabled', …)`, keeping the accepted
/// value and reporting the outcome when the Host refuses.
///
/// The plane is the one this client already speaks. The pin's form reads the
/// shared describe mirror (`ui-settings/src/client/config-form.ts:191`) and
/// writes with `settings/mutate` under the described revision (`:139`) — which
/// is [ChatRepository.describeSettings] plus the revision
/// [ChatRepository.updateSetting] takes as its CAS guard. The field is the
/// plugin's own `enabled` (`session/session-log-deepseek/src/index.ts:41`,
/// `:52`), so the switch edits live configuration rather than a stored
/// preference.
///
/// The row is absent unless the Host serves the namespace — the pin's
/// `whileServed` gate (`index.ts:45`) — because a Host that never published the
/// entry has no value to show, and a client-side default would write a
/// namespace the Host does not own.
library;

import 'dart:async';
import 'dart:convert';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../state_stream.dart';

/// The Host plugin entry this row edits.
const String kSessionLogSettingsNs = 'session-log-deepseek';

/// The entry's field: contribute `dsh_session_log` to official API requests.
const String kSessionLogEnabledField = 'enabled';

/// What the Host reported for the entry's field.
final class SessionLogUploadState {
  const SessionLogUploadState({
    this.enabled = true,
    this.revision,
    this.exposed = false,
    this.writable = false,
    this.saving = false,
    this.failed = false,
  });

  /// The accepted value. The plugin's schema defaults it to `true`
  /// (`session-log-deepseek/src/index.ts:52`), which is what a namespace that
  /// exposes the field without carrying it reads as.
  final bool enabled;

  /// The revision the last describe reported — the write's CAS guard.
  final int? revision;

  /// Whether the Host serves the namespace at all.
  final bool exposed;

  /// Whether the Host accepts writes to it (a loopback-pinned session).
  final bool writable;

  final bool saving;
  final bool failed;

  SessionLogUploadState copyWith({
    bool? enabled,
    int? revision,
    bool? exposed,
    bool? writable,
    bool? saving,
    bool? failed,
  }) => SessionLogUploadState(
    enabled: enabled ?? this.enabled,
    revision: revision ?? this.revision,
    exposed: exposed ?? this.exposed,
    writable: writable ?? this.writable,
    saving: saving ?? this.saving,
    failed: failed ?? this.failed,
  );
}

/// UDF controller over the Host's `session-log-deepseek` entry: describes on
/// construction, writes the field with the described revision as its CAS guard,
/// and re-describes before it confirms anything.
class SessionLogUploadController {
  SessionLogUploadController(this._repository) {
    unawaited(refresh());
  }

  final ChatRepository _repository;
  final AppStateStream<SessionLogUploadState> _state =
      AppStateStream<SessionLogUploadState>(const SessionLogUploadState());

  SessionLogUploadState get state => _state.value;
  Stream<SessionLogUploadState> get uiState => _state.stream;

  void dispose() {
    unawaited(_state.close());
  }

  /// Re-describe the entry and adopt what the Host reports.
  Future<void> refresh() async {
    try {
      final snapshot = await _repository.describeSettings();
      final namespace = snapshot.namespaces
          .where((entry) => entry.ns == kSessionLogSettingsNs)
          .firstOrNull;
      final value = namespace?.value;
      final enabled = value is Map ? value[kSessionLogEnabledField] : null;
      _state.value = SessionLogUploadState(
        enabled: enabled is bool ? enabled : true,
        revision: namespace?.revision,
        exposed: namespace != null,
        writable: snapshot.writable,
      );
    } catch (error) {
      _state.value = _state.value.copyWith(failed: true);
      ErrorLogCollector.instance.addBreadcrumb(
        'Session-log upload describe failed: $error',
        level: 'warning',
      );
    }
  }

  /// Persist one value. The switch never flips optimistically: the accepted
  /// value stays visible until the Host's answer comes back, which is the pin's
  /// own rule for a refused write (`upload-preference.ts:38-46`).
  Future<void> setEnabled(bool enabled) async {
    final before = _state.value;
    if (!before.exposed || !before.writable || before.saving) return;
    if (enabled == before.enabled) return;
    _state.value = before.copyWith(saving: true, failed: false);
    try {
      await _repository.updateSetting(
        kSessionLogSettingsNs,
        kSessionLogEnabledField,
        jsonEncode(enabled),
        expectedRevision: before.revision,
      );
      await refresh();
    } catch (error) {
      _state.value = before.copyWith(saving: false, failed: true);
      ErrorLogCollector.instance.addBreadcrumb(
        'Session-log upload write failed: $error',
        level: 'warning',
      );
    }
  }
}

/// One controller per backend: the describe and the CAS-guarded write share the
/// repository the rest of the settings surface uses.
final sessionLogUploadControllerProvider = Provider.family
    .autoDispose<SessionLogUploadController, String>((ref, backendId) {
      final controller = SessionLogUploadController(
        ref.watch(chatRepositoryProvider(backendId)),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

/// The Settings → App row: the Host's Session-log upload switch, in the place
/// the pin seats it — one item in the general settings list
/// (`settings.general.item`, order 90), not a page of its own.
class SettingsSessionLogRow extends ConsumerWidget {
  const SettingsSessionLogRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String backendId = ref.watch(activeBackendIdProvider).value ?? '';
    if (backendId.isEmpty) return const SizedBox.shrink();
    final SessionLogUploadController controller = ref.watch(
      sessionLogUploadControllerProvider(backendId),
    );
    return StreamBuilder<SessionLogUploadState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder: (BuildContext context, AsyncSnapshot<SessionLogUploadState> snap) {
        final SessionLogUploadState state = snap.data ?? controller.state;
        // The Host does not serve the entry: nothing to switch, so nothing is
        // rendered (the pin's `whileServed` gate).
        if (!state.exposed) return const SizedBox.shrink();
        return _SessionLogRowBody(state: state, controller: controller);
      },
    );
  }
}

/// The row itself: the pin's `.row` — a title over its description, with the
/// switch on the trailing edge (`UploadRow.module.css:1-19`).
class _SessionLogRowBody extends StatelessWidget {
  const _SessionLogRowBody({required this.state, required this.controller});

  final SessionLogUploadState state;
  final SessionLogUploadController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.settingsSessionLogTitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.settingsSessionLogDescription,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (state.failed) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    l10n.settingsSessionLogSaveFailed,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Inert while the Host refuses writes or a save is in flight, so the
          // control can never promise a write it will not make.
          Switch(
            value: state.enabled,
            onChanged: state.writable && !state.saving
                ? (bool value) => unawaited(controller.setEnabled(value))
                : null,
          ),
        ],
      ),
    );
  }
}
