/// Deterministic Android notification identity for a session's ongoing
/// work notification.
///
/// An in-process id counter cannot address notifications a previous process
/// posted: the ongoing row survives app death in the shade, but the fresh
/// process cannot update or cancel it, stranding an orphan. Hashing the
/// stable `"$backendId/$sessionId"` key gives every process the same id, so
/// the startup reconcile replaces the stale row in place (or cancels it)
/// instead of stacking a duplicate. The tag carries the key string itself as
/// the second identity axis: a cancel matched on (id, tag) hits the right
/// row even if two sessions ever share a hash.
library;

import 'dart:convert';

/// The notification tag: the backend/session key verbatim.
String workingNotificationTag(String backendId, String sessionId) =>
    '$backendId/$sessionId';

/// A deterministic notification id: FNV-1a (32-bit, offset basis
/// `0x811c9dc5`, prime `0x01000193`) over the UTF-8 bytes of
/// [workingNotificationTag], masked to the positive int32 range so the id
/// never looks like an error sentinel in tooling.
int workingNotificationId(String backendId, String sessionId) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(
    workingNotificationTag(backendId, sessionId),
  )) {
    hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF;
  }
  return hash & 0x7FFFFFFF;
}
