/// The native settings page behind the shell's settings orb.
///
/// One page, five grouped cards: the configured hosts (edit, add, remove), the
/// Android notification permission and its keep-alive note, the appearance
/// choice, the interface language, and the build's version. Host mutations go
/// through [showHostEditor]; the appearance and language choices ride the
/// existing controllers through the seams below so the page never owns their
/// state.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../di/providers.dart';
import '../local_state/locale_preference.dart';
import '../notifications/notification_channel_health.dart';
import '../notifications/notification_preferences.dart';
import '../notifications/system_notifier.dart';
import '../theme/theme.dart';
import '../theme/theme_preference.dart';
import 'host_editor.dart';

// ---------------------------------------------------------------------------
// The preference and language seams.
// ---------------------------------------------------------------------------

/// The host `ui-theme` preference the Appearance card renders.
///
/// Production resolves the active backend's controller; the card watches it so
/// a write landing elsewhere (a second settings surface, the host's own page)
/// refreshes the selected seat.
final shellThemePreferenceProvider = StreamProvider<ThemePreferenceState>((
  ref,
) async* {
  final String backendId = ref.watch(activeBackendIdProvider).value ?? '';
  if (backendId.isEmpty) {
    yield const ThemePreferenceState();
    return;
  }
  final ThemePreferenceController controller = ref.watch(
    themePreferenceControllerProvider(backendId),
  );
  yield controller.state;
  yield* controller.uiState;
});

/// Applies one appearance choice: OLED flips the device-local flag, every
/// other seat clears it and writes the host's `ui-theme.preference`.
typedef ShellThemeSelect = Future<void> Function(ThemePreference preference);

/// The theme write seam: production drives the OLED and theme controllers, a
/// test records the choice.
final shellThemeSelectProvider = Provider<ShellThemeSelect>((ref) {
  return (ThemePreference preference) async {
    OledAppearanceController? oled;
    try {
      oled = await ref.read(oledAppearanceControllerProvider.future);
    } on Object catch (_) {
      // The device-local store is unavailable; only the host seats can work.
      oled = null;
    }
    if (preference == ThemePreference.oled) {
      if (oled != null) await oled.select(true);
      return;
    }
    if (oled != null && oled.state) await oled.select(false);
    final String backendId = ref.read(activeBackendIdProvider).value ?? '';
    if (backendId.isEmpty) return;
    await ref
        .read(themePreferenceControllerProvider(backendId))
        .select(preference);
  };
});

/// Re-describes the host theme namespace; the Retry seat beside the
/// "unavailable" note.
typedef ShellThemeRefresh = Future<void> Function();

/// The theme refresh seam.
final shellThemeRefreshProvider = Provider<ShellThemeRefresh>((ref) {
  return () async {
    final String backendId = ref.read(activeBackendIdProvider).value ?? '';
    if (backendId.isEmpty) return;
    await ref.read(themePreferenceControllerProvider(backendId)).refresh();
  };
});

/// Applies one interface language.
typedef ShellLocaleSelect = Future<void> Function(
  AppLocalePreference preference,
);

/// The language write seam: production persists through the device-local
/// locale controller, a test records the choice.
final shellLocaleSelectProvider = Provider<ShellLocaleSelect>((ref) {
  return (AppLocalePreference preference) async {
    final LocalePreferenceController controller = await ref.read(
      localePreferenceProvider.future,
    );
    await controller.select(preference);
  };
});

// ---------------------------------------------------------------------------
// The page.
// ---------------------------------------------------------------------------

/// The settings page: custom header, then one card per group.
class ShellSettingsScreen extends ConsumerWidget {
  const ShellSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final BackendRegistryState registry =
        ref.watch(backendRegistryStateProvider).value ??
        const BackendRegistryState();
    return Scaffold(
      backgroundColor: scheme.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            _SettingsHeader(title: l10n.destinationSettings),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _SettingsCard(
                    title: l10n.settingsSectionHost,
                    action: IconButton(
                      onPressed: () => unawaited(showHostEditor(context)),
                      icon: const Icon(Icons.add),
                      tooltip: l10n.addBackend,
                    ),
                    children: _hostRows(context, registry),
                  ),
                  const _NotificationCard(),
                  const _AppearanceCard(),
                  const _LanguageCard(),
                  const _AboutCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One row per configured backend, including disabled ones, plus the last
  /// controller error when there is one.
  List<Widget> _hostRows(BuildContext context, BackendRegistryState registry) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<BackendConfig> hosts = registry.backends;
    if (hosts.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Text(
            l10n.noHostsTitle,
            style: DshType.s14.style(color: scheme.labelTertiary),
          ),
        ),
      ];
    }
    return [
      for (var index = 0; index < hosts.length; index++) ...[
        if (index > 0) const _RowDivider(),
        _HostRow(
          host: hosts[index],
          active: hosts[index].id == registry.activeId,
        ),
      ],
      if (registry.errorMessage != null) ...[
        const _RowDivider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Text(
            _registryErrorText(l10n, registry.errorMessage!),
            style: DshType.xs13.style(color: scheme.stateErrorPrimary),
          ),
        ),
      ],
    ];
  }
}

/// The custom header: a back arrow and the page title on the shell's aliases.
class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      height: 52,
      padding: const EdgeInsets.only(left: 4, right: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(width: 0.5, color: scheme.borderL2)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DshType.l20.style(color: scheme.labelPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A grouped card: a title strip, an action seat, and the rows beneath.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.children,
    this.action,
  });

  final String title;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.bgLayer2,
        borderRadius: BorderRadius.circular(kRadiusMd),
        border: Border.all(width: 0.5, color: scheme.borderL4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: DshType.xsStrong13.style(
                      color: scheme.labelSecondary,
                    ),
                  ),
                ),
                if (action != null) action!,
              ],
            ),
          ),
          const _RowDivider(),
          ...children,
        ],
      ),
    );
  }
}

/// The hairline between rows on the pin's border scale.
class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Divider(height: 1, thickness: 0.5, color: scheme.borderL2);
  }
}

/// One configured host: label, authority, connection dot, active check or
/// disabled state. Tapping it opens the editor.
class _HostRow extends ConsumerWidget {
  const _HostRow({required this.host, required this.active});

  final BackendConfig host;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final connection = ref.watch(backendConnectionStateProvider(host.id)).value;
    final bool live = connection == null || connection.isConnected;
    final Color ink = host.enabled ? scheme.labelPrimary : scheme.labelDimmed;
    final Color dot = !host.enabled
        ? scheme.labelCaption
        : live
        ? scheme.stateSuccessPrimary
        : scheme.labelCaption;
    return InkWell(
      onTap: () => unawaited(showHostEditor(context, host: host)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    host.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DshType.sStrong14.style(color: ink),
                  ),
                  Text(
                    host.baseUri.authority,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DshType.xxs12.style(color: scheme.labelTertiary),
                  ),
                ],
              ),
            ),
            if (!host.enabled)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  l10n.backendStatusDisabled,
                  style: DshType.xxs12.style(color: scheme.labelCaption),
                ),
              )
            else if (active)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.check,
                  size: 16,
                  color: scheme.stateBusinessPrimary,
                ),
              ),
            Icon(Icons.chevron_right, size: 18, color: scheme.labelTertiary),
          ],
        ),
      ),
    );
  }
}

/// Notifications: the Android permission row, the channel-health block when
/// Android is silencing a channel, the master switch with one seat per kind,
/// and the keep-alive note.
class _NotificationCard extends ConsumerWidget {
  const _NotificationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final NotificationPreferences preferences = ref.watch(
      notificationPreferencesProvider,
    );
    final NotificationChannelHealth? health = ref
        .watch(notificationChannelHealthProvider)
        .value;
    final bool healthBlocked = health != null && !health.allEnabled;
    return _SettingsCard(
      title: l10n.settingsNotificationsSection,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Text(
            l10n.settingsNotifyDescription,
            style: DshType.xxs12.style(color: scheme.labelTertiary),
          ),
        ),
        const _RowDivider(),
        const _NotificationPermissionRow(),
        if (healthBlocked) ...[
          const _RowDivider(),
          const _NotificationHealthBlock(),
        ],
        const _RowDivider(),
        _NotificationSwitchRow(
          switchKey: const ValueKey<String>('settingsNotifyMaster'),
          label: l10n.settingsNotifyMaster,
          value: preferences.enabled,
          enabled: true,
          onChanged: (bool value) {
            unawaited(
              ref
                  .read(notificationPreferencesProvider.notifier)
                  .setEnabled(value),
            );
          },
        ),
        const _RowDivider(),
        _NotificationSwitchRow(
          switchKey: const ValueKey<String>('settingsNotifyReplies'),
          label: l10n.settingsNotifyReplies,
          value: preferences.replies,
          enabled: preferences.enabled,
          onChanged: (bool value) {
            unawaited(
              ref
                  .read(notificationPreferencesProvider.notifier)
                  .setReplies(value),
            );
          },
        ),
        const _RowDivider(),
        _NotificationSwitchRow(
          switchKey: const ValueKey<String>('settingsNotifyFailures'),
          label: l10n.settingsNotifyFailures,
          value: preferences.failures,
          enabled: preferences.enabled,
          onChanged: (bool value) {
            unawaited(
              ref
                  .read(notificationPreferencesProvider.notifier)
                  .setFailures(value),
            );
          },
        ),
        const _RowDivider(),
        _NotificationSwitchRow(
          switchKey: const ValueKey<String>('settingsNotifyAttention'),
          label: l10n.settingsNotifyAttention,
          value: preferences.attention,
          enabled: preferences.enabled,
          onChanged: (bool value) {
            unawaited(
              ref
                  .read(notificationPreferencesProvider.notifier)
                  .setAttention(value),
            );
          },
        ),
        const _RowDivider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Text(
            l10n.settingsKeepAliveNote,
            style: DshType.xxs12.style(color: scheme.labelTertiary),
          ),
        ),
      ],
    );
  }
}

/// One notification preference. A row under a silenced master dims and goes
/// inert while still showing its stored value.
///
/// A plain [Switch] rather than a `SwitchListTile`: a `ListTile` inside the
/// card's decorated surface trips Flutter's ink-visibility assertion.
class _NotificationSwitchRow extends StatelessWidget {
  const _NotificationSwitchRow({
    required this.switchKey,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  /// The stable test hook: the ARB key the row renders, not its localized
  /// text, so a test can find the seat in either language.
  final Key switchKey;
  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // The whole row toggles; MergeSemantics makes the label and the switch
    // one announced switch instead of a loose text plus a control.
    return MergeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged(!value) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: DshType.s14.style(
                    color: enabled ? scheme.labelPrimary : scheme.labelDimmed,
                  ),
                ),
              ),
              Switch(
                key: switchKey,
                value: value,
                onChanged: enabled ? onChanged : null,
                activeThumbColor: scheme.aliases.switchThumb,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Android's own answer: a channel is silenced somewhere the app cannot undo
/// it. The block renders only while the watched health says so; the button
/// opens the system page and re-reads the health when the user returns.
class _NotificationHealthBlock extends ConsumerWidget {
  const _NotificationHealthBlock();

  Future<void> _openSettings(BuildContext context, WidgetRef ref) async {
    await ref.read(openNotificationSettingsProvider)();
    if (!context.mounted) return;
    ref.invalidate(notificationChannelHealthProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsNotifyHealthTitle,
            style: DshType.xxsStrong12.style(color: scheme.labelSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.settingsNotifyHealthBlocked,
            style: DshType.xxs12.style(color: scheme.labelTertiary),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => unawaited(_openSettings(context, ref)),
            child: Text(l10n.settingsNotifyHealthOpen),
          ),
        ],
      ),
    );
  }
}

/// The permission row: state readable at a glance, and the one ask.
class _NotificationPermissionRow extends ConsumerStatefulWidget {
  const _NotificationPermissionRow();

  @override
  ConsumerState<_NotificationPermissionRow> createState() =>
      _NotificationPermissionRowState();
}

class _NotificationPermissionRowState
    extends ConsumerState<_NotificationPermissionRow> {
  /// The host's answer once this row asked; null reads the notifier.
  bool? _resolved;

  bool _requesting = false;

  Future<void> _request(SystemNotifier notifier) async {
    if (_requesting) return;
    setState(() => _requesting = true);
    final bool granted = await notifier.ensurePermissionRequested();
    if (!mounted) return;
    setState(() {
      _resolved = granted;
      _requesting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final SystemNotifier notifier = ref.watch(systemNotifierProvider);
    final bool granted = _resolved ?? notifier.permissionGranted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsNotificationPermission,
                  style: DshType.s14.style(color: scheme.labelPrimary),
                ),
                if (!granted) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.notificationPermissionBody,
                    style: DshType.xxs12.style(color: scheme.labelTertiary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (granted)
            Icon(
              Icons.check_circle,
              size: 20,
              color: scheme.stateSuccessPrimary,
            )
          else
            FilledButton(
              onPressed: _requesting
                  ? null
                  : () => unawaited(_request(notifier)),
              child: Text(l10n.settingsNotificationGrant),
            ),
        ],
      ),
    );
  }
}

/// The built-in appearance choices in the order the page shows them.
const List<ThemePreference> _appearanceOrder = <ThemePreference>[
  ThemePreference.system,
  ThemePreference.light,
  ThemePreference.dark,
  ThemePreference.oled,
];

String _appearanceLabel(AppLocalizations l10n, ThemePreference option) =>
    switch (option) {
      ThemePreference.light => l10n.settingsAppearanceLight,
      ThemePreference.dark => l10n.settingsAppearanceDark,
      ThemePreference.oled => l10n.settingsAppearanceOled,
      ThemePreference.system => l10n.settingsAppearanceSystem,
    };

/// Appearance: the host's three seats plus the device-local OLED one.
///
/// OLED is device-local and wins while it is on, so it is the selected seat;
/// a host seat clears it and writes the host preference. The host seats are
/// inert while the host refuses writes or exposes no theme namespace, and the
/// note names that instead of pretending `system` was the stored value.
class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemePreferenceState? host = ref
        .watch(shellThemePreferenceProvider)
        .value;
    final bool oledOn = ref.watch(appOledAppearanceProvider).value ?? false;
    final ThemePreference selected = oledOn
        ? ThemePreference.oled
        : host?.preference ?? ThemePreference.system;
    final bool hostSeatsEnabled =
        host != null && host.writable && host.exposed && !host.saving;
    final bool showUnavailable = host != null && !host.loading && !host.exposed;
    return _SettingsCard(
      title: l10n.settingsAppearanceTitle,
      children: [
        for (var index = 0; index < _appearanceOrder.length; index++) ...[
          if (index > 0) const _RowDivider(),
          _SelectableRow(
            label: _appearanceLabel(l10n, _appearanceOrder[index]),
            selected: selected == _appearanceOrder[index],
            enabled:
                _appearanceOrder[index] == ThemePreference.oled ||
                hostSeatsEnabled,
            onTap: () {
              unawaited(
                ref.read(shellThemeSelectProvider)(_appearanceOrder[index]),
              );
            },
          ),
        ],
        if (showUnavailable) ...[
          const _RowDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.settingsAppearanceUnavailable,
                    style: DshType.xxs12.style(color: scheme.labelTertiary),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    unawaited(ref.read(shellThemeRefreshProvider)());
                  },
                  child: Text(l10n.retry),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The interface language choices in the order the page shows them.
const List<AppLocalePreference> _localeOrder = <AppLocalePreference>[
  AppLocalePreference.system,
  AppLocalePreference.en,
  AppLocalePreference.zh,
];

String _localeLabel(AppLocalizations l10n, AppLocalePreference option) =>
    switch (option) {
      AppLocalePreference.system => l10n.languageOptionSystem,
      AppLocalePreference.en => l10n.languageOptionEn,
      AppLocalePreference.zh => l10n.languageOptionZh,
    };

/// Language: the device-local interface language, persisted immediately.
class _LanguageCard extends ConsumerWidget {
  const _LanguageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final AppLocalePreference selected =
        ref.watch(appLocalePreferenceProvider).value ??
        AppLocalePreference.system;
    return _SettingsCard(
      title: l10n.languageLabel,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
          child: Text(
            l10n.languageDescription,
            style: DshType.xxs12.style(color: scheme.labelTertiary),
          ),
        ),
        for (var index = 0; index < _localeOrder.length; index++) ...[
          if (index > 0) const _RowDivider(),
          _SelectableRow(
            label: _localeLabel(l10n, _localeOrder[index]),
            selected: selected == _localeOrder[index],
            enabled: true,
            onTap: () {
              unawaited(
                ref.read(shellLocaleSelectProvider)(_localeOrder[index]),
              );
            },
          ),
        ],
      ],
    );
  }
}

/// One seat in a single-choice group.
class _SelectableRow extends StatelessWidget {
  const _SelectableRow({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color ink = !enabled
        ? scheme.labelDimmed
        : selected
        ? scheme.labelPrimary
        : scheme.labelSecondary;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: !enabled
                    ? scheme.labelDimmed
                    : selected
                    ? scheme.stateBusinessPrimary
                    : scheme.labelTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: DshType.s14.style(color: ink)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// About: the build's version line.
class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return _SettingsCard(
      title: l10n.settingsSectionAbout,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  l10n.aboutVersionLabel,
                  style: DshType.s14.style(color: scheme.labelPrimary),
                ),
              ),
              Text(
                l10n.aboutVersionLine(kDshAppVersion, kDshBuildNumber),
                style: DshType.xxs12.style(color: scheme.labelTertiary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Maps the controller's encoded error to the user-facing string.
String _registryErrorText(AppLocalizations l10n, String raw) {
  final String code = raw.split(':').first;
  return switch (code) {
    'badBaseUrl' => l10n.backendErrorInvalidBaseUrl,
    'emptyLabel' => l10n.backendErrorEmptyLabel,
    'cannotRemoveLast' => l10n.cannotRemoveLastBackend,
    'removeActiveFirst' => l10n.removeActiveBackendFirst,
    'backendDisabled' => l10n.backendErrorDisabled,
    'writeFailed' => l10n.backendErrorWriteFailed,
    'readFailed' => l10n.backendErrorReadFailed,
    'invalidJson' => l10n.backendErrorInvalidJson,
    'malformedEntry' => l10n.backendErrorMalformedEntry,
    'emptyList' => l10n.backendErrorEmptyList,
    _ => l10n.backendErrorUnknown,
  };
}
