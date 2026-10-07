/// Path-only `@` mention candidates (`fileReferences/list`).
library;

/// What one candidate is. A directory keeps completion open so the reader
/// can descend; a file finishes the mention.
enum FileReferenceKind { file, directory }

/// One path-only completion candidate inside the addressed agent's working
/// directory.
///
/// The path is the user-facing text a mention spells (workspace-relative
/// unless the host says otherwise), never a host absolute path: selected
/// values stay ordinary prompt text, and the model reads contents through
/// its own tools.
final class FileReferenceCandidate {
  const FileReferenceCandidate({required this.path, required this.kind});

  /// The path text the mention carries.
  final String path;

  /// Whether [path] names a directory or a file.
  final FileReferenceKind kind;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FileReferenceCandidate &&
          other.path == path &&
          other.kind == kind);

  @override
  int get hashCode => Object.hash(path, kind);
}
