/// Workspace registry vocabulary.
library;

final class WorkspaceSummary {
  const WorkspaceSummary({
    required this.workspaceId,
    required this.path,
    required this.title,
    this.sessionIds = const <String>[],
    this.createdAt = '',
    this.updatedAt = '',
  });

  final String workspaceId;
  final String path;
  final String title;
  final List<String> sessionIds;
  final String createdAt;
  final String updatedAt;

  @override
  bool operator ==(Object other) =>
      other is WorkspaceSummary &&
      other.workspaceId == workspaceId &&
      other.path == path &&
      other.title == title &&
      _listEquals(other.sessionIds, sessionIds) &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
        workspaceId,
        path,
        title,
        Object.hashAll(sessionIds),
        createdAt,
        updatedAt,
      );
}

final class SessionSearchResult {
  const SessionSearchResult({
    required this.sessionId,
    required this.snippet,
  });

  final String sessionId;
  final String snippet;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
