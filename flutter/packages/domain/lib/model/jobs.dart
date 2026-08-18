/// Background-job snapshots pushed by `session/jobs` frames.
library;

enum JobStatus { running, stopping, completed, killed, failed }

final class JobView {
  const JobView({
    required this.id,
    required this.kind,
    required this.label,
    required this.status,
    this.detail,
    this.startedAt = 0,
    this.finishedAt,
  });

  final String id;
  final String kind;
  final String label;
  final JobStatus status;
  final String? detail;
  final int startedAt;
  final int? finishedAt;

  @override
  bool operator ==(Object other) =>
      other is JobView &&
      other.id == id &&
      other.kind == kind &&
      other.label == label &&
      other.status == status &&
      other.detail == detail &&
      other.startedAt == startedAt &&
      other.finishedAt == finishedAt;

  @override
  int get hashCode =>
      Object.hash(id, kind, label, status, detail, startedAt, finishedAt);
}
