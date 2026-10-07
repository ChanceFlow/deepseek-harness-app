/// Background-job snapshots pushed by `session/jobs` frames, and the
/// retained-output vocabulary of one `job/follow` observation.
library;

/// The registry's job lifecycle (`packages/jobs/jobs/src/view.ts` `JobStatus`).
enum JobStatus { running, stopping, completed, killed, failed }

/// The producer stream a retained chunk came from (`JobChunk.channel`).
///
/// A producer that supplies no channel leaves the chunk unlabelled, so the
/// absence is modelled as a nullable field rather than a fourth value.
enum JobChannel { stdout, stderr, log }

/// One background job's roster row (`packages/jobs/jobs/src/view.ts`
/// `JobView`).
///
/// `kind` stays an open string on purpose: the wire type is `string`, because
/// a bundle or codec sees only the producer kinds its own program compiles.
final class JobView {
  const JobView({
    required this.id,
    required this.kind,
    required this.label,
    required this.status,
    this.owner,
    this.progress,
    this.detail,
    this.startedAt = 0,
    this.finishedAt,
    this.output,
  });

  final String id;
  final String kind;
  final String label;

  /// Owning session; absent for an unowned job every caller can see.
  final String? owner;

  final JobStatus status;

  /// The producer's live progress line (`3/10`); cleared at settlement.
  final String? progress;

  /// Terminal reason (`exit code: 3`), with a recorded kill reason merged in.
  final String? detail;

  final int startedAt;
  final int? finishedAt;

  /// The retained output ring's bounds; null only for a host that omitted
  /// them, which the decoder treats as "nothing retained".
  final JobOutputWindow? output;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JobView &&
          other.id == id &&
          other.kind == kind &&
          other.label == label &&
          other.owner == owner &&
          other.status == status &&
          other.progress == progress &&
          other.detail == detail &&
          other.startedAt == startedAt &&
          other.finishedAt == finishedAt &&
          other.output == output);

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    label,
    owner,
    status,
    progress,
    detail,
    startedAt,
    finishedAt,
    output,
  );
}

/// One job's retained-output bounds (`JobView.output`).
///
/// [earliest] is the oldest retained byte and is above zero exactly when
/// retention dropped the head; [total] is the offset the next appended chunk
/// starts at.
final class JobOutputWindow {
  const JobOutputWindow({
    required this.total,
    required this.earliest,
    this.spillPaths = const <String>[],
  });

  final int total;
  final int earliest;
  final List<String> spillPaths;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JobOutputWindow &&
          other.total == total &&
          other.earliest == earliest &&
          _listEquals(other.spillPaths, spillPaths));

  @override
  int get hashCode => Object.hash(total, earliest, Object.hashAll(spillPaths));
}

/// One chunk of a job's output ring (`packages/jobs/jobs/src/view.ts`
/// `JobChunk`).
///
/// [at] is the chunk's absolute first-byte offset and never moves once
/// assigned. [gapBefore] means bytes immediately before this chunk were lost,
/// at the producer or to retention; it is never explicitly false on the wire,
/// so the decoder models absence as `false`.
final class JobOutputChunk {
  const JobOutputChunk({
    required this.at,
    required this.text,
    this.channel,
    this.gapBefore = false,
  });

  final int at;
  final String text;
  final JobChannel? channel;
  final bool gapBefore;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JobOutputChunk &&
          other.at == at &&
          other.text == text &&
          other.channel == channel &&
          other.gapBefore == gapBefore);

  @override
  int get hashCode => Object.hash(at, text, channel, gapBefore);
}

/// One frame of a `job/follow` observation stream
/// (`packages/api/job-controller/src/types.ts` `JobFollowFrame`).
sealed class JobOutputFrame {
  const JobOutputFrame();
}

/// The first frame of every generation: the job, and the absolute byte offset
/// the following output frames continue from.
///
/// A generation opened without a resume offset anchors at the job's oldest
/// retained byte, never at zero.
final class JobOutputOpened extends JobOutputFrame {
  const JobOutputOpened({required this.job, required this.from});

  final JobView job;
  final int from;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JobOutputOpened && other.job == job && other.from == from);

  @override
  int get hashCode => Object.hash(job, from);
}

/// Coalesced retained output after the anchor.
///
/// [next] is the offset to resume from after this frame. [lossy] means bytes
/// between the requested offset and [chunks] were already evicted; the wire
/// flag is only ever present as `true`.
final class JobOutputChunks extends JobOutputFrame {
  const JobOutputChunks({
    required this.chunks,
    required this.next,
    this.lossy = false,
  });

  final List<JobOutputChunk> chunks;
  final int next;
  final bool lossy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JobOutputChunks &&
          other.next == next &&
          other.lossy == lossy &&
          _listEquals(other.chunks, chunks));

  @override
  int get hashCode => Object.hash(Object.hashAll(chunks), next, lossy);
}

/// The terminal projection: the job settled and its retained ring drained.
///
/// This frame closes the stream; a job removed mid-generation reports its
/// removal through this same frame rather than as a read failure.
final class JobOutputStatus extends JobOutputFrame {
  const JobOutputStatus({required this.job});

  final JobView job;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is JobOutputStatus && other.job == job);

  @override
  int get hashCode => job.hashCode;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
