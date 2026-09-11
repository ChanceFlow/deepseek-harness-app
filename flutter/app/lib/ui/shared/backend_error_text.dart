/// User-facing copy for a host-configuration failure surfaced as an async
/// error on the workspace surface.
///
/// [describeBackendError] already maps the store's own failure classes; a
/// failure it cannot classify (a plugin or filesystem error reaching the
/// registry future) would otherwise render as a raw `toString()`. This
/// wrapper keeps the specific copy for a classified error and falls back
/// to a localized sentence for everything else.
library;

import 'package:app/l10n/app_localizations.dart';

import '../../backends/backend_store.dart';
import '../../backends/describe_backend_error.dart';

/// Localized sentence describing [error] for the workspace failure view.
String describeBackendFailure(AppLocalizations l10n, Object error) {
  if (error is BackendStoreException || error is BackendErrorCode) {
    return describeBackendError(l10n, error);
  }
  if (error is String) {
    final mapped = describeBackendError(l10n, error);
    if (mapped.isNotEmpty && mapped != error.trim()) return mapped;
  }
  return l10n.backendErrorLoadFailed;
}
