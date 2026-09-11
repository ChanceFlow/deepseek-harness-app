# Agent Note: provider and model administration, and an About surface

Status: implemented

## Problem

Settings could only *select* a model from the session-scoped catalog. A phone
user could not add a provider, store its API key, remove a stored profile, or
ask an endpoint which models it serves — the Settings → Models card rendered a
read-only notice next to the DeepSeek key. The client's endpoint registry
(`DshRpcEndpoints`) declared no `llm/*` method, so the surface did not exist
below the UI either.

An earlier probe of a live host assumed the 0.1.1-era dotted names and got a
404 for `llm/providers`. The 0.1.5 contract registers `LlmRuntime` as a Typert
Remote service under the bare key `llm`
(`reference/deepseek-harness/packages/llm/llm/src/index.ts`), exposing three
unary methods: `llm/listProviders`, `llm/listConfigurableProviders`, and
`llm/discoverModels`. All three answer on the pinned host.

Settings also had no version, documentation, or feedback affordance.

## Decision

**Wire.** `rpc_map.dart` gains the three endpoint constants in its one
registry. Their result values are bare JSON arrays, which
`RpcResult.fromJson` parks under `value`
(`packages/network/lib/rpc_envelope.dart`), so the hand-written decoders live
in `harness_adapter/lib/src/wire_json.dart` beside the required-field
helpers rather than in `dsh_wire_types.dart`, whose decoders all read object
results. `LlmProviderInfoWire` requires `id`/`name`;
`LlmConfigurableProviderWire` requires `provider`/`displayName`/`settingsNs`
and a string-list `settingsPath`, with `declared`/`error` optional;
`LlmDiscoveredModelWire` requires only `id`. A missing or mistyped required
field throws a `FormatException` naming the field.

**Domain.** `packages/domain/lib/model/llm_provider.dart` carries
`LlmProvider`, `LlmConfigurableProvider`, `LlmProviderRow`,
`LlmModelDiscoveryRequest`, `LlmDiscoveredModel`, and the pure
`joinProviderDirectory`/`providerKeyRef`/`providerFamilies`/`providerPathFor`
projections. `ChatRepository` gains `listLlmProviders`,
`listConfigurableProviders`, and `discoverModels`. `SettingsNamespace` gains
the redacted `value` and `user` layers the directory join reads; the adapter
already decoded both.

**Discovery carries no secret.** `LlmModelDiscoveryRequest` models only
`provider`, `baseURL`, and `api`. The wire request also accepts a one-shot
`apiKey`, and this client never populates it: a configured route names its
route and the host resolves the stored credential
(`dsh-llm-pi-ai/src/discovery.ts` `storedDiscoveryProfile`). A key literal
therefore never rides a request, the error log, or telemetry, and the key
field is `obscureText`.

**Key path.** Storing a key reuses the existing credential plane exactly as
the reference provider editor does: `credentials.set(ref, value)` first, then
`settings.mutate` writes `apiKeyEnv: <ref>` at the profile path when the
profile names no reference. Clearing calls `credentials.unset(ref)` and
leaves the profile. Adding a provider writes one `set` profile op at
`[...familyPrefix, route]` and then stores the key; removing writes one
`unset` at the profile path, offered only when the user layer carries it.

**UI.** `app/lib/ui/settings/llm_providers.dart` holds the controller, its
UDF state, the action union, the section, and both sheets;
`app/lib/ui/settings/about_section.dart` holds the About card. Both are
self-contained because `settings_screen.dart` is owned by another change this
round; the two one-line mounts are reported to that owner instead of edited
in. Cards ride `Material` rather than a decorated `Container` so row ink
paints on the card.

## Alternatives considered

Generating the DTOs with `freezed`/`json_serializable` was rejected: codegen
is a settled non-goal (ADR-0001, `docs/spec.md` §Non-Goals). Hard-coding the
pi-ai protocol list in the add sheet was rejected: it would drift from the
adapter's `supportedProtocols()`, so the field stays free text and the host's
own diagnostic reports an unusable value. Passing the typed key into
`discoverModels` for a brand-new route — the contract's intended path for a
route with no stored profile — was rejected to keep a secret out of a
client-built request; a hand-declared route instead requires at least one
model id, which the profile contract already demands. Editing
`settings_screen.dart` to mount directly was rejected because another change
owns the file.

## Consequences

The client wires 49 of the 84 Remote methods the pinned tree registers; the
coverage block in `docs/spec.md` §4.6 and the README sentence move with it in
this change. The Models & Credentials footer still says custom providers are
host-managed, and its assertion in `settings_screen_test.dart` pins that
text: whoever mounts this section updates `modelsFooter` (both locales) and
that assertion in the same change, because the claim is only true while the
Providers section is unmounted. A hand-declared route still needs a model id
(or a discovered catalog) before the host accepts its profile; the host's
refusal surfaces in the sheet. Removing a provider leaves its stored
credential, so a re-added route finds its key again.
