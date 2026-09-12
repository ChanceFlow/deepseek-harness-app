/// About surface for Settings: the build's version, the project docs, and
/// the feedback channel.
///
/// Self-contained so the Settings list mounts it as one child; it reads no
/// controller and holds no host state — the version comes from the build-time
/// constants and both links open in the platform browser.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../theme/theme.dart';

/// The project repository the docs and issue tracker hang off. Builds that
/// override [kDshSourceRepo] (a fork, an internal mirror) get links to that
/// repository instead of the default one.
String get kAboutRepositoryUrl => 'https://github.com/$kDshSourceRepo';

/// `Settings` → About: version, documentation, and bug reports.
///
/// [showTitle] is false on the About page, whose app bar already names it.
class SettingsAboutSection extends StatelessWidget {
  const SettingsAboutSection({this.showTitle = true, super.key});

  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showTitle)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l10n.settingsSectionAbout,
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Material(
          color: scheme.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kShapeCard),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ListTile(
                leading: Icon(
                  Icons.info_outline,
                  color: scheme.onSurfaceVariant,
                ),
                title: Text(l10n.aboutVersionLabel),
                subtitle: Text(
                  l10n.aboutVersionLine(kDshAppVersion, kDshBuildNumber),
                ),
              ),
              Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
              ListTile(
                leading: Icon(
                  Icons.menu_book_outlined,
                  color: scheme.onSurfaceVariant,
                ),
                title: Text(l10n.aboutDocs),
                trailing: Icon(
                  Icons.open_in_new,
                  color: scheme.onSurfaceVariant,
                ),
                onTap: () => _open(context, Uri.parse(kAboutRepositoryUrl)),
              ),
              Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
              ListTile(
                leading: Icon(
                  Icons.bug_report_outlined,
                  color: scheme.onSurfaceVariant,
                ),
                title: Text(l10n.aboutFeedback),
                trailing: Icon(
                  Icons.open_in_new,
                  color: scheme.onSurfaceVariant,
                ),
                onTap: () =>
                    _open(context, Uri.parse('$kAboutRepositoryUrl/issues')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Hand [uri] to the platform browser, reporting the one outcome the user
  /// must see: nothing opened. A launcher failure and a `false` result are
  /// the same fact here, so both land on [AppLocalizations.aboutLinkFailed].
  Future<void> _open(BuildContext context, Uri uri) async {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // The platform channel refused the URL (no browser, malformed target);
      // the snackbar below is the only report this surface owes.
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.aboutLinkFailed)));
    }
  }
}
