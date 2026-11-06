# DeepSeek Harness Android Client Spec (English Digest)

Status: WebView shell shipped
([the shell decision](../.agents/notes/implemented/architecture/2026-11-06-webview-shell.md));
the Flutter rewrite closed on route A (ADR-0001).

## Goal
Render each configured host's own `dsh web` client in a WebView, so the chat
surface is the host's page. The client's own surfaces are the multi-host
registry and Android notifications; every dsh wire concept stays behind the
adapter.

## Non-Goals
No native re-implementation of the host's chat UI, no React Native, no
design-system port. No JavaScript bridge and no injected script: the page
keeps its own navigation state, and the client reads the host API on its own
socket. No dsh backend changes. No client-side authentication.

## Architecture
`app -> domain -> harness_adapter -> network` (pub workspace under `flutter/`).
`harness_adapter` is the only package that knows dsh wire vocabulary.
`app/lib/shell` draws the host pages and their chrome, `app/lib/notifications`
owns the notification pipeline, and `app/lib/backends` owns the device-local
host registry.

## Wire Contract
- Unary: `POST /api/<domain>/<method>` with `client-request` carrying payload wrapped in `args`, answer with `server-response`.
- Events: downlink-only WebSocket `/api/remote.mux` (required, the only downlink). Session running state, peer creation, removal and activity are not decoded from `host/*` frames: they arrive as the forwarded Remote Events `api-session/status`, `api-session/added`, `api-session/removed` and `api-session/activity` on the mux `$events` stream. `/api/events.host` is not a host route (the upgrade hangs, the gateway answers 502) and is no longer dialed.
- Interactive frames answer via `$events/result`; the 0.1.1 `POST /api/respond` carrier is folded as the legacy path.

## Connection Lifecycle
Connected means the required `/api/remote.mux` socket opened and the gateway delivered its `$events` registration answer — the `ready` frame carrying `host.home` (the reference client's connection-generation handshake). A `ready` frame without `host.home`, a stream that closes first, or one that misses its 30 s deadline fails the generation; `host/describe` is not registered at 0.1.7 and `HostDescription` carries only the ready frame's `home` plus a version no route publishes (never defaulted).
Backoff on loss: 500 ms base, factor 2, cap 10 s.
Reconnect refetches session list and open histories, then replays buffered frames.
While work is in flight (a running or user-waiting root session) the client runs a keep-alive foreground service (`dsh/keep_alive`, `specialUse` on API 34+, `dataSync` below) with a partial wake lock, so Android's cached-process freeze after screen lock cannot kill the mux; it stops 30 s after the last session settles.

## Timeline Folding
Raw dsh events fold into `TimelineItem.Message`, `TimelineItem.ToolCall`,
`TimelineItem.ApprovalRequest`, `TimelineItem.QuestionRequest`, and `TimelineItem.Error`.
`seq` is the dedupe boundary. The fold feeds the notification pipeline; the
host's page renders its own transcript.

## UI
One WebView per enabled host, stacked in an `IndexedStack` so switching is a
display change, not a reload. `HostPoolPolicy.maxLive` defaults to 3: beyond
that the least-recently-used page is released and reloads from its URL when
next selected, and the active host is never evicted. The shell draws only its
chrome — a 44 px host bar (label, reachability dot, switcher) and a 280 px
drawer (add and select) — around the page's `SafeArea`; there is no bottom
navigation, no per-screen app bar, and no Material 3 port. The host's page owns
its pixels and its navigation state. Notifications do not ride the page: the
adapter keeps one event socket per enabled host, `ChatRepository.observeSessions()`
folds the roster into `AppNotificationCenter`, and the result is an Android
notification (plus a foreground toast composed by `ShellLifecycle`). There is
no JavaScript bridge.

## Known Limitations
- **No bridge, so a notification is not a deep link.** A tap brings the app
  forward on the current host; the page's navigation state stays private.
- **The pool caps warm pages at three.** A fourth host reloads when selected,
  and each live page costs roughly 100–200 MB.
- **Cookies ignore ports.** Two hosts on one domain at different ports share
  storage; a path-mounted single-origin gateway is not safe.
- **The host page ships no safe-area/viewport-fit handling.** The shell wraps
  it in `SafeArea`; a cutout inside the page is the host's layout to fix.
- **Native extras are gone with the native screens.** Voice input and
  on-device ASR, the in-app error-log viewer, gesture shortcuts, and the
  aggregated cross-host workspace view have no shell surface.
- **Host editing is controller-only.** The drawer adds and selects a host;
  rename, URL edit, removal and the per-host TLS-certificate opt-in have no
  shell seat yet.
- **Notification coverage is roster-shaped.** A finished-but-unviewed turn
  arms from the `api-session/status` edge and reconciles on the reconnect
  pull; a pending approval or question notifies from the registry pending map.

## Subagent Ownership
Address by parentSessionId + childSessionId. Never derive identity from labels.
MVP supports subagent.list, subagent.prompt, subagent.interrupt.
A child's transcript is read through session/page with a subagent address
({kind: 'subagent', parentSessionId, childSessionId, mode}): the address mode
must match the durable entry or the host answers subagent/unauthorized, and a
child the catalog no longer lists answers subagent/not-found. The pre-0.1.5
subagent/history name stays declared in the endpoint registry with no call site.


## Session Titles
Initial titles come from session.list projections.values.title.
Live title projection frames update the session list. Titles are display only.


## Goal Flow
GoalRef/GoalProjection/GoalPhase are domain models.
Adapter wires goal.create/pause/resume/complete/clear; state comes from projection key=goal.
Goal state is session-scoped.


## Background Jobs
session/jobs mux frames fold into TimelineItem.Jobs. Jobs are live snapshots, not durable history.
