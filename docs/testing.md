# Testing policy: verify the world, not the self-report

Agents optimize what the check measures and report success in prose unless
the environment contradicts them. These tiers are that environment.

## Rules

1. **Assert external state.** Found widgets, decoded `domain` objects,
   rendered text, thrown errors — never a re-encoding of the input or a
   flag the code under test sets about itself.
2. **Drive the real entry path.** Widget tests pump real widget trees with
   real controllers; adapter tests decode fixture JSON through the real
   decoders and folds in `packages/harness_adapter`. Hand-mounted fakes of
   the wiring under test are forbidden — they pass while the product is
   broken.
3. **Fixtures come from the wire.** Record JSON from the reference web
   client or transcribe it from the reference submodule contract files
   ([reference/README.md](../reference/README.md)); cite the source path in
   the fixture. Invented payloads test imagination, not the contract.
4. **Prove failure modes.** Every fail-loud decoder has a negative fixture
   (required field absent → throws with the field name); every collapsible
   or disposable interaction has a test that observes the collapsed/removed
   state.
5. **Self-skip credential tiers.** Tests needing a live host read
   `DSH_E2E_URL` and skip with a printed reason when it is unset — CI stays
   green without secrets, and the tier still runs locally
   ([README §Opt-in real-host e2e](../README.md#opt-in-real-host-e2e)).

## Tiers

| Tier | What it is | Runs |
|---|---|---|
| Unit | Pure Dart: domain models, markdown parser, folds | Every change touching them |
| Widget | Real widget trees per screen, controller-fed | Every `flutter/app` UI change |
| Adapter fixture | Recorded wire JSON through real decoders | Every `harness_adapter` change |
| Real-host e2e | Live `dsh web` host via `DSH_E2_URL`, asserts observable session state | Opt-in, provider-affecting changes |
| Build smoke | `flutter build apk --debug` | Release-critical changes; not in the aggregate |

## Select evidence by surface

Run the narrowest check that would fail for your regression; the full
matrix belongs to `python3 scripts/verify_all.py` (all) at close-out and to
CI:

- Behavior of one module → its focused test file (`flutter test <path>`
  from `flutter/`).
- Anything model- or user-visible (theme tokens, rendered text, wire
  coverage counts) → the owning test plus `verify_all.py docs` where a doc
  states the contract.
- Docs/instructions only → `python3 scripts/verify_all.py docs`.
- Structural or cross-package change → the full aggregate.

## Review bar

A test passes review when deleting the code under test makes it fail —
mutate once and watch. Coverage percentage is not a target; a missing
failure-mode assertion is a defect regardless of the number.
