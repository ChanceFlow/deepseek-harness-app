# AGENTS.md — flutter/ (pub workspace)

Supplements the [root conventions](../AGENTS.md#conventions); only workspace
mechanics live here.

- **Workspace root owns the toolchain.** Flutter commands run from
  `flutter/`, inside the CI image: `scripts/flutter.sh test <pkg>` is the
  shortcut, and the workspace root has no `test/` of its own, so the full
  suite is `scripts/flutter.sh test app/test packages/domain/test
  packages/network/test packages/harness_adapter/test packages/dev/test`
  (bare `scripts/flutter.sh test <pkg>` covers one member). Pub workspace
  resolution and the shared `analysis_options.yaml` apply at this level
  ([analysis_options.yaml](analysis_options.yaml)).
- **Each member's rules live in its own delta file.** UI and aesthetic:
  [app/AGENTS.md](app/AGENTS.md); wire seam:
  [packages/harness_adapter/AGENTS.md](packages/harness_adapter/AGENTS.md);
  debug tooling: [packages/dev/AGENTS.md](packages/dev/AGENTS.md).
  `packages/domain` and `packages/network` carry no delta — the root rules
  and the import gate are their whole contract.
- **All packages resolve through the workspace.** Member `pubspec.yaml` files
  declare workspace membership; dependency edits update
  [pubspec.lock](pubspec.lock) in the same change.
- **Tests mirror `lib/` layout.** `test/` paths match `lib/` paths; widget
  tests live beside the screen they drive (per-screen parity is the goal, see
  [README §Feature surface](../README.md#feature-surface)).
- **No codegen toolchain.** No `build_runner`, no generated files; see the
  root [no-codegen rule](../AGENTS.md#conventions). One SDK-mandated
  exception: gen-l10n output under `app/lib/l10n/` is committed
  (Flutter 3.47 removed synthetic packages) — see
  [the i18n decision note](../.agents/notes/implemented/feature/2026-08-20-bilingual-i18n-zh-en.md).
- **Analyzer excludes are platform dirs only.** `build/`, `android/`, and
  other platform folders are excluded in
  [analysis_options.yaml](analysis_options.yaml); Dart code under `lib/` and
  `test/` is always analyzed.
