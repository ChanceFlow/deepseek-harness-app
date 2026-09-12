# Agent Note: A gate runs the resolved workspace, it does not resolve one

Status: implemented

## Problem

The aggregate's two Flutter gates ran bare `flutter analyze` and `flutter test`.
Those commands resolve the workspace themselves when the package config is
missing or stale, which makes a gate that is supposed to inspect the tree also
a network client. Two ways that bites:

- On a host whose egress is unavailable or proxied through an address that only
  means something outside the container — the default here — the gate dies with
  `Failed to update packages` (exit 69) instead of reporting anything about the
  code. Measured while checking this repository's own gates from a sandbox.
- A resolve that stalls does not time out. This repository has already paid for
  that twice: a job sat on `Resolving dependencies...` for 1h49m, and another
  spent its whole 1800s ceiling on the same line.

Every workflow already resolves once, on purpose, at a named step with a bound
and a retry, precisely so the gates' own resolves become no-ops. The gate was
still free to ignore that and reach the network anyway.

## Decision

- **Both gates pass `--no-pub`.** They run the workspace the resolve step
  produced and fail fast when there is nothing to run, naming the remedy.
- **Offline is now a supported local path.** The image carries the resolved
  package set, so `scripts/flutter.sh pub get --offline` settles the workspace
  with no network at all, and `verify_all.py code` then runs green from it:
  measured, all five gates, with egress unavailable.

## Alternatives considered

- **Leave the commands bare.** Rejected: it keeps a gate's result dependent on
  the network and on a resolve that can hang indefinitely, for no gain — the
  workflows resolve immediately before anyway.
- **Check for `.dart_tool/package_config.json` in the gate first.** Rejected as
  incomplete: it catches a missing config but not a stale one, and a stale
  config still triggers the implicit resolve this change exists to remove.
- **Resolve inside the gate with `pub get --offline`.** Rejected: it duplicates
  the workflow's bounded, retried resolve and hides which step owns the network.

## Consequences

A fresh checkout must be resolved before the aggregate runs — one
`scripts/flutter.sh pub get` (or `--offline`, which the image's warm cache
satisfies). A pubspec edited without re-resolving is now gated against the old
resolution rather than silently re-fetched; CI has no such window, because its
resolve is the step immediately before the gates.
