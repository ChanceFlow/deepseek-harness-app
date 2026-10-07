/// Background-jobs header action — port of the web ui-jobs JobListAction:
/// a session-header pill ("N background jobs running" + live dot + chevron)
/// that opens the ordered job list. Renders nothing without jobs.
///
/// The list is live: the sheet watches the same chat state the header reads,
/// so a lifecycle frame settles a row and a kill button converges through the
/// roster instead of a local guess. Live rows and settled rows with retained
/// output expand into that job's observation stream (`job/follow`); a running
/// row carries the reference's two-press stop (`job/kill`).
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/shared/state_dot.dart';
import 'package:domain/model/jobs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';
import 'chat_ui_state.dart';

/// A job the registry still holds open (its duration ticks).
bool _isLive(JobView job) =>
    job.status == JobStatus.running || job.status == JobStatus.stopping;

/// A row with retained output to show: live, or settled with bytes still held.
bool _isObservable(JobView job) => _isLive(job) || (job.output?.total ?? 0) > 0;

/// How long an armed stop waits for its confirming press.
const Duration kJobKillArmWindow = Duration(seconds: 3);

/// How long a refused stop shows its failure hint.
const Duration kJobKillFailedHold = Duration(seconds: 4);

/// Live rows first in start order, then settled rows newest-first.
List<JobView> orderedJobs(List<JobView> jobs) {
  final rows = List<JobView>.of(jobs);
  rows.sort((left, right) {
    final liveLeft = _isLive(left);
    if (liveLeft != _isLive(right)) return liveLeft ? -1 : 1;
    if (liveLeft) return left.startedAt - right.startedAt;
    final finished =
        (right.finishedAt ?? right.startedAt) -
        (left.finishedAt ?? left.startedAt);
    return finished != 0 ? finished : left.startedAt - right.startedAt;
  });
  return rows;
}

/// Elapsed in at most two adjacent units (web formatDuration).
String formatJobDuration(int elapsedMs, AppLocalizations l10n) {
  final total = elapsedMs < 0 ? 0 : elapsedMs ~/ 1000;
  final seconds = total % 60;
  final minutes = total ~/ 60 % 60;
  final hours = total ~/ 3600;
  if (hours > 0) return l10n.jobDurationHoursMinutes(hours, minutes);
  if (minutes > 0) return l10n.jobDurationMinutesSeconds(minutes, seconds);
  return l10n.jobDurationSeconds(seconds);
}

String _statusLabel(JobStatus status, AppLocalizations l10n) =>
    switch (status) {
      JobStatus.running => l10n.jobStatusRunning,
      JobStatus.stopping => l10n.jobStatusStopping,
      JobStatus.completed => l10n.jobStatusCompleted,
      JobStatus.killed => l10n.jobStatusKilled,
      JobStatus.failed => l10n.jobStatusFailed,
    };

class JobListAction extends StatelessWidget {
  const JobListAction({
    required this.jobs,
    required this.sessionId,
    required this.observeJobOutput,
    required this.killJob,
    required this.jobRoster,
    super.key,
  });

  final List<JobView> jobs;

  /// Session whose jobs the sheet shows; fixed for the sheet's lifetime.
  final String sessionId;

  /// One job's retained output (`job/follow`) and the human stop
  /// (`job/kill`), injected like every other screen seam.
  final JobOutputObserver observeJobOutput;
  final JobKiller killJob;

  /// The live roster behind the pill. The sheet outlives the header's own
  /// rebuilds, so it follows this stream rather than a snapshot.
  final Stream<List<JobView>> jobRoster;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final liveCount = jobs.where(_isLive).length;
    final count = liveCount > 0 ? liveCount : jobs.length;
    final countLabel = liveCount > 0
        ? l10n.jobCountRunning(count)
        : l10n.jobCount(count);
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(kShapeDock),
      onTap: () => _open(context),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        height: 28,
        padding: const EdgeInsets.only(left: 8, right: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (liveCount > 0)
              const StateDot(state: StateDotState.ongoing, size: 8),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                countLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, size: 14, color: scheme.outline),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _JobsSheet(
        sessionId: sessionId,
        initialJobs: jobs,
        observeJobOutput: observeJobOutput,
        killJob: killJob,
        jobRoster: jobRoster,
      ),
    );
  }
}

/// The ordered list, following the injected roster, with observable rows.
class _JobsSheet extends StatefulWidget {
  const _JobsSheet({
    required this.sessionId,
    required this.initialJobs,
    required this.observeJobOutput,
    required this.killJob,
    required this.jobRoster,
  });

  final String sessionId;

  /// The roster the header already held when the sheet opened; the live
  /// stream replaces it as soon as it publishes, so the sheet never flashes
  /// empty on the first frame.
  final List<JobView> initialJobs;

  final JobOutputObserver observeJobOutput;
  final JobKiller killJob;
  final Stream<List<JobView>> jobRoster;

  @override
  State<_JobsSheet> createState() => _JobsSheetState();
}

/// One job's accumulated output and its resume cursor.
///
/// Kept per job id for the sheet's lifetime: collapsing and re-expanding
/// resumes at [cursor] instead of replaying the retained head, and the
/// rendered tail stays bounded like the reference's render window.
final class _JobOutputBuffer {
  /// Rendered tail bound in UTF-16 code units (web `RENDER_TAIL_LIMIT`).
  static const int renderTailLimit = 128 * 1024;

  String text = '';
  int? cursor;
  bool gap = false;
  String? error;

  void apply(JobOutputFrame frame) {
    switch (frame) {
      case JobOutputOpened(:final job, :final from):
        cursor = from;
        if (from > (job.output?.earliest ?? 0)) gap = true;
      case JobOutputChunks(:final chunks, :final next, :final lossy):
        if (lossy) gap = true;
        for (final chunk in chunks) {
          if (chunk.gapBefore) gap = true;
          text += chunk.text;
        }
        cursor = next;
        _trimTail();
      case JobOutputStatus():
        break;
    }
  }

  /// Keeps the newest [renderTailLimit] code units, never splitting a
  /// surrogate pair; the trim itself is a retention gap.
  void _trimTail() {
    if (text.length <= renderTailLimit) return;
    var start = text.length - renderTailLimit;
    if (start > 0 &&
        _isLowSurrogate(text.codeUnitAt(start)) &&
        _isHighSurrogate(text.codeUnitAt(start - 1))) {
      start -= 1;
    }
    text = text.substring(start);
    gap = true;
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
  static bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
}

enum _KillPhase { idle, armed, pending, failed }

class _JobsSheetState extends State<_JobsSheet> {
  DateTime _now = DateTime.now();
  Timer? _ticker;

  String? _expandedJobId;
  bool? _settledOpen;
  final Set<String> _clearedJobIds = <String>{};
  final Map<String, _JobOutputBuffer> _buffers = <String, _JobOutputBuffer>{};
  final Map<String, StreamSubscription<JobOutputFrame>> _outputSubs =
      <String, StreamSubscription<JobOutputFrame>>{};

  String? _killJobId;
  _KillPhase _killPhase = _KillPhase.idle;
  Timer? _killTimer;

  /// The roster the sheet renders: the header's snapshot until the live
  /// stream publishes, then whatever the newest frame carries.
  late List<JobView> _roster;
  StreamSubscription<List<JobView>>? _rosterSub;

  @override
  void initState() {
    super.initState();
    _roster = widget.initialJobs;
    _rosterSub = widget.jobRoster.listen((rows) {
      if (!mounted) return;
      setState(() => _roster = rows);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _killTimer?.cancel();
    unawaited(_rosterSub?.cancel());
    for (final sub in _outputSubs.values) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }

  void _syncTicker(bool hasLive) {
    if (hasLive && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    } else if (!hasLive && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final rows = orderedJobs(_roster);
    final liveRows = rows.where(_isLive).toList();
    final settledRows = rows
        .where((job) => !_isLive(job) && !_clearedJobIds.contains(job.id))
        .toList();
    _syncTicker(liveRows.isNotEmpty);
    // While any live work exists the settled tail folds; a settled-only list
    // opens expanded (web default).
    final settledOpen = _settledOpen ?? liveRows.isEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.backgroundJobsTitle,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.close,
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final job in liveRows)
                      ..._row(job, l10n, scheme, theme),
                    if (settledRows.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                        child: Row(
                          children: [
                            TextButton(
                              onPressed: () =>
                                  setState(() => _settledOpen = !settledOpen),
                              child: Text(
                                l10n.jobSettledCount(settledRows.length),
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => setState(() {
                                _clearedJobIds.addAll(
                                  settledRows.map((job) => job.id),
                                );
                              }),
                              child: Text(l10n.jobClearSettled),
                            ),
                          ],
                        ),
                      ),
                      if (settledOpen)
                        for (final job in settledRows)
                          ..._row(job, l10n, scheme, theme),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _row(
    JobView job,
    AppLocalizations l10n,
    ColorScheme scheme,
    ThemeData theme,
  ) {
    final observable = _isObservable(job);
    final expanded = _expandedJobId == job.id;
    // Web parity: the live line is `progress`, the settled line falls back to
    // the terminal reason and then to the status label itself.
    final qualifier =
        job.progress ??
        job.detail ??
        (_isLive(job) ? null : _statusLabel(job.status, l10n));
    return <Widget>[
      InkWell(
        onTap: observable && !expanded ? () => _expand(job) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: StateDot(state: _dotState(job.status), size: 8),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.kind, style: theme.textTheme.labelMedium),
                    Text(
                      job.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    if (qualifier != null)
                      Text(
                        qualifier,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatJobDuration(_elapsedMs(job), l10n),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (job.status == JobStatus.running)
                    _killControl(job, l10n, theme)
                  else if (observable)
                    IconButton(
                      tooltip: expanded ? l10n.jobCollapse : l10n.jobExpand,
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                      ),
                      onPressed: () =>
                          expanded ? _collapseExpanded() : _expand(job),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      if (expanded) _outputPanel(job, l10n, scheme, theme),
      const Divider(height: 1),
    ];
  }

  /// The reference's stop affordance: first press arms, the confirming press
  /// within [kJobKillArmWindow] fires. An admitted kill stays pending until the
  /// roster frame takes the row off `running` — the unary reply and the roster
  /// stream have no cross-carrier order, so re-enabling early would offer a
  /// duplicate kill.
  Widget _killControl(JobView job, AppLocalizations l10n, ThemeData theme) {
    final armed = _killJobId == job.id && _killPhase == _KillPhase.armed;
    final pending = _killJobId == job.id && _killPhase == _KillPhase.pending;
    final failed = _killJobId == job.id && _killPhase == _KillPhase.failed;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (failed)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              l10n.jobKillFailed,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        TextButton(
          onPressed: pending ? null : () => _onKillPressed(job),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Text(
            armed ? l10n.jobKillConfirm : l10n.jobKillStop,
            style: theme.textTheme.labelSmall,
          ),
        ),
      ],
    );
  }

  Widget _outputPanel(
    JobView job,
    AppLocalizations l10n,
    ColorScheme scheme,
    ThemeData theme,
  ) {
    final buffer = _buffers[job.id] ?? (_buffers[job.id] = _JobOutputBuffer());
    final mono = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      height: 1.2,
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(28, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kShapeCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  job.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono,
                ),
              ),
              // The reference copies the command, never the output.
              IconButton(
                tooltip: l10n.copyTooltip,
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_all_outlined),
                onPressed: () {
                  unawaited(Clipboard.setData(ClipboardData(text: job.label)));
                  ScaffoldMessenger.maybeOf(
                    context,
                  )?.showSnackBar(SnackBar(content: Text(l10n.copiedTooltip)));
                },
              ),
            ],
          ),
          if (buffer.gap)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                l10n.jobOutputGap,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          if (buffer.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                l10n.jobOutputError(buffer.error!),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: SingleChildScrollView(
              child: Text(
                buffer.text.isEmpty ? l10n.jobOutputEmpty : buffer.text,
                style: mono?.copyWith(
                  color: buffer.text.isEmpty
                      ? scheme.onSurfaceVariant
                      : scheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _expand(JobView job) {
    setState(() => _expandedJobId = job.id);
    final buffer = _buffers.putIfAbsent(job.id, _JobOutputBuffer.new);
    // Re-entering a row clears its previous error so a working stream is not
    // shadowed by a stale failure notice.
    buffer.error = null;
    final sub = widget
        .observeJobOutput(widget.sessionId, job.id, resumeFrom: buffer.cursor)
        .listen(
          (frame) {
            if (!mounted) return;
            setState(() => buffer.apply(frame));
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() => buffer.error = error.toString());
          },
        );
    _outputSubs[job.id] = sub;
  }

  void _collapseExpanded() {
    final jobId = _expandedJobId;
    if (jobId == null) return;
    setState(() => _expandedJobId = null);
    unawaited(_outputSubs.remove(jobId)?.cancel());
  }

  void _onKillPressed(JobView job) {
    if (_killJobId == job.id && _killPhase == _KillPhase.armed) {
      _killTimer?.cancel();
      setState(() {
        _killJobId = job.id;
        _killPhase = _KillPhase.pending;
      });
      unawaited(_kill(job));
      return;
    }
    _killTimer?.cancel();
    setState(() {
      _killJobId = job.id;
      _killPhase = _KillPhase.armed;
    });
    _killTimer = Timer(kJobKillArmWindow, () {
      if (!mounted || _killJobId != job.id) return;
      setState(() => _killPhase = _KillPhase.idle);
    });
  }

  Future<void> _kill(JobView job) async {
    final accepted = await widget.killJob(widget.sessionId, job.id);
    if (!mounted) return;
    if (accepted) return;
    // The row stays running until the roster says otherwise; a refusal is the
    // only case the surface reports itself.
    setState(() {
      _killJobId = job.id;
      _killPhase = _KillPhase.failed;
    });
    _killTimer?.cancel();
    _killTimer = Timer(kJobKillFailedHold, () {
      if (!mounted || _killJobId != job.id) return;
      setState(() => _killPhase = _KillPhase.idle);
    });
  }

  int _elapsedMs(JobView job) {
    if (_isLive(job)) {
      return _now.millisecondsSinceEpoch - job.startedAt;
    }
    return (job.finishedAt ?? job.startedAt) - job.startedAt;
  }
}

/// Maps a job status onto the shared state-dot vocabulary (web
/// JobListAction's per-status StateDot).
StateDotState _dotState(JobStatus status) => switch (status) {
  JobStatus.running => StateDotState.ongoing,
  JobStatus.stopping => StateDotState.warning,
  JobStatus.completed => StateDotState.done,
  JobStatus.killed => StateDotState.warning,
  JobStatus.failed => StateDotState.error,
};
