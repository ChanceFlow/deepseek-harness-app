/// `Settings` → Plugins → Shell: the command timeout and the per-stream output
/// cap of the composed shell executor.
///
/// Port of the reference's shell settings card (`ui-settings-shell`): the page
/// binds the executor entry the base bundle composed — `bash-sandbox` off
/// Windows, `pwsh-sandbox` on it (`src/client/shell-card-controller.ts:10-12`)
/// — while the Host serves it (`src/client/index.ts:50-52`), and edits its two
/// rows (`ShellCard.tsx:27-52`): **Command timeout (ms)** (`timeoutMs`) and
/// **Output cap per stream (bytes)** (`maxOutputBytes`), both numbers
/// (`settingsNumberField('timeoutMs')` / `('maxOutputBytes')`,
/// `shell-card-controller.ts:45`).
///
/// The rows live in the Host's user-settings document for that namespace; an
/// empty field saves as a reset, and the page is absent while the Host serves
/// neither executor.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import 'host_namespace_form.dart';
import 'settings_chrome.dart';

/// Profile entry id of the POSIX shell executor; the base bundle composes it
/// off Windows (`shell-card-controller.ts:10`).
const String kShellBashNamespace = 'bash-sandbox';

/// Profile entry id of the PowerShell executor; the base bundle composes it on
/// Windows (`shell-card-controller.ts:12`).
const String kShellPwshNamespace = 'pwsh-sandbox';

/// One controller per backend: the describe and the CAS-guarded write share the
/// repository the rest of the settings surface uses.
final shellSettingsControllerProvider = Provider.family
    .autoDispose<HostNamespaceController, String>((ref, backendId) {
      final controller = HostNamespaceController(
        ref.watch(chatRepositoryProvider(backendId)),
        const <String>[kShellBashNamespace, kShellPwshNamespace],
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

/// The Settings → Plugins index row: it opens the shell page while the Host
/// serves one of the executor namespaces, and names what is missing when it
/// does not.
class SettingsShellEntryRow extends ConsumerWidget {
  const SettingsShellEntryRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final String backendId = ref.watch(activeBackendIdProvider).value ?? '';
    if (backendId.isEmpty) {
      return SettingsNavRow(
        title: l10n.settingsNavShell,
        leading: const Icon(Icons.terminal_outlined),
        value: l10n.settingsValueUnavailable,
        enabled: false,
        onTap: () {},
      );
    }
    final HostNamespaceController controller = ref.watch(
      shellSettingsControllerProvider(backendId),
    );
    return HostNamespaceEntryRow(
      controller: controller,
      title: l10n.settingsNavShell,
      leading: const Icon(Icons.terminal_outlined),
      onOpen: () => unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext _) =>
                SettingsShellPage(backendId: backendId),
          ),
        ),
      ),
    );
  }
}

/// The shell executor's settings page.
class SettingsShellPage extends ConsumerWidget {
  const SettingsShellPage({required this.backendId, super.key});

  final String backendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return SettingsPageScaffold(
      title: l10n.settingsNavShell,
      children: <Widget>[
        SettingsSectionHeading(
          title: l10n.settingsNavShell,
          intro: l10n.settingsShellDescription,
          showTitle: false,
        ),
        HostNamespaceFormCard(
          controller: ref.watch(shellSettingsControllerProvider(backendId)),
          fields: <HostNamespaceField>[
            HostNamespaceField(
              key: 'timeoutMs',
              label: l10n.settingsShellTimeoutMsLabel,
              hint: l10n.settingsShellTimeoutMsHint,
              numeric: true,
            ),
            HostNamespaceField(
              key: 'maxOutputBytes',
              label: l10n.settingsShellMaxOutputBytesLabel,
              hint: l10n.settingsShellMaxOutputBytesHint,
              numeric: true,
            ),
          ],
        ),
      ],
    );
  }
}
