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

The first milestone is wiring, not feature completion:

1. Implement `DshRpcClient` and `DshEventSocket` against a local dsh web server.
2. Implement `HarnessAdapter` translation for the MVP event set.
3. Keep `ChatScreen` consuming only `ChatUiState` / domain models.

A local dev server can be reached with:

```sh
adb reverse tcp:3080 tcp:3080
pnpm dsh web --port 3080
```

## Kotlin best practices

See [docs/kotlin-best-practices.md](docs/kotlin-best-practices.md) for the rules this repository follows.

- Hilt constructor injection in `:app`
- MVVM + UDF + `StateFlow`
- stateless Compose screens with a stateful `ChatRoute`
- anti-corruption layer in `:core:harness-adapter`
- JVM tests for the ViewModel

## Current status

Skeleton plus transport/adapter contracts. The chat screen is still a preview path until the adapter wiring is completed. The checked-in UI is a placeholder preview; it does not call the backend yet.
