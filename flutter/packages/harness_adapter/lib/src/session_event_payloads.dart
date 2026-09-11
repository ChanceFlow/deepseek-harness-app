/// Decoders for `session/event` payloads that carry facts the timeline fold
/// and the repository's per-session projections consume, plus the
/// `tool/result` presentation narrowing.
///
/// Every decoder reads field names, nullability, and nesting from the
/// pinned reference sources named on each function; a required field that is
/// absent or mistyped throws with the field name ([wireRequiredString] and
/// friends).
library;

import 'package:domain/model/cordis.dart';
import 'package:domain/model/hook.dart';
import 'package:domain/model/sandbox.dart';
import 'package:domain/model/schedule.dart';
import 'package:domain/model/tool_presentation.dart';

import 'rpc_map.dart';
import 'wire_json.dart';

// ---------------------------------------------------------------------------
// sandbox/mode (packages/sandbox/sandbox-policy/src/session-mode.ts)
// ---------------------------------------------------------------------------

/// Decodes one log-only `sandbox/mode` event's data. The event is the
/// session's override write path: the LAST such event wins, and an absent
/// `source` marks a runtime switch (`source: 'delegation'` marks an override
/// seeded into a child).
SandboxModeFact decodeSandboxModeEvent(JsonMap data) {
  final mode = switch (wireRequiredString(data, 'mode')) {
    'read-only' => SandboxMode.readOnly,
    'workspace-write' => SandboxMode.workspaceWrite,
    'danger-full-access' => SandboxMode.dangerFullAccess,
    final other => throw FormatException(
      'sandbox/mode "mode" is not a known value: "$other"',
    ),
  };
  final source = wireString(data, 'source');
  if (source != null && source != 'delegation') {
    throw FormatException(
      'sandbox/mode "source" is not a known value: "$source"',
    );
  }
  return SandboxModeFact(
    mode: mode,
    seededByDelegation: source == 'delegation',
  );
}

// ---------------------------------------------------------------------------
// schedule/change and the `schedule` projection
// (packages/schedule/schedule/src/types.ts)
// ---------------------------------------------------------------------------

/// One decoded `schedule/change` mutation. Adapter-internal: the reducer
/// folds it into the session's active [ScheduleReminder] list.
sealed class ScheduleChange {
  const ScheduleChange();
}

/// `{version: 1, operation: 'create', schedule: ScheduleRecord}`.
final class ScheduleCreate extends ScheduleChange {
  const ScheduleCreate(this.reminder);

  final ScheduleReminder reminder;
}

/// `{version: 1, operation: 'delete', id}`.
final class ScheduleDelete extends ScheduleChange {
  const ScheduleDelete(this.id);

  final String id;
}

/// `{version: 1, operation: 'dispatch', id[, acceptedAt]}` — a one-shot
/// leaves the active set; a fixed-rate one advances past the occurrence.
final class ScheduleDispatch extends ScheduleChange {
  const ScheduleDispatch(this.id, {this.acceptedAt});

  final String id;

  /// Wall-clock decision time of a fixed-rate dispatch; null for a one-shot.
  final String? acceptedAt;
}

/// Decodes one durable [ScheduleReminder] record (`ScheduleRecord`):
/// `kind` is the closed rule discriminator; `afterSeconds` is required for
/// `after` and `everySeconds` for `every`, both forbidden elsewhere.
ScheduleReminder decodeScheduleRecord(JsonMap json) {
  final id = wireRequiredString(json, 'id');
  final prompt = wireRequiredString(json, 'prompt');
  final scheduledAt = wireRequiredString(json, 'scheduledAt');
  switch (wireRequiredString(json, 'kind')) {
    case 'after':
      return ScheduleReminder(
        id: id,
        kind: ScheduleReminderKind.after,
        prompt: prompt,
        scheduledAt: scheduledAt,
        afterSeconds: wireRequiredLong(json, 'afterSeconds'),
      );
    case 'at':
      return ScheduleReminder(
        id: id,
        kind: ScheduleReminderKind.at,
        prompt: prompt,
        scheduledAt: scheduledAt,
      );
    case 'every':
      return ScheduleReminder(
        id: id,
        kind: ScheduleReminderKind.every,
        prompt: prompt,
        scheduledAt: scheduledAt,
        everySeconds: wireRequiredLong(json, 'everySeconds'),
      );
    case final other:
      throw FormatException(
        'schedule record "kind" is not a known value: "$other"',
      );
  }
}

/// Decodes one versioned `schedule/change` event's data. `version` must be
/// the current 1; `operation` selects the mutation arm.
ScheduleChange decodeScheduleChange(JsonMap data) {
  final version = wireRequiredLong(data, 'version');
  if (version != 1) {
    throw FormatException('schedule/change "version" must be 1, got $version');
  }
  switch (wireRequiredString(data, 'operation')) {
    case 'create':
      return ScheduleCreate(
        decodeScheduleRecord(wireRequiredObject(data, 'schedule')),
      );
    case 'delete':
      return ScheduleDelete(wireRequiredString(data, 'id'));
    case 'dispatch':
      return ScheduleDispatch(
        wireRequiredString(data, 'id'),
        acceptedAt: wireString(data, 'acceptedAt'),
      );
    case final other:
      throw FormatException(
        'schedule/change "operation" is not a known value: "$other"',
      );
  }
}

// ---------------------------------------------------------------------------
// hook/invoked and hook/result
// (packages/hooks/hook-protocol/src/events.ts and types.ts)
// ---------------------------------------------------------------------------

HookDialect _hookDialect(JsonMap json) =>
    switch (wireRequiredString(json, 'dialect')) {
      'claude-code' => HookDialect.claudeCode,
      'codex' => HookDialect.codex,
      final other => throw FormatException(
        'hook event "dialect" is not a known value: "$other"',
      ),
    };

/// Decodes one log-only `hook/invoked` event's data (the invoked half of an
/// audit pair).
HookAudit decodeHookInvoked(JsonMap data) => HookAudit(
  handlerId: wireRequiredString(data, 'handlerId'),
  turn: wireRequiredLong(data, 'turn'),
  point: wireRequiredString(data, 'point'),
  dialect: _hookDialect(data),
  matcher: wireString(data, 'matcher'),
);

/// Folds one `hook/result` event's data onto its invoked half. `decision`
/// and `durationMs` are required by the wire contract; `exitCode` and
/// `stderrSummary` are optional.
HookAudit applyHookResult(HookAudit base, JsonMap data) => base.withResult(
  decision: wireRequiredString(data, 'decision'),
  exitCode: wireLongOrNull(data, 'exitCode'),
  stderrSummary: wireString(data, 'stderrSummary'),
  durationMs: wireRequiredLong(data, 'durationMs'),
);

// ---------------------------------------------------------------------------
// tool-workflow/* (packages/workflow/tool-workflow/src/types.ts)
// ---------------------------------------------------------------------------

/// `tool-workflow/run-start` data.
final class WorkflowRunStartData {
  const WorkflowRunStartData({required this.runId, required this.name});

  final String runId;
  final String name;
}

WorkflowRunStartData decodeWorkflowRunStart(JsonMap data) =>
    WorkflowRunStartData(
      runId: wireRequiredString(data, 'runId'),
      name: wireRequiredString(data, 'name'),
    );

/// `tool-workflow/agent-start` data.
final class WorkflowAgentStartData {
  const WorkflowAgentStartData({
    required this.runId,
    required this.seq,
    required this.label,
    required this.childId,
    this.phase,
  });

  final String runId;
  final int seq;
  final String label;
  final String childId;

  /// Progress group; null when the member declared none.
  final String? phase;
}

WorkflowAgentStartData decodeWorkflowAgentStart(JsonMap data) =>
    WorkflowAgentStartData(
      runId: wireRequiredString(data, 'runId'),
      seq: wireRequiredLong(data, 'seq'),
      label: wireRequiredString(data, 'label'),
      childId: wireRequiredString(data, 'childId'),
      phase: wireString(data, 'phase'),
    );

/// The closed member-outcome union (`WorkflowAgentOutcome`).
enum WorkflowMemberOutcome { completed, failed, cancelled }

/// `tool-workflow/agent-end` data.
final class WorkflowAgentEndData {
  const WorkflowAgentEndData({
    required this.runId,
    required this.seq,
    required this.outcome,
  });

  final String runId;
  final int seq;
  final WorkflowMemberOutcome outcome;
}

WorkflowAgentEndData decodeWorkflowAgentEnd(JsonMap data) =>
    WorkflowAgentEndData(
      runId: wireRequiredString(data, 'runId'),
      seq: wireRequiredLong(data, 'seq'),
      outcome: switch (wireRequiredString(data, 'outcome')) {
        'completed' => WorkflowMemberOutcome.completed,
        'failed' => WorkflowMemberOutcome.failed,
        'cancelled' => WorkflowMemberOutcome.cancelled,
        final other => throw FormatException(
          'tool-workflow/agent-end "outcome" is not a known value: "$other"',
        ),
      },
    );

/// The closed run-stop-reason union (`WorkflowStopReason`).
enum WorkflowStopReason { completed, cancelled, error }

/// `tool-workflow/run-end` data.
final class WorkflowRunEndData {
  const WorkflowRunEndData({required this.runId, required this.stopReason});

  final String runId;
  final WorkflowStopReason stopReason;
}

WorkflowRunEndData decodeWorkflowRunEnd(JsonMap data) => WorkflowRunEndData(
  runId: wireRequiredString(data, 'runId'),
  stopReason: switch (wireRequiredString(data, 'stopReason')) {
    'completed' => WorkflowStopReason.completed,
    'cancelled' => WorkflowStopReason.cancelled,
    'error' => WorkflowStopReason.error,
    final other => throw FormatException(
      'tool-workflow/run-end "stopReason" is not a known value: "$other"',
    ),
  },
);

/// The collision-free phase identity the reference's `workflowPhaseKey`
/// builds: `missing` for an omitted phase, else `value:<length>:<phase>` so
/// the empty string stays a distinct identity from the absent field.
String workflowPhaseKey(String? phase) =>
    phase == null ? 'missing' : 'value:${phase.length}:$phase';

// ---------------------------------------------------------------------------
// cordis/request-run and cordis/request-run-resolved forwarded events
// (packages/extensions/cordis-host-runner/src/types.ts)
// ---------------------------------------------------------------------------

/// Decodes the single forwarded argument of `cordis/request-run`
/// (`DynamicCordisRunRequest`). The request's `agentId` is the session the
/// blocked `cordis_run` tool call belongs to.
CordisRunRequest decodeCordisRunRequest(JsonMap json) => CordisRunRequest(
  requestId: wireRequiredString(json, 'requestId'),
  sessionId: wireRequiredString(json, 'agentId'),
  pluginId: wireRequiredString(json, 'pluginId'),
  packageId: wireRequiredString(json, 'packageId'),
  mode: switch (wireRequiredString(json, 'mode')) {
    'run' => CordisRunMode.run,
    'update' => CordisRunMode.update,
    final other => throw FormatException(
      'cordis/request-run "mode" is not a known value: "$other"',
    ),
  },
  name: wireRequiredString(json, 'name'),
  purpose: wireRequiredString(json, 'purpose'),
  requiresApproval: wireRequiredBool(json, 'requiresApproval'),
);

/// Decodes the single forwarded argument of `cordis/request-run-resolved`
/// (`DynamicCordisRequestResolved`).
CordisRequestResolved decodeCordisRequestResolved(JsonMap json) =>
    CordisRequestResolved(
      requestId: wireRequiredString(json, 'requestId'),
      outcome: switch (wireRequiredString(json, 'outcome')) {
        'approved' => CordisRequestOutcome.approved,
        'completed' => CordisRequestOutcome.completed,
        'rejected' => CordisRequestOutcome.rejected,
        'cancelled' => CordisRequestOutcome.cancelled,
        'failed' => CordisRequestOutcome.failed,
        final other => throw FormatException(
          'cordis/request-run-resolved "outcome" is not a known value: '
          '"$other"',
        ),
      },
    );

// ---------------------------------------------------------------------------
// tool/result presentation (the persisted `output.presentationMeta`).
//
// The host's `presentCall`/`presentResult` functions never cross the wire;
// each tool's `output.presentationMeta` is persisted as the `tool/result`
// event's opaque `meta` member and re-narrowed here exactly as the
// reference's own `presentResult` implementations narrow it
// (packages/fs/tool-fs/src/diff.ts `diffsFromMeta`,
// packages/fs/tool-fs/src/read-render.ts `readMetaFromMeta`,
// packages/fs/tool-fs-search/src/presentation.ts `searchViewFromMeta`,
// packages/web/tool-web/src/{search,fetch}.ts, and
// packages/terminal/tool-terminal/src/index.ts). A payload with no
// recognizable card returns null — the reference's generic fallback; a
// recognized card with a missing member throws naming the field.
// ---------------------------------------------------------------------------

/// Narrows one `tool/result` event's `meta` member into a domain
/// presentation, or null when the tool persisted none and no known card
/// shape matches.
ToolResultPresentation? decodeToolResultPresentation(Object? meta) {
  final json = asJsonObject(meta);
  if (json == null) return null;
  if (json.containsKey('diffs')) return _diffPresentation(json);
  if (json.containsKey('shape')) return _searchPresentation(json);
  if (json.containsKey('sources')) return _webSearchPresentation(json);
  if (json.containsKey('viewport')) return _terminalPresentation(json);
  if (json.containsKey('url') && json.containsKey('statusCode')) {
    return _webFetchPresentation(json);
  }
  if (json.containsKey('path') &&
      json.containsKey('offset') &&
      json.containsKey('lines')) {
    return _readPresentation(json);
  }
  return null;
}

/// `FsDiffMeta` (`{diffs: FileDiff[]}`). The reference rejects an empty list
/// (a no-op write keeps its generic row), so an empty array yields null; a
/// malformed member throws naming the member field.
ToolResultPresentation? _diffPresentation(JsonMap json) {
  final entries = wireRequiredArray(json, 'diffs');
  if (entries.isEmpty) return null;
  final diffs = <FileDiff>[];
  for (final entry in entries) {
    final obj = asJsonObject(entry);
    if (obj == null) {
      throw const FormatException('tool/result "diffs" entry is not an object');
    }
    final oldText = obj.containsKey('oldText') ? obj['oldText'] : null;
    if (oldText != null && oldText is! String) {
      throw const FormatException(
        'required field "oldText" missing or mistyped in tool/result "diffs"',
      );
    }
    diffs.add(
      FileDiff(
        path: wireRequiredString(obj, 'path'),
        oldText: oldText as String?,
        newText: wireRequiredString(obj, 'newText'),
      ),
    );
  }
  return DiffToolPresentation(diffs: diffs);
}

/// `SearchMeta` (`{shape: 'matches'|'paths', ...}`). `truncated` and `total`
/// are required on both variants; an unknown `shape` yields null (the
/// reference's undefined), and a known shape's missing member throws.
ToolResultPresentation? _searchPresentation(JsonMap json) {
  final truncated = wireRequiredBool(json, 'truncated');
  final total = wireRequiredLong(json, 'total');
  switch (wireRequiredString(json, 'shape')) {
    case 'matches':
      final files = <SearchFileMatches>[];
      for (final entry in wireRequiredArray(json, 'files')) {
        final obj = asJsonObject(entry);
        if (obj == null) {
          throw const FormatException(
            'tool/result search "files" entry is not an object',
          );
        }
        final matches = <SearchLineMatch>[];
        for (final member in wireRequiredArray(obj, 'matches')) {
          final matchObj = asJsonObject(member);
          if (matchObj == null) {
            throw const FormatException(
              'tool/result search "matches" entry is not an object',
            );
          }
          matches.add(
            SearchLineMatch(
              lineNumber: wireRequiredLong(matchObj, 'lineNumber'),
              line: wireRequiredString(matchObj, 'line'),
            ),
          );
        }
        files.add(
          SearchFileMatches(
            path: wireRequiredString(obj, 'path'),
            matches: matches,
          ),
        );
      }
      return SearchToolPresentation.matches(
        files: files,
        truncated: truncated,
        total: total,
      );
    case 'paths':
      final paths = wireRequiredArray(json, 'paths')
          .map((Object? value) => value is String ? value : null)
          .whereType<String>()
          .toList();
      return SearchToolPresentation.paths(
        paths: paths,
        truncated: truncated,
        total: total,
      );
    default:
      return null;
  }
}

/// `searchMetaFromValue` (`{sources: WebSource[], truncated, answer?}`).
ToolResultPresentation? _webSearchPresentation(JsonMap json) {
  final sources = <WebSource>[];
  for (final entry in wireRequiredArray(json, 'sources')) {
    final obj = asJsonObject(entry);
    if (obj == null) {
      throw const FormatException(
        'tool/result web "sources" entry is not an object',
      );
    }
    sources.add(
      WebSource(
        url: wireRequiredString(obj, 'url'),
        title: wireString(obj, 'title'),
        snippet: wireString(obj, 'snippet'),
        publishedAt: wireString(obj, 'publishedAt'),
      ),
    );
  }
  return WebToolPresentation.search(
    sources: sources,
    truncated: wireRequiredBool(json, 'truncated'),
    answer: wireString(json, 'answer'),
  );
}

/// `fetchMetaFromValue` (`{url, statusCode, truncated}`).
ToolResultPresentation? _webFetchPresentation(JsonMap json) =>
    WebToolPresentation.fetch(
      url: wireRequiredString(json, 'url'),
      statusCode: wireRequiredLong(json, 'statusCode'),
      truncated: wireRequiredBool(json, 'truncated'),
    );

/// `readMetaFromMeta` (`{path, offset, lines, totalLines, lang?}`).
ToolResultPresentation? _readPresentation(JsonMap json) {
  final lines = <ReadFileLine>[];
  for (final entry in wireRequiredArray(json, 'lines')) {
    final obj = asJsonObject(entry);
    if (obj == null) {
      throw const FormatException(
        'tool/result read "lines" entry is not an object',
      );
    }
    lines.add(
      ReadFileLine(
        number: wireRequiredLong(obj, 'number'),
        text: wireRequiredString(obj, 'text'),
      ),
    );
  }
  return ReadToolPresentation(
    path: wireRequiredString(json, 'path'),
    offset: wireRequiredLong(json, 'offset'),
    lines: lines,
    totalLines: wireRequiredLong(json, 'totalLines'),
    lang: wireString(json, 'lang'),
  );
}

/// The persistent-terminal `presentationMeta`
/// (`{viewport, waitReason, sessionStatus, truncated}`).
ToolResultPresentation? _terminalPresentation(JsonMap json) {
  final waitReason = switch (wireRequiredString(json, 'waitReason')) {
    'stdin_read' => TerminalWaitReason.stdinRead,
    'inferred_idle' => TerminalWaitReason.inferredIdle,
    'timeout' => TerminalWaitReason.timeout,
    'session_exit' => TerminalWaitReason.sessionExit,
    final other => throw FormatException(
      'tool/result terminal "waitReason" is not a known value: "$other"',
    ),
  };
  return TerminalToolPresentation(
    viewport: wireRequiredString(json, 'viewport'),
    waitReason: waitReason,
    truncated: wireRequiredBool(json, 'truncated'),
    sessionStatus: wireRequiredObject(json, 'sessionStatus'),
  );
}
