/// Permission-preset selection vocabulary.
///
/// Mirrors the `permissions` session projection value
/// (reference/deepseek-harness/packages/interaction/permission-presets/
/// src/types.ts): every switchable preset the host composes, plus the
/// effective current value. Key absence means the host composes no
/// permission service — surfaces hide their controls.
library;

/// One selectable permission preset (or the derived `custom` state).
final class PermissionPresetOption {
  const PermissionPresetOption({
    required this.value,
    required this.name,
    this.description,
  });

  /// Stable option value: the preset table key, or `custom`.
  final String value;

  /// The display label.
  final String name;

  /// One user-facing sentence on what the value means; null when the
  /// host did not configure one.
  final String? description;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PermissionPresetOption &&
          other.value == value &&
          other.name == name &&
          other.description == description);

  @override
  int get hashCode => Object.hash(value, name, description);
}

/// Whole `permissions` projection value: the switchable presets in host
/// table order (plus `custom` exactly while it is current) and the
/// effective current value.
final class PermissionSelect {
  const PermissionSelect({required this.options, required this.currentValue});

  final List<PermissionPresetOption> options;

  /// The effective current value: a preset table key, or `custom`.
  final String currentValue;

  /// The option row matching [currentValue], when the host listed one.
  PermissionPresetOption? get currentOption =>
      options.where((option) => option.value == currentValue).firstOrNull;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PermissionSelect &&
          other.currentValue == currentValue &&
          _listEquals(other.options, options));

  @override
  int get hashCode => Object.hash(Object.hashAll(options), currentValue);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The deployment's permission-preset catalog (`permissionPresets/catalog`).
///
/// Distinct from [PermissionSelect], which is one *session's* projection: the
/// catalog is the deployment-wide table — every preset the host composes
/// ([options]), the subset a new session may be defaulted to
/// ([defaultOptions] — a host may compose a preset that is switchable but not
/// acceptable as a default), and the effective [defaultPreset]. A settings
/// row offers exactly [defaultOptions] and writes [defaultPreset].
final class PermissionPresetCatalog {
  const PermissionPresetCatalog({
    required this.options,
    required this.defaultOptions,
    required this.defaultPreset,
  });

  /// Every preset the host composes, in its table order.
  final List<PermissionPresetOption> options;

  /// The presets a new session may default to, in the host's order. The
  /// effective [defaultPreset] is always one of these.
  final List<PermissionPresetOption> defaultOptions;

  /// The deployment's effective default preset key.
  final String defaultPreset;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PermissionPresetCatalog &&
          other.defaultPreset == defaultPreset &&
          _listEquals(other.options, options) &&
          _listEquals(other.defaultOptions, defaultOptions));

  @override
  int get hashCode => Object.hash(
    Object.hashAll(options),
    Object.hashAll(defaultOptions),
    defaultPreset,
  );
}
