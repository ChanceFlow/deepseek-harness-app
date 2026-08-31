/// Pure helper mapping backend registry and store errors to user-facing
/// localized strings.
library;

import '../l10n/app_localizations.dart';
import 'backend_store.dart';

/// Describes a backend error for user-facing surfaces using [AppLocalizations].
///
/// Accepts [BackendStoreException], [BackendErrorCode], or the machine-encoded
/// error strings published on `BackendRegistryState.errorMessage`.
String describeBackendError(AppLocalizations l10n, Object? error) {
  if (error == null) return '';

  if (error is BackendStoreException) {
    return _describeCode(l10n, error.code, detail: error.detail);
  }

  if (error is BackendErrorCode) {
    return _describeCode(l10n, error);
  }

  if (error is String) {
    final trimmed = error.trim();
    if (trimmed.isEmpty) return '';

    final colonIndex = trimmed.indexOf(':');
    final codeName = colonIndex >= 0
        ? trimmed.substring(0, colonIndex)
        : trimmed;
    final detail = colonIndex >= 0 ? trimmed.substring(colonIndex + 1) : null;

    for (final code in BackendErrorCode.values) {
      if (code.name == codeName) {
        return _describeCode(l10n, code, detail: detail);
      }
    }

    return trimmed;
  }

  return error.toString();
}

String _describeCode(
  AppLocalizations l10n,
  BackendErrorCode code, {
  String? detail,
}) {
  return switch (code) {
    BackendErrorCode.invalidJson => l10n.backendErrorInvalidJson,
    BackendErrorCode.malformedEntry => l10n.backendErrorMalformedEntry,
    BackendErrorCode.badBaseUrl =>
      detail != null && detail.isNotEmpty
          ? l10n.backendErrorBadBaseUrl(detail)
          : l10n.backendErrorInvalidBaseUrl,
    BackendErrorCode.emptyList => l10n.backendErrorEmptyList,
    BackendErrorCode.readFailed => l10n.backendErrorReadFailed,
    BackendErrorCode.writeFailed => l10n.backendErrorWriteFailed,
    BackendErrorCode.emptyLabel => l10n.backendErrorEmptyLabel,
    BackendErrorCode.cannotRemoveLast => l10n.cannotRemoveLastBackend,
    BackendErrorCode.removeActiveFirst => l10n.removeActiveBackendFirst,
    BackendErrorCode.unknownBackend =>
      detail != null && detail.isNotEmpty
          ? l10n.backendErrorUnknownBackend(detail)
          : l10n.backendErrorUnknown,
    BackendErrorCode.backendDisabled => l10n.backendErrorDisabled,
    BackendErrorCode.duplicateId =>
      detail != null && detail.isNotEmpty
          ? l10n.backendErrorDuplicateId(detail)
          : l10n.backendErrorUnknown,
  };
}
