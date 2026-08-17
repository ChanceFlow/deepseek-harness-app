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
- `:core:harness-adapter` — connection generations with exponential backoff,
  reconnect resync, buffered frame replay, history/timeline folding, and the
  complete unary method set used by the MVP.
- `:app` — stateless Compose screens for Chat, Workspaces, Models, Subagents,
  and Goals. Chat supports session search/create/rename/archive/fork, queue
  steer and remove (including Queue/Steer composer delivery), approvals,
  custom and multi-select questions, live titles, goals, background jobs, and
  page-at-a-time older-history loading.

Still deferred, matching [docs/spec.md](docs/spec.md): settings/credentials,
attachment uploads, markdown and trajectory/plan rendering, and manual
workspace ordering.
