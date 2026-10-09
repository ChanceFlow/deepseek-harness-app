/// `Settings` → Plugins → Web search: the DeepSeek search provider's key, its
/// endpoint, and its per-request search budget.
///
/// Port of the reference's web-search settings card (`ui-settings-web-search`):
/// the page binds the provider's `web-search-deepseek` namespace while the Host
/// serves it (`src/client/index.ts:48-59`, `web-search-card-controller.ts:25`)
/// and edits three rows (`WebSearchCard.tsx:31-69`):
///
/// - **API key** (`apiKey`) — the one control that does not live in the
///   section: its literal never rides a response, so the page learns only
///   whether one is configured and writes it through the credentials domain
///   under the reference `apiKeyEnv` names, `DEEPSEEK_API_KEY` when it names
///   none (`web-search-card-controller.ts:27-28`, `:186-190`). A blank draft
///   keeps the stored key, and the control is disabled only when the credentials
///   domain cannot be written from here (`WebSearchCard.tsx:35-39`).
/// - **Endpoint** (`baseURL`) — text; blank inherits the provider default.
/// - **Max searches per request** (`maxUses`) — a number
///   (`settingsNumberField('maxUses')`, `web-search-card-controller.ts:93`).
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import 'host_namespace_form.dart';
import 'settings_chrome.dart';

/// Namespace of the DeepSeek search provider
/// (`web-search-card-controller.ts:25`).
const String kWebSearchNamespace = 'web-search-deepseek';

/// Credential reference the provider resolves when the section names none
/// (`web-search-card-controller.ts:28`).
const String kWebSearchDefaultApiKeyRef = 'DEEPSEEK_API_KEY';

/// One controller per backend: the describe, the credential status and the
/// CAS-guarded writes share the repository the rest of the settings surface
/// uses.
final webSearchSettingsControllerProvider = Provider.family
    .autoDispose<HostNamespaceController, String>((ref, backendId) {
      final controller = HostNamespaceController(
        ref.watch(chatRepositoryProvider(backendId)),
        const <String>[kWebSearchNamespace],
        credentialRefField: 'apiKeyEnv',
        defaultCredentialRef: kWebSearchDefaultApiKeyRef,
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

/// The Settings → Plugins index row: it opens the web-search page while the
/// Host serves the provider's namespace.
class SettingsWebSearchEntryRow extends ConsumerWidget {
  const SettingsWebSearchEntryRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final String backendId = ref.watch(activeBackendIdProvider).value ?? '';
    if (backendId.isEmpty) {
      return SettingsNavRow(
        title: l10n.settingsNavWebSearch,
        leading: const Icon(Icons.travel_explore_outlined),
        value: l10n.settingsValueUnavailable,
        enabled: false,
        onTap: () {},
      );
    }
    final HostNamespaceController controller = ref.watch(
      webSearchSettingsControllerProvider(backendId),
    );
    return HostNamespaceEntryRow(
      controller: controller,
      title: l10n.settingsNavWebSearch,
      leading: const Icon(Icons.travel_explore_outlined),
      onOpen: () => unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext _) =>
                SettingsWebSearchPage(backendId: backendId),
          ),
        ),
      ),
    );
  }
}

/// The DeepSeek web-search provider's settings page.
class SettingsWebSearchPage extends ConsumerWidget {
  const SettingsWebSearchPage({required this.backendId, super.key});

  final String backendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return SettingsPageScaffold(
      title: l10n.settingsNavWebSearch,
      children: <Widget>[
        SettingsSectionHeading(
          title: l10n.settingsNavWebSearch,
          intro: l10n.settingsWebSearchDescription,
          showTitle: false,
        ),
        HostNamespaceFormCard(
          controller: ref.watch(webSearchSettingsControllerProvider(backendId)),
          secret: HostNamespaceSecret(
            label: l10n.settingsWebSearchApiKeyLabel,
            hint: l10n.settingsWebSearchApiKeyHint,
            configuredLabel: l10n.settingsWebSearchApiKeySet,
            unsetLabel: l10n.settingsWebSearchApiKeyUnset,
          ),
          fields: <HostNamespaceField>[
            HostNamespaceField(
              key: 'baseURL',
              label: l10n.settingsWebSearchBaseUrlLabel,
              hint: l10n.settingsWebSearchBaseUrlHint,
            ),
            HostNamespaceField(
              key: 'maxUses',
              label: l10n.settingsWebSearchMaxUsesLabel,
              hint: l10n.settingsWebSearchMaxUsesHint,
              numeric: true,
            ),
          ],
        ),
      ],
    );
  }
}
