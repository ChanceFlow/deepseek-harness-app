/// Deterministic Android notification identity for a session's rows.
///
/// An in-process id counter cannot address notifications a previous process
/// posted: the ongoing row survives app death in the shade, but the fresh
/// process cannot update or cancel it, stranding an orphan. Hashing the
/// stable `"$backendId/$sessionId"` key gives every process the same id, so
/// the startup reconcile replaces the stale row in place (or cancels it)
/// instead of stacking a duplicate. The tag carries the key string itself as
/// the second identity axis: a cancel matched on (id, tag) hits the right
/// row even if two sessions ever share a hash.
///
/// A session owns two such identities: the ongoing/done row
/// ([workingNotificationTag]) and the pending-interaction row
/// ([pendingNotificationTag]). They are separate rows with separate ids, so
/// resolving the interaction cancels the pending row without touching the
/// session's ongoing one.
library;

import 'dart:convert';

/// The ongoing/done notification tag: the backend/session key verbatim.
String workingNotificationTag(String backendId, String sessionId) =>
    '$backendId/$sessionId';

/// The pending-interaction notification tag.
///
/// The `/pending` suffix keeps it distinct from the ongoing row's tag, so
/// the two rows can coexist for the same session and a `cancel(id, tag)`
/// targets exactly one of them.
String pendingNotificationTag(String backendId, String sessionId) =>
    '$backendId/$sessionId/pending';

/// A deterministic ongoing/done notification id: FNV-1a (32-bit, offset
/// basis `0x811c9dc5`, prime `0x01000193`) over the UTF-8 bytes of
/// [workingNotificationTag], masked to the positive int32 range so the id
/// never looks like an error sentinel in tooling.
int workingNotificationId(String backendId, String sessionId) =>
    _fnv1a(workingNotificationTag(backendId, sessionId));

/// A deterministic pending-interaction notification id over
/// [pendingNotificationTag]. Distinct from [workingNotificationId] for the
/// same session because the hashed strings differ.
int pendingNotificationId(String backendId, String sessionId) =>
    _fnv1a(pendingNotificationTag(backendId, sessionId));

/// FNV-1a over the raw string's UTF-8 bytes, masked to int32-positive.
int _fnv1a(String raw) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(raw)) {
    hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF;
  }
  return hash & 0x7FFFFFFF;
}
