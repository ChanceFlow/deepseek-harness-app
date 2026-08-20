/// Defensive wire-JSON accessors mirroring the kotlinx-json extension
/// helpers used by the Kotlin adapter (`jsonPrimitive.contentOrNull` and
/// friends): primitives surface their string content, everything else is
/// null.
library;

import 'rpc_map.dart';

/// Reads `type` as a string primitive.
String? wireType(JsonMap obj) => wireString(obj, 'type');

/// Reads one string primitive; numbers/bools yield their string content
/// like kotlinx `contentOrNull`, objects/arrays/null yield null.
String? wireString(JsonMap obj, String key) {
  final value = obj[key];
  if (value == null) return null;
  if (value is String) return value;
  if (value is num) return value.toString();
  if (value is bool) return value.toString();
  return null;
}

/// Reads one long-ish primitive, defaulting to 0 like the Kotlin
/// `toLongOrNull() ?: 0L` idiom. Fractional numbers fail to parse.
int wireLong(JsonMap obj, String key) {
  final value = obj[key];
  if (value is int) return value;
  if (value is num) {
    final truncated = value.truncateToDouble();
    return value == truncated ? truncated.toInt() : 0;
  }
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

/// Strict boolean primitive ("true"/"false" only), defaulting to false.
bool wireBool(JsonMap obj, String key) {
  final value = obj[key];
  if (value is bool) return value;
  if (value is String) {
    if (value == 'true') return true;
    if (value == 'false') return false;
  }
  return false;
}

/// Reads one nullable long primitive (e.g. `finishedAt`), null on absence
/// or unparseable content.
int? wireLongOrNull(JsonMap obj, String key) {
  if (!obj.containsKey(key)) return null;
  final value = obj[key];
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) {
    final truncated = value.truncateToDouble();
    return value == truncated ? truncated.toInt() : null;
  }
  if (value is String) return int.tryParse(value);
  return null;
}
