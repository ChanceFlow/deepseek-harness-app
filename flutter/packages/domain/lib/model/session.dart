/// Session list vocabulary.
library;

final class SessionSummary {
  const SessionSummary({
    required this.id,
    this.title,
    this.running = false,
    this.blank = true,
    this.workspaceId,
    this.updatedAtEpochMs = 0,
    this.cwd,
    this.agentPreset,
  });

  final String id;
  final String? title;
  final bool running;
  final bool blank;
  final String? workspaceId;
  final int updatedAtEpochMs;
  final String? cwd;
  final String? agentPreset;

  /// Same label rule as the Web client: durable title first, then the
  /// canonical workspace path basename, then the raw session id.
  String get displayTitle {
    final durable = title;
    if (durable != null && durable.trim().isNotEmpty) return durable;
    final path = cwd;
    if (path != null) {
      final segments = path.split(RegExp(r'[/\\]'));
      for (final segment in segments.reversed) {
        if (segment.trim().isNotEmpty) return segment;
      }
    }
    return id;
  }

  @override
  bool operator ==(Object other) =>
      other is SessionSummary &&
      other.id == id &&
      other.title == title &&
      other.running == running &&
      other.blank == blank &&
      other.workspaceId == workspaceId &&
      other.updatedAtEpochMs == updatedAtEpochMs &&
      other.cwd == cwd &&
      other.agentPreset == agentPreset;

  @override
  int get hashCode => Object.hash(
        id,
        title,
        running,
        blank,
        workspaceId,
        updatedAtEpochMs,
        cwd,
        agentPreset,
      );
}

final class CreateSessionRequest {
  const CreateSessionRequest({
    this.sessionId,
    this.workspaceId,
    this.cwd,
    this.agentPreset,
  });

  final String? sessionId;
  final String? workspaceId;
  final String? cwd;
  final String? agentPreset;

  @override
  bool operator ==(Object other) =>
      other is CreateSessionRequest &&
      other.sessionId == sessionId &&
      other.workspaceId == workspaceId &&
      other.cwd == cwd &&
      other.agentPreset == agentPreset;

  @override
  int get hashCode => Object.hash(sessionId, workspaceId, cwd, agentPreset);
}

enum QueuePlacement { queued, steering, context }

enum QueueUpdateKind { remove, steer, edit }

final class QueueUpdateRequest {
  const QueueUpdateRequest({
    required this.sessionId,
    required this.itemId,
    required this.kind,
    this.text,
  });

  final String sessionId;
  final String itemId;
  final QueueUpdateKind kind;
  final String? text;

  @override
  bool operator ==(Object other) =>
      other is QueueUpdateRequest &&
      other.sessionId == sessionId &&
      other.itemId == itemId &&
      other.kind == kind &&
      other.text == text;

  @override
  int get hashCode => Object.hash(sessionId, itemId, kind, text);
}
