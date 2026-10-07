/// Open-in-app vocabulary: which operating-system applications the serving
/// desktop has registered to open a workspace path.
///
/// Mirrors the Session controller's `workspacePathApplications` result
/// (`reference/deepseek-harness/packages/api/session-controller/src/types.ts`
/// `SessionWorkspacePathApplication`, itself
/// `packages/util/native-command/src/types.ts` `NativeFileApplication`). The
/// host resolves these per path; the phone offers the Open workspace verb
/// only when `canOpenWorkspacePath` says the deployment has a native opener,
/// and lists the registered applications when more than one answers.
library;

/// One OS-registered application capable of opening the requested file.
final class WorkspacePathApplication {
  const WorkspacePathApplication({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.icon,
  });

  /// OS application identifier; the host revalidates it against the file's
  /// current handlers before opening, so a stale id is a refusal rather than
  /// a launch of something else.
  final String id;

  /// Display name the desktop reported for [id].
  final String name;

  /// Whether the desktop opens the file with this application when no
  /// application is requested (the wire `default`). Best effort: the host
  /// reports a marker, not a promise.
  final bool isDefault;

  /// PNG or SVG data URL the desktop supplied for this application, or null
  /// when it supplied none. Carried verbatim — the phone lists application
  /// names, because a data URL is not a source the Flutter image pipeline
  /// loads.
  final String? icon;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkspacePathApplication &&
          other.id == id &&
          other.name == name &&
          other.isDefault == isDefault &&
          other.icon == icon);

  @override
  int get hashCode => Object.hash(id, name, isDefault, icon);
}
