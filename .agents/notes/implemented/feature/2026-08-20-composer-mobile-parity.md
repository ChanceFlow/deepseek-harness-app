# Agent Note: Composer mobile parity — newline, access, presets, persistence

Status: implemented

## Problem

The mobile composer deviated from the web client in four user-visible
ways: the keyboard action key sent the draft (soft keyboards have no
reliable Shift+Enter, so multi-line drafts were untypeable), the access
(permission-preset) seat was missing, the agent-preset modes (标准/PTC/
极简) had no selection surface, and drafts, reading positions, and
expansion states were lost on every remount or session switch.

## Decision

**Newline gesture (superseded — see
[2026-08-20-composer-mobile-toolbar.md](2026-08-20-composer-mobile-toolbar.md)).**
The draft field's keyboard action was `TextInputAction.newline`
(maxLines 8) and an explicit 28px circle button beside the ➕ inserted
`\n` at the caret through `controller.value` (a selection range is
replaced; the caret lands after the newline). The mobile toolbar note
removes that button: the keyboard return key is the newline gesture and
the send button the only submit path. While a turn runs, Stop keeps the
web's primary seat and a second send control appears whenever a draft is
ready; its delivery mode follows the persisted `chat.busyEnterBehavior`
preference ('queue' default | 'steer') — the mobile stand-in for the
web's plain-Enter `ComposerSubmissionPolicy.resolve`.

**Access chip** (`ui/chat/permission_select.dart`, port of the web
PermissionSelect seat): a pill in the composer's tools row showing the
current preset (title-cased `option.name`, `Full access` product label
override), fed by `observePermissions(selectedSessionId)` re-subscribed
on session switch; null projection or no session hides it. Picking a
safe preset submits `/permission <value>` through SendPrompt;
`danger-full-access` first shows the web risk Modal as a dialog whose
acknowledgement checkbox gates the Enable button (cancel/escape/dismiss
submit nothing); a `custom` current value renders the chip read-only.

**Preset surfaces** (`ui/chat/preset_seat.dart`): the EmptyHero chip
beside the WorkspaceChip opens a roster picker (display name +
description, `Default` badge, broken presets never offered — they
cannot compose a session). The shown id follows the web seat
precedence: staged pick, then a blank selected session's composition,
then the deployment default. A pick with a blank session selected
dispatches `SelectAgentPreset` (host `agent-preset-locked` refusals
surface in the error strip); otherwise it stages, and the stage rides
`CreateSessionInWorkspace(workspaceId, agentPreset:)` — the controller
passes it to `createSession`, and a reused blank session gets it via
`selectAgentPreset`. Started sessions show a read-only header label
(`agentPresetDisplayName` against the roster) in both app bars.

**Persistence** (`ui/chat/chat_local_state.dart`): a `ChatLocalState`
seam (busy preference + per-session view) over the shared
`LocalStateStore`, resolved from the enclosing ProviderScope so every
consumer writes one store instance. KV keys: `chat.busyEnterBehavior`
(String, written by the settings row), `chat.draft.<sessionId>`
(String), `chat.readOffset.<sessionId>` (double, saved debounced on
reader scrolls), `chat.expandedTools.<sessionId>` (List<String> of
timelineKey values, e.g. `tool:<id>:<status>`),
`chat.collapsedTurns.<sessionId>` (List<int>). The reading position
restores on a session's initial mount clamped to the laid-out extents —
only while the session is idle; a running or streaming session lands at
the bottom and follows.

## Alternatives considered

- **Keep Enter-as-send with a modifier chord**: rejected — soft
  keyboards cannot deliver a reliable Shift+Enter.
- **Route blank-session preset switches through the draft as a slash
  command**: rejected — `agentPreset.select` is an RPC verb, not a host
  command; `/permission` is.
- **Persist per-widget (each row its own store handle)**: rejected —
  the store flushes whole-document; one shared instance is a
  precondition (see `StoreChatLocalState` doc).
- **Expand state keyed by bare tool id**: rejected — the timeline rows'
  own `timelineKey` identity keeps the persisted set aligned with the
  rendered rows across restarts.

## Consequences

The context ring's tap panel also carries the web `~used / window`
figures line (`formatTokens`). Session-switch scroll behavior gains a
restore path; the first laid-out frame of a session never force-scrolls
(the restore-or-bottom jump owns it). Web parity notes: mobile has no
accelerated-Enter inversion (no chord), and the running-send control is
mobile-only. The concurrent `chat_screen_test.dart` case
"primary becomes Stop; submit queues" drives the removed keyboard-action
submission path and needs its owner's update.
