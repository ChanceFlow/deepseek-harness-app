#!/usr/bin/env bash
# Push leak scan (lefthook pre-push job) — authoritative leak gate on the
# commits being pushed, using this repo's gitleaks config (default ruleset
# + repo-specific signatures + allowlists). The shared history must always
# be public-clean, so the full config applies to every push, to either
# forge.
#
# Escape hatch for exceptional local experiments:
#   git config leakscan.mode off
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"

[ "$(git config --get leakscan.mode || true)" = off ] && exit 0

fail=0
while read -r local_ref local_sha remote_ref remote_sha; do
  [ "$local_sha" = "$remote_sha" ] && continue

  if [ "$remote_sha" = "0000000000000000000000000000000000000000" ]; then
    # New branch: scan every commit reachable from the branch tip that is
    # not already reachable from any known remote ref (^-negation form —
    # the --not flag form misparses in some shells).
    opts="$local_sha $(git for-each-ref --format='%(refname)' refs/remotes | sed 's/^/^/')"
  else
    opts="$remote_sha..$local_sha"
  fi

  if command -v gitleaks >/dev/null 2>&1; then
    ( cd "$ROOT" && gitleaks detect --log-opts="$opts" --config scripts/gitleaks.toml --no-banner -s . ) \
      || { echo; echo "pre-push: gitleaks found leaks in $local_ref — fix before pushing."; fail=1; }
  else
    python3 "$ROOT/scripts/scan_leaks.py" --commits="$opts" --mode=public \
      || { echo; echo "pre-push: leak scan failed for $local_ref (install gitleaks for the authoritative scan)."; fail=1; }
  fi
done < /dev/stdin

exit $fail