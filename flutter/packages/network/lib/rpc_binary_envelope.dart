/// Decodes the dsh binary-attachment RPC carrier.
///
/// A Typert Remote result carrying a `Uint8Array` field is not pure JSON. The
/// Gateway's result encoder hands the codec a `writeBytes` hook that records
/// each byte view at its result-relative path and returns the `null`
/// placeholder that takes its place in the JSON body
/// (`reference/deepseek-harness/packages/api/gateway/src/index.ts:991-1001`;
/// the hook's own contract is
/// `packages/typert/protocol/src/types.ts:283-288` — `encode(value, writeBytes)`
/// "project typed binary fields into RPC result attachments"). The generated
/// result encoder roots that path at the result value itself
/// (`packages/typert/generator/src/emitter.ts:1059`
/// `encode: (value, writeBytes) => …(value, writeBytes, [], …)`) and writes the
/// placeholder for a `Uint8Array` leaf
/// (`packages/typert/generator/src/emitter.ts:575-576`
/// `return value instanceof Uint8Array ? writeBytes(value, path) : value`).
///
/// The Connection carrier then frames the reply as `multipart/form-data`
/// (`packages/client/connection/src/rpc-host.ts:300-311`):
///
/// * a text field named `metadata` holds the JSON envelope
///   `{type, rpcId, result, attachments}`, with each byte field's former
///   position left as `null`;
/// * one binary field per attachment, named by that attachment's `part`
///   (`bytes-<index>`);
/// * `attachments[i]` is `{path, codec: 'bytes', part}`, `path` relative to
///   `result.value`.
///
/// The reference client accepts that carrier and splices each byte view over
/// its `null` placeholder before any endpoint logic runs
/// (`packages/client/connection/src/client/rpc.ts:61-64` selects the multipart
/// branch; `:83-139` validates the fields, the `bytes` codec, the path, and
/// the `null` placeholder, then writes a `Uint8Array` back in).
/// [decodeRpcAttachmentResponse] performs the same splice, so a
/// `DshRpcClient.call` caller sees the reassembled result exactly as a JSON
/// response would deliver it: the binary carrier never reaches the adapter as
/// a second result shape.
///
/// Every departure from that framing — no boundary, a truncated part, a
/// declared part the body does not carry, an undeclared field, a non-`bytes`
/// codec, a path that leaves the value, a placeholder that is not `null` —
/// throws a [FormatException] naming what failed, never a partial byte view.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'rpc_envelope.dart';

/// The media type a dsh reply uses when its result carries binary fields.
const String kRpcAttachmentMediaType = 'multipart/form-data';

/// The base media type of [contentType] with parameters and case stripped.
///
/// Returns null when [contentType] is null or carries no type.
String? rpcBaseMediaType(String? contentType) {
  if (contentType == null) return null;
  final semicolon = contentType.indexOf(';');
  final base =
      (semicolon == -1 ? contentType : contentType.substring(0, semicolon))
          .trim();
  return base.isEmpty ? null : base.toLowerCase();
}

/// Whether [contentType] selects the binary-attachment carrier.
bool isRpcAttachmentResponse(String? contentType) =>
    rpcBaseMediaType(contentType) == kRpcAttachmentMediaType;

/// Decodes one `multipart/form-data` RPC response into the same
/// [ServerResponse] the JSON carrier would have produced, with every declared
/// attachment's bytes spliced over its `null` placeholder.
///
/// [bodyBytes] is the raw response body and [contentType] its full
/// `Content-Type`, boundary parameter included. Decoding fails loud on any
/// departure from the framing described in this library's doc comment.
ServerResponse decodeRpcAttachmentResponse({
  required List<int> bodyBytes,
  required String contentType,
}) {
  final boundary = _boundaryOf(contentType);
  final parts = _parseParts(bodyBytes, boundary);

  final metadata = parts.remove('metadata');
  if (metadata == null) {
    throw const FormatException(
      'multipart RPC response carries no "metadata" field',
    );
  }
  final Object? envelopeJson;
  try {
    envelopeJson = jsonDecode(utf8.decode(metadata));
  } on FormatException catch (error) {
    throw FormatException('multipart RPC "metadata" is not UTF-8 JSON: $error');
  }
  final envelope = _asObject(envelopeJson);
  if (envelope == null) {
    throw const FormatException(
      'multipart RPC "metadata" is not a JSON object',
    );
  }
  final response = ServerResponse.fromJson(envelope);
  final value = response.result.value;
  if (!response.result.ok || value == null) {
    throw const FormatException(
      'multipart RPC response carries no successful result value',
    );
  }
  final attachments = _asArray(envelope['attachments']);
  if (attachments == null || attachments.isEmpty) {
    throw const FormatException(
      'multipart RPC response declares no attachment',
    );
  }
  for (final entry in attachments) {
    final attachment = _asObject(entry);
    if (attachment == null) {
      throw FormatException(
        'multipart RPC attachment is not a JSON object: $entry',
      );
    }
    final codec = attachment['codec'];
    if (codec != 'bytes') {
      throw FormatException(
        'multipart RPC attachment codec "$codec" is not "bytes"',
      );
    }
    final partName = attachment['part'];
    if (partName is! String || partName.isEmpty) {
      throw FormatException(
        'multipart RPC attachment has no "part" name: $attachment',
      );
    }
    final path = _asArray(attachment['path']);
    if (path == null || path.isEmpty) {
      throw FormatException(
        'multipart RPC attachment "$partName" has no result path',
      );
    }
    final bytes = parts.remove(partName);
    if (bytes == null) {
      throw FormatException(
        'multipart RPC response carries no field for attachment part '
        '"$partName"',
      );
    }
    _splice(value, path, bytes, partName);
  }
  if (parts.isNotEmpty) {
    throw FormatException(
      'multipart RPC response carries undeclared field(s) '
      '${parts.keys.toList()}',
    );
  }
  return response;
}

/// Reads the boundary parameter of a `multipart/form-data` [contentType].
String _boundaryOf(String contentType) {
  final parameters = contentType.split(';');
  if (parameters.isEmpty ||
      parameters.first.trim().toLowerCase() != kRpcAttachmentMediaType) {
    throw FormatException('not a multipart RPC response: "$contentType"');
  }
  for (final parameter in parameters.skip(1)) {
    final equals = parameter.indexOf('=');
    if (equals == -1) continue;
    if (parameter.substring(0, equals).trim().toLowerCase() != 'boundary') {
      continue;
    }
    final value = _unquote(parameter.substring(equals + 1).trim());
    if (value.isEmpty) break;
    return value;
  }
  throw FormatException(
    'multipart RPC response has no boundary parameter: "$contentType"',
  );
}

/// Splits the body into one entry per named form field.
///
/// The delimiter is `--<boundary>` at the body's start or after a CRLF; the
/// closing delimiter is followed by `--`.
Map<String, Uint8List> _parseParts(List<int> body, String boundary) {
  final delimiter = _ascii('--$boundary');
  final crlfDelimiter = _ascii('\r\n--$boundary');
  final crlf = _ascii('\r\n');
  final terminator = _ascii('--');
  final parts = <String, Uint8List>{};
  int cursor;
  if (_startsWith(body, 0, delimiter)) {
    cursor = 0;
  } else {
    final found = _indexOf(body, crlfDelimiter, 0);
    if (found == -1) {
      throw const FormatException(
        'multipart RPC response has no boundary delimiter',
      );
    }
    cursor = found + 2;
  }
  while (true) {
    final afterDelimiter = cursor + delimiter.length;
    if (_startsWith(body, afterDelimiter, terminator)) return parts;
    if (!_startsWith(body, afterDelimiter, crlf)) {
      throw const FormatException(
        'multipart RPC response boundary is not followed by CRLF',
      );
    }
    final partStart = afterDelimiter + 2;
    final next = _indexOf(body, crlfDelimiter, partStart);
    if (next == -1) {
      throw const FormatException('multipart RPC response ends inside a part');
    }
    _addPart(parts, body.sublist(partStart, next));
    cursor = next + 2;
  }
}

/// Records one part under the `name` of its `Content-Disposition` header.
void _addPart(Map<String, Uint8List> parts, List<int> part) {
  final headerEnd = _indexOf(part, _ascii('\r\n\r\n'), 0);
  if (headerEnd == -1) {
    throw const FormatException('multipart RPC part has no header terminator');
  }
  final headers = utf8.decode(part.sublist(0, headerEnd));
  String? name;
  for (final line in headers.split('\r\n')) {
    final colon = line.indexOf(':');
    if (colon == -1) {
      throw FormatException(
        'multipart RPC part has a malformed header "$line"',
      );
    }
    if (line.substring(0, colon).trim().toLowerCase() !=
        'content-disposition') {
      continue;
    }
    name = _dispositionName(line.substring(colon + 1).trim());
  }
  if (name == null) {
    throw const FormatException(
      'multipart RPC part has no Content-Disposition name',
    );
  }
  if (parts.containsKey(name)) {
    throw FormatException('multipart RPC response repeats field "$name"');
  }
  parts[name] = Uint8List.fromList(part.sublist(headerEnd + 4));
}

/// Reads the `name` parameter of one `Content-Disposition` header value.
String? _dispositionName(String value) {
  final segments = value.split(';');
  if (segments.first.trim().toLowerCase() != 'form-data') {
    throw FormatException('multipart RPC part is not form-data: "$value"');
  }
  for (final segment in segments.skip(1)) {
    final equals = segment.indexOf('=');
    if (equals == -1) continue;
    if (segment.substring(0, equals).trim().toLowerCase() != 'name') continue;
    final name = _unquote(segment.substring(equals + 1).trim());
    if (name.isEmpty) {
      throw const FormatException('multipart RPC part has an empty name');
    }
    return name;
  }
  return null;
}

/// Writes [bytes] over the `null` placeholder at [path] inside [value].
///
/// [path] is relative to the result value: string segments index JSON objects,
/// integer segments index arrays.
void _splice(
  Map<String, Object?> value,
  List<Object?> path,
  Uint8List bytes,
  String partName,
) {
  Object? container = value;
  for (final segment in path.take(path.length - 1)) {
    container = _child(container, segment, partName, path);
  }
  final last = path.last;
  if (container is Map<String, Object?>) {
    if (last is! String || !container.containsKey(last)) {
      throw FormatException(
        'multipart RPC attachment "$partName" path $path leaves the result '
        'value',
      );
    }
    if (container[last] != null) {
      throw FormatException(
        'multipart RPC attachment "$partName" placeholder at $path is not null',
      );
    }
    container[last] = bytes;
    return;
  }
  if (container is List<Object?>) {
    if (last is! int || last < 0 || last >= container.length) {
      throw FormatException(
        'multipart RPC attachment "$partName" path $path leaves the result '
        'value',
      );
    }
    if (container[last] != null) {
      throw FormatException(
        'multipart RPC attachment "$partName" placeholder at $path is not null',
      );
    }
    container[last] = bytes;
    return;
  }
  throw FormatException(
    'multipart RPC attachment "$partName" path $path does not name a JSON '
    'container',
  );
}

/// Reads one intermediate [path] segment out of [container].
Object? _child(
  Object? container,
  Object? segment,
  String partName,
  List<Object?> path,
) {
  if (container is Map<String, Object?>) {
    if (segment is! String || !container.containsKey(segment)) {
      throw FormatException(
        'multipart RPC attachment "$partName" path $path leaves the result '
        'value',
      );
    }
    return container[segment];
  }
  if (container is List<Object?>) {
    if (segment is! int || segment < 0 || segment >= container.length) {
      throw FormatException(
        'multipart RPC attachment "$partName" path $path leaves the result '
        'value',
      );
    }
    return container[segment];
  }
  throw FormatException(
    'multipart RPC attachment "$partName" path $path does not name a JSON '
    'container',
  );
}

String _unquote(String value) =>
    value.length >= 2 && value.startsWith('"') && value.endsWith('"')
    ? value.substring(1, value.length - 1)
    : value;

Map<String, Object?>? _asObject(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return null;
}

List<Object?>? _asArray(Object? value) {
  if (value is List<Object?>) return value;
  if (value is List) return value.cast<Object?>();
  return null;
}

Uint8List _ascii(String value) => Uint8List.fromList(value.codeUnits);

bool _startsWith(List<int> haystack, int at, List<int> needle) {
  if (at < 0 || at + needle.length > haystack.length) return false;
  for (var i = 0; i < needle.length; i++) {
    if (haystack[at + i] != needle[i]) return false;
  }
  return true;
}

int _indexOf(List<int> haystack, List<int> needle, int from) {
  final last = haystack.length - needle.length;
  for (var at = from; at <= last; at++) {
    if (_startsWith(haystack, at, needle)) return at;
  }
  return -1;
}
