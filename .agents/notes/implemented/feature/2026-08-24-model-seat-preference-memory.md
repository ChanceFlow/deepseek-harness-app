# Agent Note: Remembered model-seat preferences

Status: implemented

## Problem

Every fresh session opened on the phone's composer model seat with the
host's default model and that model's default reasoning effort. The reader
who prefers another route — or the same model at `high` instead of the
default `low` — re-picked both on every new session, because nothing on
the client remembered the choice. The host persists a session's own
selection (a reopened session keeps its model), and the host-side
`agent-default-model` settings section can pin one route per deployment,
but neither carries a per-route effort preference, and the client seats a
new session from the host's current selection alone.

## Decision

The client remembers its own model-seat preferences in the device-local
[LocalStateStore](../../../../flutter/app/lib/local_state/local_state_store.dart)
document, scoped per backend (`chat.modelPrefs.<backendId>.*` — hosts own
different catalogs, so a route remembered on one must not land on
another's seat). [ChatController](../../../../flutter/app/lib/ui/chat/chat_controller.dart)
owns the memory:

- Every committed seat selection becomes the remembered last selection and
  overwrites its `provider/model` route's remembered effort
  (`ModelSeatPreferences.remembering`), persisted through the
  `ModelPreferencePersistence` seam wired per backend in
  [providers.dart](../../../../flutter/app/lib/di/providers.dart).
- A blank session's directory load applies the remembered selection when
  it differs from the host's current (web `agent-default-model` parity: a
  session that already ran keeps the selection the host logged for it).
  The apply runs once per session selection, waits for both the directory
  and the session summary, and a host refusal (route no longer served)
  stays silent with telemetry — the seat keeps the host's selection.
- Picking a model in the seat's sheet prefills that route's remembered
  effort instead of the model's default (web `selectionOf` parity); the
  effort pane's explicit rows are unaffected, so a deliberate "provider
  default" pick still wins.

## Alternatives considered

- **Write the host's `agent-default-model` settings section** through a
  settings RPC: rejected — it changes the deployment for every other
  client of that host, and it still has no per-route effort vocabulary.
- **Apply the remembered selection to every session, not just blank
  ones**: rejected — it fights the host's per-session persisted selection
  and would flip an old session's model on reopen.
- **Per-device global scope instead of per-backend**: rejected — a
  remembered route absent from another host's catalog turns every blank
  session there into a refused selection.

## Consequences

- A new session opens with the reader's usual model and effort with no
  re-picking; the remembered state survives app restarts and lands only
  on the backend it was chosen on.
- The seat's directory now loads for created and forked sessions too
  (previously only `SelectSession` loaded it, so those surfaces showed the
  previous session's model until reselection), and the sheet's open
  refresh (`onRefreshModels` → `ChatController.refreshModels`) is wired in
  production where it was a no-op.
- `ChatUiState.modelPrefs` publishes the memory for the sheet's prefill;
  null while persistence is absent or still resolving, in which case the
  seat behaves exactly as before.
