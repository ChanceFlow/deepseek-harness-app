# Agent Note: CI wall-clock flakes hardened to condition-bounded waits

Status: implemented

## Problem

Two integration tests bet on fixed wall-clock margins and flaked under CI
contention (single runner, full suite): `harness_repository_integration_test`
"streaming chunks coalesce" slept 24ms expecting a ~16ms coalescing timer to
have fired, and intermittently asserted with 1 of 2 window publishes;
`session_panel_backend_test` "tapping another backend's session" ran a fixed
8×20ms runAsync warm-up that starved the slower roster under load, so the
sidebar rendered half-loaded. Both passed in isolation and under the local
combined suite — the flakes surfaced on CI (#141's first code run) and a
local full-suite load run.

## Decision

Replace time bets with condition-bounded waits: poll until the observable
fact lands (the coalesced second publish arrives; both backends'
`Ungrouped` headers — which render only when a roster loaded, empty groups
are omitted), bounded (100×10ms / 30×20ms) so a genuine regression still
fails with a meaningful assertion right after the loop. Test files only;
production timing semantics unchanged.

## Alternatives considered

- **Enlarge the fixed margins**: rejected — moves the failure threshold,
  does not remove the race, and slows real regressions.
- **Fake timers/`testUsingContext`**: the adapter tests drive a real
  `dart:io`-backed socket script; injecting a clock harness is a much wider
  surgery than the flake justifies.

## Consequences

- CI red on these two names now means a real regression (the post-loop
  assertions still pin exact publish counts and rendered titles).
- If the widget harness ever grows a virtual-clock mode, these loops can
  collapse to single deterministic pumps.
