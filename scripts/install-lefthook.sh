#!/usr/bin/env bash
# Install lefthook git hooks into this repository.
#
# Downloads the pinned lefthook binary (single static binary, no runtime
# deps) and installs the lefthook-managed hooks. See lefthook.yml for the
# hook jobs; CI runs the full gate matrix (scripts/verify_all.py) itself and
# does not need this.
#
# Usage:
#   scripts/install-lefthook.sh
#
# Env:
#   LEFTHOOK_BIN   directory to install the binary into (default ~/.local/bin)
#   LEFTHOOK_VERSION  override the pinned version
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${LEFTHOOK_VERSION:-2.1.11}"
BIN_DIR="${LEFTHOOK_BIN:-$HOME/.local/bin}"
BIN="$BIN_DIR/lefthook"

if command -v lefthook >/dev/null 2>&1 && [ "$(lefthook version 2>/dev/null || true)" = "$VERSION" ]; then
  echo "lefthook $VERSION already on PATH"
else
  OS="$(uname -s)"
  ARCH="$(uname -m)"
  case "$OS" in
    Linux)  GOOS="linux" ;;
    Darwin) GOOS="darwin" ;;
    *) echo "unsupported OS: $OS (only Linux/Darwin)" >&2; exit 1 ;;
  esac
  case "$ARCH" in
    x86_64|amd64) GOARCH="x86_64" ;;
    aarch64|arm64) GOARCH="aarch64" ;;
    *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
  esac

  URL="https://github.com/evilmartians/lefthook/releases/download/v${VERSION}/lefthook_${VERSION}_${GOOS}_${GOARCH}.gz"
  mkdir -p "$BIN_DIR"
  tmp="$(mktemp -d)"
  echo "downloading lefthook $VERSION ($GOOS/$GOARCH) -> $BIN_DIR"
  curl -fsSL --max-time 120 -o "$tmp/lefthook.gz" "$URL"
  gunzip -f "$tmp/lefthook.gz"
  chmod +x "$tmp/lefthook"
  mv "$tmp/lefthook" "$BIN"
  rmdir "$tmp" 2>/dev/null || true
fi

# Migrate away from the historical core.hooksPath -> scripts/git-hooks setup:
# lefthook installs its wrappers into .git/hooks, which git ignores while
# core.hooksPath points elsewhere. Only unset it when it targets the legacy
# directory, never a user's custom path.
LEGACY_HOOKS_PATH="$(git config --get core.hooksPath || true)"
if [ "$LEGACY_HOOKS_PATH" = "scripts/git-hooks" ]; then
  git config --unset core.hooksPath
  echo "unset legacy core.hooksPath (scripts/git-hooks)"
fi

command -v lefthook >/dev/null 2>&1 || export PATH="$BIN_DIR:$PATH"
(
  cd "$ROOT"
  lefthook install
)
echo "lefthook hooks installed"