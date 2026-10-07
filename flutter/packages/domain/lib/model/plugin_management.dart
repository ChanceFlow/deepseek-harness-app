/// Plugin-management vocabulary: the host's bundle/plugin roster, the
/// installation lifecycle, and the version-exemption ledger.
///
/// Wire shapes come from
/// `reference/deepseek-harness/packages/boot/plugin-manager/src/types.ts`
/// (the `pluginManager` Remote service) and
/// `packages/host/plugin-inventory/src/types.ts` (the read-only snapshot this
/// client already consumes). Every package operation runs on the host — pnpm,
/// git, and the registry probes — so these types describe what the phone may
/// ask for, never what it performs.
library;

/// Host-supplied display text in one or more locales
/// (`PluginLocalizedMeta`): a manifest may ship a plain string or an
/// `{en, zh, …}` record. [resolve] reads the caller's locale, falls back to
/// English, and then to whatever the host did send.
final class PluginLocalizedText {
  const PluginLocalizedText(this.values);

  final Map<String, String> values;

  /// The text for [locale], or an empty string when the host sent none.
  String resolve(String locale) {
    final exact = values[locale];
    if (exact != null && exact.isNotEmpty) return exact;
    final language = locale.split(RegExp('[-_]')).first;
    for (final entry in values.entries) {
      if (entry.key == language || entry.key.startsWith('$language-')) {
        if (entry.value.isNotEmpty) return entry.value;
      }
    }
    final english = values['en'];
    if (english != null && english.isNotEmpty) return english;
    for (final value in values.values) {
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PluginLocalizedText && _mapEquals(other.values, values));

  @override
  int get hashCode => Object.hashAll(values.entries.map((e) => e.key));

  @override
  String toString() => 'PluginLocalizedText(${values.length} locales)';
}

/// Why a roster row cannot be changed through the profile patch
/// (`ReadOnlyReason`).
enum PluginReadOnlyReason { managementRequired, unaddressable }

/// How an installation attempt failed (`PluginInstallFailureKind`).
enum PluginInstallFailureKind {
  pnpmMissing,
  timeout,
  notFound,
  noMatchingVersion,
  network,
  diskFull,
  permission,
  buildBlocked,
  integrity,
  unknown,
}

/// What a change did (`ChangeResult.application`).
enum PluginChangeApplication {
  applied,
  restartRequired,
  overridden,
  failed,
  cancelled,
}

/// Which stage a change belongs to (`ChangeResult.stage`).
enum PluginChangeStage { install, enable, remove }

/// The kind of package a spec names (`InstallSpecKind`).
enum PluginSpecKind { registry, path, git, tarball }

/// Why an inspection refused a spec (`PluginInspectProblem`).
enum PluginInspectProblem {
  invalidSpec,
  alreadyInstalled,
  notFound,
  notAPackage,
  notABundle,
  network,
  unknown,
}

/// Where an installation is (`PluginInstallProgress.phase`).
enum PluginInstallPhase { installing, cancelling, applying }

/// What a completed manager operation touched (`PluginChange.reason`).
enum PluginChangeReason { plugin, bundle, install, remove }

/// The registry's answer to a cancellation (`PluginInstallCancellation`).
enum PluginInstallCancellation { cancelled, tooLate, notRunning }

/// The manager's own refusal codes (`ManagementError.code`).
enum PluginManagementErrorCode {
  managementRequired,
  unaddressable,
  unknownPlugin,
  invalidSpec,
  ambiguousInstall,
  notBundle,
  notRemovable,
  stopProfile,
  bundleInUse,
  staleApproval,
  incompatibleVersion,
  operationError,
}

/// One plugin the running DSH version rejects (`IncompatiblePlugin`).
final class IncompatiblePlugin {
  const IncompatiblePlugin({
    required this.name,
    required this.version,
    required this.runtimeVersion,
    this.peers = const <String, String>{},
  });

  final String name;
  final String version;
  final String runtimeVersion;

  /// Only the peer ranges the running version does not satisfy.
  final Map<String, String> peers;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IncompatiblePlugin &&
          other.name == name &&
          other.version == version &&
          other.runtimeVersion == runtimeVersion &&
          _mapEquals(other.peers, peers));

  @override
  int get hashCode =>
      Object.hash(name, version, runtimeVersion, Object.hashAll(peers.entries));
}

/// A refusal a manager operation reports inside its result
/// (`ManagementError`).
///
/// Expected refusals are values, not transport errors: the host folds them
/// into the `ChangeResult` it returns, so a caller reads [PluginChange.error]
/// rather than catching.
final class PluginManagementError {
  const PluginManagementError({
    required this.code,
    this.diagnostic,
    this.incompatible = const <IncompatiblePlugin>[],
  });

  final PluginManagementErrorCode code;
  final String? diagnostic;

  /// Present with [PluginManagementErrorCode.incompatibleVersion]: the
  /// packages the running DSH version rejects.
  final List<IncompatiblePlugin> incompatible;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PluginManagementError &&
          other.code == code &&
          other.diagnostic == diagnostic &&
          _listEquals(other.incompatible, incompatible));

  @override
  int get hashCode => Object.hash(code, diagnostic, incompatible.length);
}

/// The registries an installation will ask, in order (`PluginRegistries`).
///
/// A null [registry] means the registry pnpm's own configuration names; a null
/// [resolved] means no registry is known to be usable.
final class PluginRegistries {
  const PluginRegistries({
    this.registry,
    this.fallbackRegistries = const <String>[],
    this.resolved,
  });

  final String? registry;
  final List<String> fallbackRegistries;
  final String? resolved;

  /// Every registry a picker may offer, deduplicated in ask order.
  List<String> get offered {
    final seen = <String>{};
    final out = <String>[];
    for (final candidate in <String?>[registry, ...fallbackRegistries]) {
      if (candidate == null || candidate.isEmpty) continue;
      if (seen.add(candidate)) out.add(candidate);
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PluginRegistries &&
          other.registry == registry &&
          _listEquals(other.fallbackRegistries, fallbackRegistries) &&
          other.resolved == resolved);

  @override
  int get hashCode =>
      Object.hash(registry, Object.hashAll(fallbackRegistries), resolved);
}

/// One row inside a bundle (`BundleRowInfo`) — the individually switchable
/// plugin entries a bundle composes.
final class PluginBundleRow {
  const PluginBundleRow({
    required this.rowId,
    required this.moduleName,
    this.entryId,
    this.title,
    this.description,
    this.icon,
    this.metaError,
  });

  final String rowId;
  final String moduleName;

  /// Absent when the row is not (yet) a loaded entry, which is also the case
  /// where its switch is unlocked.
  final String? entryId;

  final PluginLocalizedText? title;
  final PluginLocalizedText? description;
  final String? icon;
  final String? metaError;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PluginBundleRow &&
          other.rowId == rowId &&
          other.moduleName == moduleName &&
          other.entryId == entryId &&
          other.title == title &&
          other.description == description &&
          other.icon == icon &&
          other.metaError == metaError);

  @override
  int get hashCode => Object.hash(
    rowId,
    moduleName,
    entryId,
    title,
    description,
    icon,
    metaError,
  );
}

/// One installed or optional bundle (`BundleInfo`).
final class PluginBundle {
  const PluginBundle({
    required this.name,
    required this.enabled,
    required this.installed,
    required this.optional,
    required this.removable,
    this.version,
    this.title,
    this.description,
    this.metaDescription,
    this.icon,
    this.metaError,
    this.readOnlyReason,
    this.error,
    this.rows = const <PluginBundleRow>[],
    this.overrides = const <String>[],
  });

  final String name;
  final String? version;
  final PluginLocalizedText? title;

  /// The bundle's plain one-liner (`BundleInfo.description`).
  final String? description;

  /// The manifest's localized one-liner, when it shipped one.
  final PluginLocalizedText? metaDescription;

  final String? icon;
  final String? metaError;
  final bool enabled;
  final bool installed;
  final bool optional;
  final bool removable;
  final PluginReadOnlyReason? readOnlyReason;
  final PluginManagementError? error;
  final List<PluginBundleRow> rows;

  /// The package names this bundle overrides.
  final List<String> overrides;

  /// An experimental bundle, tagged in the roster the way the reference does.
  bool get isExperimental => name.startsWith('@deepseek-ai/dsh-experimental-');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PluginBundle &&
          other.name == name &&
          other.version == version &&
          other.title == title &&
          other.description == description &&
          other.metaDescription == metaDescription &&
          other.icon == icon &&
          other.metaError == metaError &&
          other.enabled == enabled &&
          other.installed == installed &&
          other.optional == optional &&
          other.removable == removable &&
          other.readOnlyReason == readOnlyReason &&
          other.error == error &&
          _listEquals(other.rows, rows) &&
          _listEquals(other.overrides, overrides));

  @override
  int get hashCode => Object.hash(
    name,
    version,
    title,
    description,
    metaDescription,
    icon,
    metaError,
    enabled,
    installed,
    optional,
    removable,
    readOnlyReason,
    error,
    Object.hashAll(rows),
    Object.hashAll(overrides),
  );
}

/// One loaded plugin entry (`PluginInfo`, an inventory entry plus its patch
/// target).
final class PluginInfo {
  const PluginInfo({
    required this.entryId,
    required this.moduleName,
    required this.enabled,
    this.patchId,
    this.readOnlyReason,
    this.title,
    this.description,
    this.icon,
    this.metaError,
  });

  final String entryId;
  final String moduleName;
  final bool enabled;

  /// Present only when the row is addressable through the profile patch.
  final String? patchId;
  final PluginReadOnlyReason? readOnlyReason;
  final PluginLocalizedText? title;
  final PluginLocalizedText? description;
  final String? icon;
  final String? metaError;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PluginInfo &&
          other.entryId == entryId &&
          other.moduleName == moduleName &&
          other.enabled == enabled &&
          other.patchId == patchId &&
          other.readOnlyReason == readOnlyReason &&
          other.title == title &&
          other.description == description &&
          other.icon == icon &&
          other.metaError == metaError);

  @override
  int get hashCode => Object.hash(
    entryId,
    moduleName,
    enabled,
    patchId,
    readOnlyReason,
    title,
    description,
    icon,
    metaError,
  );
}

/// The package run behind a change (`PackageResult`).
final class PluginPackageResult {
  const PluginPackageResult({
    required this.exitCode,
    required this.output,
    required this.truncated,
    required this.logPath,
    this.kind,
    this.timedOut = false,
    this.incompatible = const <IncompatiblePlugin>[],
  });

  final int exitCode;
  final String output;
  final bool truncated;
  final String logPath;
  final PluginInstallFailureKind? kind;
  final bool timedOut;
  final List<IncompatiblePlugin> incompatible;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PluginPackageResult &&
          other.exitCode == exitCode &&
          other.output == output &&
          other.truncated == truncated &&
          other.logPath == logPath &&
          other.kind == kind &&
          other.timedOut == timedOut &&
          _listEquals(other.incompatible, incompatible));

  @override
  int get hashCode => Object.hash(
    exitCode,
    output,
    truncated,
    logPath,
    kind,
    timedOut,
    incompatible.length,
  );
}

/// What one manager operation did (`ChangeResult`).
final class PluginChangeResult {
  const PluginChangeResult({
    required this.changed,
    required this.application,
    required this.stage,
    required this.target,
    this.enabled,
    this.error,
    this.warnings = const <String>[],
    this.packageResult,
    this.bundle,
    this.pendingBuilds = const <String>[],
    this.approvedBuilds = const <String>[],
    this.registries = const <String>[],
    this.failedAt,
  });

  final bool changed;
  final PluginChangeApplication application;
  final PluginChangeStage stage;

  /// The package or bundle the change targeted.
  final String target;

  final bool? enabled;
  final PluginManagementError? error;
  final List<String> warnings;
  final PluginPackageResult? packageResult;

  /// The bundle a successful install produced.
  final String? bundle;

  /// Build scripts the host refused to run; retrying with them in
  /// `approvedBuilds` is the human's explicit acceptance.
  final List<String> pendingBuilds;
  final List<String> approvedBuilds;
  final List<String> registries;

  /// `registry` or `spec-host` when the failure came from where the spec was
  /// fetched.
  final String? failedAt;

  /// True when the outcome needs a restart before it is live.
  bool get needsRestart =>
      application == PluginChangeApplication.restartRequired;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PluginChangeResult &&
          other.changed == changed &&
          other.application == application &&
          other.stage == stage &&
          other.target == target &&
          other.enabled == enabled &&
          other.error == error &&
          _listEquals(other.warnings, warnings) &&
          other.packageResult == packageResult &&
          other.bundle == bundle &&
          _listEquals(other.pendingBuilds, pendingBuilds) &&
          _listEquals(other.approvedBuilds, approvedBuilds) &&
          _listEquals(other.registries, registries) &&
          other.failedAt == failedAt);

  @override
  int get hashCode => Object.hashAll(<Object?>[
    changed,
    application,
    stage,
    target,
    enabled,
    error,
    Object.hashAll(warnings),
    packageResult,
    bundle,
    Object.hashAll(pendingBuilds),
    Object.hashAll(approvedBuilds),
    Object.hashAll(registries),
    failedAt,
  ]);
}

/// The host's answer to `pluginManager/inspect`.
sealed class PluginSpecInspection {
  const PluginSpecInspection();
}

/// The spec names a package the host can attempt.
final class PluginSpecAccepted extends PluginSpecInspection {
  const PluginSpecAccepted({
    required this.kind,
    this.name,
    this.version,
    this.description,
    this.bundle,
    this.registry,
    this.host,
  });

  final PluginSpecKind kind;
  final String? name;
  final String? version;
  final String? description;

  /// Null when the spec's bundle-ness is not yet knowable.
  final bool? bundle;
  final String? registry;
  final String? host;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PluginSpecAccepted &&
          other.kind == kind &&
          other.name == name &&
          other.version == version &&
          other.description == description &&
          other.bundle == bundle &&
          other.registry == registry &&
          other.host == host);

  @override
  int get hashCode =>
      Object.hash(kind, name, version, description, bundle, registry, host);
}

/// The host refused the spec before any package operation.
final class PluginSpecRefused extends PluginSpecInspection {
  const PluginSpecRefused({
    required this.problem,
    required this.reason,
    this.registries = const <String>[],
  });

  final PluginInspectProblem problem;
  final String reason;

  /// Every registry the host asked, when the refusal was a network one.
  final List<String> registries;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PluginSpecRefused &&
          other.problem == problem &&
          other.reason == reason &&
          _listEquals(other.registries, registries));

  @override
  int get hashCode => Object.hash(problem, reason, Object.hashAll(registries));
}

/// What one installation attempt asked (`InstallBundleOptions`).
final class PluginInstallOptions {
  const PluginInstallOptions({
    this.enabled,
    this.requestId,
    this.approvedBuilds = const <String>[],
    this.registry,
  });

  final bool? enabled;

  /// The client-minted id that makes the host emit progress and log events
  /// for this attempt.
  final String? requestId;

  final List<String> approvedBuilds;
  final String? registry;
}

/// One installation's position (`PluginInstallProgress`).
final class PluginInstallProgress {
  const PluginInstallProgress({
    required this.requestId,
    required this.phase,
    this.registry,
    this.attemptIndex,
    this.attemptTotal,
  });

  final String requestId;
  final PluginInstallPhase phase;

  /// Present while [PluginInstallPhase.installing]: the registry this attempt
  /// asks, and its position in the plan.
  final String? registry;
  final int? attemptIndex;
  final int? attemptTotal;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PluginInstallProgress &&
          other.requestId == requestId &&
          other.phase == phase &&
          other.registry == registry &&
          other.attemptIndex == attemptIndex &&
          other.attemptTotal == attemptTotal);

  @override
  int get hashCode =>
      Object.hash(requestId, phase, registry, attemptIndex, attemptTotal);
}

/// One chunk of a package run's output (`PluginInstallLogChunk`).
final class PluginInstallLogChunk {
  const PluginInstallLogChunk({
    required this.jobId,
    required this.argv,
    required this.cwd,
    required this.text,
    this.requestId,
    this.isStderr = false,
    this.exitCode,
  });

  final String? requestId;
  final String jobId;
  final List<String> argv;
  final String cwd;
  final bool isStderr;
  final String text;
  final int? exitCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PluginInstallLogChunk &&
          other.requestId == requestId &&
          other.jobId == jobId &&
          _listEquals(other.argv, argv) &&
          other.cwd == cwd &&
          other.isStderr == isStderr &&
          other.text == text &&
          other.exitCode == exitCode);

  @override
  int get hashCode => Object.hashAll(<Object?>[
    requestId,
    jobId,
    Object.hashAll(argv),
    cwd,
    isStderr,
    text,
    exitCode,
  ]);
}

/// The saved plugin-version exemptions (`listVersionExemptions`).
///
/// Keys are exact `name@version` strings; values are the runtime versions each
/// may run on. [warnings] reports record or file problems the reader rejected
/// instead of failing.
final class PluginVersionExemptions {
  const PluginVersionExemptions({
    this.exemptions = const <String, List<String>>{},
    this.warnings = const <String>[],
  });

  final Map<String, List<String>> exemptions;
  final List<String> warnings;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PluginVersionExemptions &&
          _mapListEquals(other.exemptions, exemptions) &&
          _listEquals(other.warnings, warnings));

  @override
  int get hashCode => Object.hash(
    Object.hashAll(
      exemptions.entries.map(
        (entry) => Object.hash(entry.key, Object.hashAll(entry.value)),
      ),
    ),
    Object.hashAll(warnings),
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

bool _mapListEquals(Map<String, List<String>> a, Map<String, List<String>> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null || !_listEquals(entry.value, other)) return false;
  }
  return true;
}
