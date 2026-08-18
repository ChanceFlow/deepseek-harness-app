# deepseek-harness-android

Kotlin-native Android client for DeepSeek Harness.

## Goals

- 100% Kotlin + Jetpack Compose. No WebView UI, no React Native, no server-driven UI.
- UI spatial layout is fully owned by Android code and can be rearranged freely.
- dsh harness concepts are isolated in `:core:harness-adapter`; UI code only sees neutral domain models.
- The dsh backend stays unchanged. Translation happens client-side inside the adapter module.

## Module boundaries

```text
app                    Kotlin/Compose UI. May only read :core:domain.
core:domain            Neutral UI-facing models: ChatMessage, Session, TimelineItem.
core:harness-adapter   The ONLY module that understands dsh wire protocol.
core:network           Transport primitives: RPC envelopes, HTTP/WebSocket seams.
```

Dependency direction:

```text
app -> :core:domain
app -> assembly wiring
:core:harness-adapter -> :core:domain
:core:harness-adapter -> :core:network
```

Forbidden import: `app` or `:core:domain` must never import from `:core:harness-adapter` or
any dsh type such as `SessionEvent`, `MuxFrame`, or `HostFrame`.

## Backend reference

The upstream dsh repository is pinned as a git submodule in
[`reference/deepseek-harness`](reference/). It is referenced through a git
submodule URL, not a filesystem symlink.

See [reference/README.md](reference/README.md) for details and the source-of-truth contract files.

## Project skills

This repository ships 29 project-scoped Agent Skills in [`.agents/skills/`](.agents/skills/),
vendored from [GuillemRoca/agent-skills-android](https://github.com/GuillemRoca/agent-skills-android)
(MIT). They are installed as plain skills (not a plugin). See
[`.agents/skills/README.md`](.agents/skills/README.md) for the full list and
how to refresh them.

## Development

Build and test from the repository root:

```sh
./gradlew :app:testDebugUnitTest :core:network:test :core:harness-adapter:test
./gradlew :app:assembleDebug
```

The default base URL is `http://10.0.2.2:3080`. Override it for a physical
device or a LAN host:

```sh
./gradlew :app:assembleDebug -PDSH_BASE_URL=http://192.168.1.10:3080
```

A local dev server can be reached with:

```sh
adb reverse tcp:3080 tcp:3080
pnpm dsh web --port 3080
```

## Kotlin best practices

See [docs/kotlin-best-practices.md](docs/kotlin-best-practices.md) for the rules this repository follows.
- Android MVP specification: [docs/spec.md](docs/spec.md)

- Hilt constructor injection in `:app`
- MVVM + UDF + `StateFlow`
- stateless Compose screens with a stateful `ChatRoute`
- anti-corruption layer in `:core:harness-adapter`
- JVM tests for the ViewModel

## Current status

The MVP client is wired end-to-end against a running `dsh web` host:

- `:core:network` — JSON-RPC envelopes over OkHttp plus the two downlink-only
  WebSocket streams (`/api/events.mux`, `/api/events.host`).
- `:core:harness-adapter` — connection generations with exponential backoff
  (injectable dispatcher and retry-policy seams), reconnect resync, buffered
  frame replay, history/timeline folding, local host-frame workspace updates,
  and the complete unary method set used by the MVP.
- `:app` — stateless Compose screens for Chat, Workspaces, Models, Subagents,
  Goals, and Settings. Chat supports session search/create/rename/archive/fork,
  queue text edit/steer/remove (including Queue/Steer composer delivery),
  approvals, custom, multi-select, and skippable questions (plan-review
intents render a decision card with the markdown plan body and a primary
approve action), live titles,
  goals (create/pause/resume/edit/complete/clear), background jobs, and
page-at-a-time older-history loading, and a ledger-style trajectory outline —
`turn/start` events fold into collapsible turn groups (message/tool counts
per turn, expand-all restore) beside the flat timeline view. Message bodies
render markdown
(fenced code with language label and streaming-open fences, headings, nested
bullet lists, block quotes, pipe tables, inline code, bold/italic, and
clickable links) through a pure-Kotlin parser with theme-owned Compose
styling. Queue rows edit into a previewable dialog that never dispatches a
blank text. The composer attaches
images (photo picker, host `imageLimits` projection gating type/size/count,
decoded thumbnails on the pending chips) that ride the prompt as inline
parts, and timeline image blocks download lazily through `session.attachment`
with a retry on failure. The chat header mirrors the `plan` session
projection
(active/pending; `/plan` in the composer toggles it), and the composer offers
the session's skill catalog as `/` slash candidates (one `skill.list` per
session, cached; picking lands the literal `/name ` text). Workspaces gain an
in-app directory browser (`host.listDirectory`/`host.createDirectory`) and
durable manual reordering (`workspace.insertBefore`), and Settings renders
the settings overview with per-namespace one-key patching (`settings.update`
with revision CAS for writable hosts) plus credential management — describe,
store (`credentials.set`), and clear (`credentials.unset`) for writable
refs; the host serves the whole plane only to loopback connections.

Still deferred, matching [docs/spec.md](docs/spec.md): schema-driven
settings forms and full-namespace replace/mutate, plugin and skill
management, rich plan/trajectory rendering, and attachment downsampling.

Verification: the normal JVM suite (`app` ViewModel, envelope,
TimelineReducer, ConnectionManager fake transport, Hermetic
HarnessRepository fake-host integration) passes with zero failures. The
opt-in `LocalDshE2eTest` also passes against a real local `dsh web` when run
with `DSH_E2E_URL=http://127.0.0.1:3080`.
