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
      other is PermissionPresetOption &&
      other.value == value &&
      other.name == name &&
      other.description == description;

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
      other is PermissionSelect &&
      other.currentValue == currentValue &&
      _listEquals(other.options, options);

  @override
  int get hashCode => Object.hash(Object.hashAll(options), currentValue);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
