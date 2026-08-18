/// Neutral host-directory browser vocabulary. The host returns absolute
/// paths for every entry; the client never joins path segments itself.
library;

final class DirectoryEntry {
  const DirectoryEntry({
    required this.name,
    required this.path,
    required this.hidden,
  });

  final String name;
  final String path;
  final bool hidden;

  @override
  bool operator ==(Object other) =>
      other is DirectoryEntry &&
      other.name == name &&
      other.path == path &&
      other.hidden == hidden;

  @override
  int get hashCode => Object.hash(name, path, hidden);
}

final class DirectoryListing {
  const DirectoryListing({
    required this.path,
    required this.home,
    required this.crumbs,
    required this.entries,
    required this.truncated,
  });

  final String path;
  final String home;
  final List<DirectoryEntry> crumbs;
  final List<DirectoryEntry> entries;
  final bool truncated;

  @override
  bool operator ==(Object other) =>
      other is DirectoryListing &&
      other.path == path &&
      other.home == home &&
      _listEquals(other.crumbs, crumbs) &&
      _listEquals(other.entries, entries) &&
      other.truncated == truncated;

  @override
  int get hashCode => Object.hash(
        path,
        home,
        Object.hashAll(crumbs),
        Object.hashAll(entries),
        truncated,
      );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
