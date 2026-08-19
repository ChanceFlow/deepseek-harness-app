/// Background-jobs header action — port of the web ui-jobs JobListAction:
/// a session-header pill ("N background jobs running" + live dot + chevron)
/// that opens the ordered job list. Renders nothing without jobs.
library;

import 'dart:async';

import 'package:domain/model/jobs.dart';
import 'package:flutter/material.dart';

import '../theme/deepsuite_extension.dart';
import '../theme/deepsuite_tokens.dart';

/// A job the registry still holds open (its duration ticks).
bool _isLive(JobView job) =>
    job.status == JobStatus.running || job.status == JobStatus.stopping;

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
String formatJobDuration(int elapsedMs) {
  final total = elapsedMs < 0 ? 0 : elapsedMs ~/ 1000;
  final seconds = total % 60;
  final minutes = total ~/ 60 % 60;
  final hours = total ~/ 3600;
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m ${seconds}s';
  return '${seconds}s';
}

String _statusLabel(JobStatus status) => switch (status) {
  JobStatus.running => 'running',
  JobStatus.stopping => 'stopping',
  JobStatus.completed => 'completed',
  JobStatus.killed => 'cancelled',
  JobStatus.failed => 'failed',
};

class JobListAction extends StatelessWidget {
  const JobListAction({super.key, required this.jobs});

  final List<JobView> jobs;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) return const SizedBox.shrink();
    final liveCount = jobs.where(_isLive).length;
    final count = liveCount > 0 ? liveCount : jobs.length;
    final countLabel = liveCount > 0
        ? (count == 1
              ? '$count background job running'
              : '$count background jobs running')
        : (count == 1 ? '$count background job' : '$count background jobs');
    final ds = dsOf(context);
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _open(context),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        height: 28,
        padding: const EdgeInsets.only(left: 8, right: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (liveCount > 0)
              const _StateDot(state: _DotState.ongoing, size: 8),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                countLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: ds.labelTertiary),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, size: 14, color: ds.labelCaption),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _JobsSheet(jobs: jobs),
    );
  }
}

/// The ordered list (web popover menu form).
class _JobsSheet extends StatefulWidget {
  const _JobsSheet({required this.jobs});

  final List<JobView> jobs;

  @override
  State<_JobsSheet> createState() => _JobsSheetState();
}

class _JobsSheetState extends State<_JobsSheet> {
  DateTime _now = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    final hasLive = widget.jobs.any(_isLive);
    if (hasLive) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final rows = orderedJobs(widget.jobs);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Background jobs',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final job in rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            _StateDot(state: _dotState(job.status), size: 8),
                            const SizedBox(width: 8),
                            Text(job.kind, style: theme.textTheme.labelMedium),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                job.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              job.detail ?? _statusLabel(job.status),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: ds.labelSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formatJobDuration(_elapsedMs(job)),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: ds.labelTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _elapsedMs(JobView job) {
    if (_isLive(job)) {
      return _now.millisecondsSinceEpoch - job.startedAt;
    }
    return (job.finishedAt ?? job.startedAt) - job.startedAt;
  }
}

enum _DotState { ongoing, done, warning, error }

_DotState _dotState(JobStatus status) => switch (status) {
  JobStatus.running => _DotState.ongoing,
  JobStatus.stopping => _DotState.warning,
  JobStatus.completed => _DotState.done,
  JobStatus.killed => _DotState.warning,
  JobStatus.failed => _DotState.error,
};

/// Web StateDot: halo + solid core riding currentColor per state.
class _StateDot extends StatelessWidget {
  const _StateDot({required this.state, required this.size});

  final _DotState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _DotState.ongoing => DeepSuiteStatic.deepseek450,
      _DotState.done => DeepSuiteStatic.green500,
      _DotState.warning => dsOf(context).warnPrimary,
      _DotState.error => Theme.of(context).colorScheme.error,
    };
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
          ),
          Center(
            child: Container(
              width: size * 0.6,
              height: size * 0.6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}
