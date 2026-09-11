/// Defensive wire-JSON accessors mirroring the kotlinx-json extension
/// helpers used by the Kotlin adapter (`jsonPrimitive.contentOrNull` and
/// friends): primitives surface their string content, everything else is
/// null.
///
/// The `llm/*` provider-administration decoders live here because their
/// result values are bare JSON arrays, not objects: `RpcResult.fromJson`
/// parks a non-object result under the `value` key, so the array shape is a
/// property of the envelope rather than of a response object.
library;

import 'package:domain/model/llm_provider.dart';

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

/// Throws for a required field that is absent or carries the wrong type,
/// naming the field exactly as kotlinx-serialization's decode failure names
/// it ([dsh_wire_types.dart] holds the same contract for object results).
Never _missingRequired(JsonMap json, String key) => throw FormatException(
  'required field "$key" missing or mistyped in ${json.keys.toList()}',
);

String _requiredString(JsonMap json, String key) {
  final value = wireString(json, key);
  if (value == null) _missingRequired(json, key);
  return value;
}

/// One required string primitive; an absent or mistyped field throws naming
/// it. Public sibling of `_requiredString` for payload decoders that live
/// outside this file.
String wireRequiredString(JsonMap json, String key) =>
    _requiredString(json, key);

/// One required integer field; a fractional number, a non-numeric string or
/// an absent field throws naming it.
int wireRequiredLong(JsonMap json, String key) {
  if (!json.containsKey(key)) _missingRequired(json, key);
  final value = json[key];
  if (value is int) return value;
  if (value is num) {
    final truncated = value.truncateToDouble();
    if (value == truncated) return truncated.toInt();
  }
  if (value is String && int.tryParse(value) != null) {
    return int.parse(value);
  }
  _missingRequired(json, key);
}

/// One required boolean field; only a real bool or the strings `"true"` /
/// `"false"` are accepted.
bool wireRequiredBool(JsonMap json, String key) {
  final value = json[key];
  if (value is bool) return value;
  if (value is String && (value == 'true' || value == 'false')) {
    return value == 'true';
  }
  _missingRequired(json, key);
}

/// One required object field; an absent or non-object value throws naming
/// it.
JsonMap wireRequiredObject(JsonMap json, String key) {
  final value = asJsonObject(json[key]);
  if (value == null) _missingRequired(json, key);
  return value;
}

/// One required array field; an absent or non-array value throws naming it.
JsonList wireRequiredArray(JsonMap json, String key) {
  final value = asJsonArray(json[key]);
  if (value == null) _missingRequired(json, key);
  return value;
}

/// One required array-of-objects field; a non-object member throws naming
/// the field.
List<JsonMap> wireRequiredObjectArray(JsonMap json, String key) =>
    wireRequiredArray(
      json,
      key,
    ).map((Object? entry) => asJsonObject(entry)).whereType<JsonMap>().toList();

/// One required array-of-strings field; an absent field, a non-list, or a
/// non-string member all fail loud naming the field.
List<String> _requiredStringList(JsonMap json, String key) {
  final raw = json[key];
  if (raw is! List) _missingRequired(json, key);
  final List<String> values = <String>[];
  for (final Object? entry in raw) {
    if (entry is! String) _missingRequired(json, key);
    values.add(entry);
  }
  return values;
}

/// The bare JSON array a `llm/*` listing result carries.
///
/// `RpcResult.fromJson` parks a non-object result under `value`
/// (`packages/network/lib/rpc_envelope.dart`), so an absent array means the
/// endpoint answered an object where the contract says an array.
List<JsonMap> _requiredObjectArray(JsonMap value, String method) {
  final raw = value['value'];
  if (raw is! List) {
    throw FormatException(
      '$method "value" must be a JSON array, got: ${value.keys.toList()}',
    );
  }
  return raw
      .map(
        (Object? entry) => entry is Map ? entry.cast<String, Object?>() : null,
      )
      .whereType<JsonMap>()
      .toList();
}

// ---------------------------------------------------------------------------
// LLM provider administration (`llm/listProviders`,
// `llm/listConfigurableProviders`, `llm/discoverModels` —
// reference/deepseek-harness/packages/llm/llm/src/types.ts)
// ---------------------------------------------------------------------------

/// Wire form of `LlmProviderInfo`.
final class LlmProviderInfoWire {
  LlmProviderInfoWire.fromJson(JsonMap json)
    : id = _requiredString(json, 'id'),
      name = _requiredString(json, 'name');

  final String id;
  final String name;
}

/// Wire form of `LlmConfigurableProvider`.
final class LlmConfigurableProviderWire {
  LlmConfigurableProviderWire.fromJson(JsonMap json)
    : provider = _requiredString(json, 'provider'),
      displayName = _requiredString(json, 'displayName'),
      settingsNs = _requiredString(json, 'settingsNs'),
      settingsPath = _requiredStringList(json, 'settingsPath'),
      declared = json.containsKey('declared')
          ? wireBool(json, 'declared')
          : null,
      error = wireString(json, 'error');

  final String provider;
  final String displayName;
  final String settingsNs;
  final List<String> settingsPath;
  final bool? declared;
  final String? error;
}

/// Wire form of `LlmDiscoveredModel`; every field but `id` is optional.
final class LlmDiscoveredModelWire {
  LlmDiscoveredModelWire.fromJson(JsonMap json)
    : id = _requiredString(json, 'id'),
      name = wireString(json, 'name'),
      contextWindow = wireLongOrNull(json, 'contextWindow'),
      maxTokens = wireLongOrNull(json, 'maxTokens');

  final String id;
  final String? name;
  final int? contextWindow;
  final int? maxTokens;
}

/// Decodes the `llm/listProviders` result: every live provider route.
List<LlmProvider> decodeLlmProviderList(JsonMap value) =>
    _requiredObjectArray(value, DshRpcEndpoints.llmListProviders).map((
      JsonMap json,
    ) {
      final LlmProviderInfoWire wire = LlmProviderInfoWire.fromJson(json);
      return LlmProvider(id: wire.id, name: wire.name);
    }).toList();

/// Decodes the `llm/listConfigurableProviders` result: every declared
/// provider route, registered or dormant.
List<LlmConfigurableProvider> decodeLlmConfigurableProviderList(
  JsonMap value,
) => _requiredObjectArray(value, DshRpcEndpoints.llmListConfigurableProviders)
    .map((JsonMap json) {
      final LlmConfigurableProviderWire wire =
          LlmConfigurableProviderWire.fromJson(json);
      return LlmConfigurableProvider(
        provider: wire.provider,
        displayName: wire.displayName,
        settingsNs: wire.settingsNs,
        settingsPath: wire.settingsPath,
        declared: wire.declared,
        error: wire.error,
      );
    })
    .toList();

/// Decodes the `llm/discoverModels` result: the models the endpoint
/// advertised, deduplicated in endpoint order by the host.
List<LlmDiscoveredModel> decodeLlmDiscoveredModelList(JsonMap value) =>
    _requiredObjectArray(value, DshRpcEndpoints.llmDiscoverModels).map((
      JsonMap json,
    ) {
      final LlmDiscoveredModelWire wire = LlmDiscoveredModelWire.fromJson(json);
      return LlmDiscoveredModel(
        id: wire.id,
        name: wire.name,
        contextWindow: wire.contextWindow,
        maxTokens: wire.maxTokens,
      );
    }).toList();
