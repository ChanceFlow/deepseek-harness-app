#!/usr/bin/env bash
# Staged leak scan (lefthook pre-commit job) — authoritative gitleaks scan
# of the STAGED diff only, using this repo's gitleaks config (default
# ruleset + the repo-specific signatures + allowlists). The shared history
# must always be public-clean, so the full config applies to every commit,
# on either forge.
#
# Escape hatch for exceptional local experiments:
#   git config leakscan.mode off
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"

[ "$(git config --get leakscan.mode || true)" = off ] && exit 0

if command -v gitleaks >/dev/null 2>&1; then
  gitleaks protect --staged --config "$ROOT/scripts/gitleaks.toml" --no-banner \
    || { echo; echo "pre-commit: gitleaks found leaks in the staged diff — fix before committing."; exit 1; }
else
  python3 "$ROOT/scripts/scan_leaks.py" --staged --mode=public \
    || { echo; echo "pre-commit: leak scan failed (install gitleaks for the authoritative scan)."; exit 1; }
fi