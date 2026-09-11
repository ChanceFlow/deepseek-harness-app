/// Chat failure copy — the machine error a controller holds, turned into the
/// sentence a reader can act on.
///
/// [describeChatError] keeps the one failure class the controller names
/// (`SESSION_ALREADY_OWNED`) on its specific copy, and gives every other
/// failure the generic localized headline with the raw host detail as the
/// secondary line instead of the whole message. The strip itself is
/// [ErrorBanner], shared with the surfaces that state the same kind of fact.
library;

import 'package:app/l10n/app_localizations.dart';

/// Localized headline plus the optional raw host detail.
typedef ChatErrorCopy = ({String message, String? detail});

/// Maps a controller `errorMessage` to user-facing copy.
ChatErrorCopy describeChatError(AppLocalizations l10n, String error) {
  if (error == 'SESSION_ALREADY_OWNED' ||
      error.contains('session-persistence/already-owned') ||
      error.contains('SessionAlreadyOwned')) {
    return (message: l10n.sessionAlreadyOwnedError, detail: null);
  }
  final detail = error.trim();
  return (
    message: l10n.chatActionFailed,
    detail: detail.isEmpty ? null : detail,
  );
}
