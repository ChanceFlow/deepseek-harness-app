/// JSON container helpers shared inside the adapter.
///
/// The [JsonMap] type itself comes from the network package so the two
/// packages never disagree about the decoded-wire representation.
library;

import 'package:network/rpc_envelope.dart' show JsonMap;

export 'package:network/rpc_envelope.dart' show JsonMap;

/// A decoded JSON array.
typedef JsonList = List<Object?>;

/// Returns [value] as a [JsonMap], or null when it is not an object.
JsonMap? asJsonObject(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return null;
}

/// Returns [value] as a [JsonList], or null when it is not an array.
JsonList? asJsonArray(Object? value) {
  if (value is List<Object?>) return value;
  if (value is List) return value.cast<Object?>();
  return null;
}
