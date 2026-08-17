# Kotlin best practices for this repository

## Build

- All dependency and plugin versions live in `gradle/libs.versions.toml`; no module hardcodes versions.
- Gradle scripts use Kotlin DSL.
- Module dependencies are explicit: a source file may only import from modules declared in `build.gradle.kts`.

## Module rules

- `:core:domain`: neutral Kotlin models. Coroutines allowed; Android UI and dsh types are not allowed.
- `:core:network`: transport only. May understand JSON-RPC envelopes and OkHttp/WebSocket mechanics.
- `:core:harness-adapter`: anti-corruption layer. The only module allowed to know dsh method names and event shapes.
- `:app`: Compose UI. Consumes `:core:domain`; never imports dsh DTOs or event names.

## Language

- Prefer immutable `data class` values and `sealed interface` closed unions.
- Public APIs use explicit types; implementation details stay `private`.
- Do not expose `MutableStateFlow` from a ViewModel.
- Suspend functions must rethrow `CancellationException`; never swallow it into a generic error state.

## Compose

- Stateful route wrappers own the ViewModel.
- Reusable composables are stateless: they receive state and action lambdas.
- Screen-wide state lives in `ChatUiState`; only transient local artifacts such as text-field draft may stay in `remember`.
- Layout choices such as Row/Column split, padding, and pane widths belong to `:app`.
- Add `@Preview` for visual components and keep preview data free of network calls.

## Testing

- JVM unit tests use `StandardTestDispatcher` + `Dispatchers.setMain`.
- Repository fakes implement the domain contract, never the harness implementation.
