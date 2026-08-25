#!/usr/bin/env bash
# Identity guard (lefthook pre-commit job) — every commit's author AND
# committer must be exactly the published identity. See the commit-identity
# guard agent note for the full rationale.
#
# Escape hatch for exceptional local experiments:
#   git config identity.guard off
set -euo pipefail

[ "$(git config --get identity.guard || true)" = off ] && exit 0

EXPECT_ID="ChanceFlow <user@example.com>"
author="${GIT_AUTHOR_NAME:-$(git config user.name || true)} <${GIT_AUTHOR_EMAIL:-$(git config user.email || true)}>"
committer="${GIT_COMMITTER_NAME:-$(git config user.name || true)} <${GIT_COMMITTER_EMAIL:-$(git config user.email || true)}>"
if [ "$author" != "$EXPECT_ID" ] || [ "$committer" != "$EXPECT_ID" ]; then
  echo "pre-commit: identity guard — this history publishes under exactly one identity."
  echo "  expected author and committer: $EXPECT_ID"
  echo "  got author:    $author"
  echo "  got committer: $committer"
  echo "Fix: git config user.name 'ChanceFlow' && git config user.email user@example.com"
  echo "(or 'git config identity.guard off' for an exceptional local experiment)"
  exit 1
fi