# Agent Note: Tool summary rows derive from args, not results

Status: implemented

## Problem

Every timeline tool row quoted the settled result's first line — for
subagent delegation calls that meant each `send_message`/`interrupt_agent`
row displayed its full receipt sentence ("message queued as the next turn
for subagent …"), and rows titled themselves with the raw wire tool name.
A goal loop steering a background subagent every round filled the
transcript with repeated receipt lines.

## Decision

Tool rows derive from the web row model
(`reference/deepseek-harness/packages/client/ui-tool/src/client/tool/models/tool-call-model.ts`),
ported as `deriveToolRowModel` in `flutter/app/lib/ui/chat/tool_row_model.dart`:
variant classification (`TOOL_VARIANTS`), figma variant titles plus
tool-owned refinements (`TOOL_TITLES`), an ARGS-derived one-line summary
(`SUMMARY_KEYS` per variant, first string arg, raw-args fallback), pretty
args as the expanded body, the flattened result text only as the expanded
output, and the failure first line as the error row's summary. The
`others` variant keeps the static "Tool call" title with the wire tool
name riding the summary slot (`"<name> · <first string arg>"`) unless the
tool owns a title. `ToolCallRow` renders title/summary/body/output from
the model; the settled result never reaches the collapsed row.

## Alternatives considered

- **Special-case the subagent tool names**: rejected — the row rules are
  generic web contracts; per-tool exceptions would drift from the
  reference and miss the next noisy tool.
- **Keep result-derived summaries but truncate**: rejected — the spam is
  the result text itself; the web deliberately reserves the collapsed
  summary for inputs and the expansion for outputs.
- **Collapse consecutive tool rows into one group**: rejected — the web
  renders one keyed row per call through the tool-call tree; grouping has
  no reference.

## Consequences

Subagent delegation rows read `Tool call · send_message · <subagent id>`
collapsed, with the message and receipt behind the expansion; bash rows
show their description/command, read rows their path, and error rows the
failure's first line in error ink. Non-JSON args (mid-stream truncation)
fall back to the raw string per the web rule.
