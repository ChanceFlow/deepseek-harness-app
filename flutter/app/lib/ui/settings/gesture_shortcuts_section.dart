/// Gestures — the phone's answer to the reference's keyboard-shortcut surface.
///
/// The decision, stated once here because it is the section's whole design:
/// the pin's `ui-shortcuts` package is an **editor**. It records key
/// combinations, persists them (`dsh.keybindings.v1` on the web,
/// `userData/keybindings.json` on the desktop) and restores defaults
/// (`ui-shortcuts/README.md`, "Use this package"; the settings entry is
/// `ui-shortcuts/src/client/index.ts:54-59`). A phone has no hardware keyboard,
/// so a binding table would list combinations nobody can press, a recorder
/// would capture nothing, and a written document would name keys the device
/// cannot deliver. The editor half is therefore **absent by design**, not
/// faked — and no platform settings link replaces it, because Android's
/// keyboard settings configure input methods, not this app's commands.
///
/// What the phone does have is gestures, and this app already answers them.
/// This page is the pin's *other* half — its read-only reference — with the
/// phone's own bindings. Every row below is an interaction this client
/// implements; none is invented, and each names where it lives:
///
/// - long-press a message → copy, or fork the conversation from it
///   (`chat/chat_screen.dart:3163`, `enum _BubbleVerb { copy, fork }`);
/// - long-press a session row → rename, fork, pin or archive it
///   (`shared/session_tree.dart:391-410`);
/// - long-press a project header → start a session in that project
///   (`chat/session_panel.dart:1341`, `onLongPress: onNewSession`);
/// - hold the microphone → talk instead of typing
///   (`chat/voice_input/voice_hold_bar.dart`, `l10n.voiceHoldToTalk`);
/// - scroll to the top of the transcript → load older history
///   (`chat/chat_screen.dart:2125`, `LoadOlderHistoryAction`).
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'settings_chrome.dart';

/// The Settings → App index row that opens the gesture reference.
class SettingsGesturesEntryRow extends StatelessWidget {
  const SettingsGesturesEntryRow({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return SettingsNavRow(
      title: l10n.settingsGesturesTitle,
      leading: const Icon(Icons.touch_app_outlined),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => const SettingsGesturesPage(),
        ),
      ),
    );
  }
}

/// The reference itself: one row per gesture, and the reason the pin's editor
/// has no counterpart here.
class SettingsGesturesPage extends StatelessWidget {
  const SettingsGesturesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final List<(String, String)> gestures = <(String, String)>[
      (l10n.settingsGesturesMessageTitle, l10n.settingsGesturesMessageBody),
      (l10n.settingsGesturesSessionTitle, l10n.settingsGesturesSessionBody),
      (l10n.settingsGesturesProjectTitle, l10n.settingsGesturesProjectBody),
      (l10n.settingsGesturesVoiceTitle, l10n.settingsGesturesVoiceBody),
      (l10n.settingsGesturesHistoryTitle, l10n.settingsGesturesHistoryBody),
    ];
    return SettingsPageScaffold(
      title: l10n.settingsGesturesTitle,
      children: <Widget>[
        SettingsSectionCard(
          children: <Widget>[
            for (final (int index, (String, String) gesture)
                in gestures.indexed) ...<Widget>[
              if (index > 0) const SettingsCardDivider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      gesture.$1,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      gesture.$2,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            l10n.settingsGesturesIntro,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            l10n.settingsGesturesEditorNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.labelTertiary,
            ),
          ),
        ),
      ],
    );
  }
}
