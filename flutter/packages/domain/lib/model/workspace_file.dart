/// Pure-Dart domain representations for DSH 0.1.5 workspaceFiles service.
library;

/// File metadata without content.
final class WorkspaceFileStat {
  const WorkspaceFileStat({
    required this.absolutePath,
    required this.version,
    this.bytes,
  });

  final String absolutePath;
  final String version;
  final int? bytes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkspaceFileStat &&
          other.absolutePath == absolutePath &&
          other.version == version &&
          other.bytes == bytes);

  @override
  int get hashCode => Object.hash(absolutePath, version, bytes);
}

/// A paged window of text content from a workspace file.
final class WorkspaceFileContent {
  const WorkspaceFileContent({
    required this.absolutePath,
    required this.version,
    required this.text,
    required this.offset,
    required this.lines,
    required this.eof,
    this.bytes,
  });

  final String absolutePath;
  final String version;
  final String text;
  final int offset;
  final int lines;
  final bool eof;
  final int? bytes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkspaceFileContent &&
          other.absolutePath == absolutePath &&
          other.version == version &&
          other.text == text &&
          other.offset == offset &&
          other.lines == lines &&
          other.eof == eof &&
          other.bytes == bytes);

  @override
  int get hashCode =>
      Object.hash(absolutePath, version, text, offset, lines, eof, bytes);
}

/// An entry inside a workspace directory listing.
final class WorkspaceDirectoryEntry {
  const WorkspaceDirectoryEntry({
    required this.name,
    required this.type,
    this.size,
  });

  final String name;
  final String type;
  final int? size;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkspaceDirectoryEntry &&
          other.name == name &&
          other.type == type &&
          other.size == size);

  @override
  int get hashCode => Object.hash(name, type, size);
}

/// A directory listing result inside a session workspace.
final class WorkspaceDirectoryListing {
  const WorkspaceDirectoryListing({
    required this.path,
    required this.entries,
    required this.truncated,
  });

  final String path;
  final List<WorkspaceDirectoryEntry> entries;
  final bool truncated;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkspaceDirectoryListing &&
          other.path == path &&
          other.truncated == truncated &&
          _listEquals(other.entries, entries));

  @override
  int get hashCode => Object.hash(path, truncated, Object.hashAll(entries));

  static bool _listEquals(
    List<WorkspaceDirectoryEntry> a,
    List<WorkspaceDirectoryEntry> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
