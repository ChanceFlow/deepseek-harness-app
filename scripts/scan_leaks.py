#!/usr/bin/env python3
"""Leak scanner for git hooks and the publish pipeline.

Two independent concerns:

1. SECRET mode (default) — real credentials that must never be committed
   anywhere: provider API keys (AWS/GitHub/GitLab/OpenAI-style), PEM private
   keys, high-entropy bearer tokens. This is the internal-repo gate: LAN
   addresses and personal paths are legitimate there, so they are NOT
   flagged.

2. PUBLIC mode — everything SECRET flags PLUS the internal-infrastructure
   and personal signatures that would leak when the repo is published
   (LAN IPs, ACT runner naming, proxy vars, personal mailbox fragments,
   absolute personal paths). This is the gate for the public clone and for
   any push whose remote URL contains github.com.

Inputs (one per run):
  --staged            scan lines ADDED in `git diff --cached`
  --commits=OLD..NEW  scan commit messages + added lines in that range
  --tree              scan the working tree (skips .git, reference/, publish-prep/)

Patterns are maintained HERE as the single source of truth; the publish
pipeline (`prepare_public_repo.sh`) delegates its sweeps to this script
instead of carrying duplicate greps.

Exit code 0 = clean, 1 = findings (each printed as path:line:match).
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# --- secret patterns (both modes) --------------------------------------------
SECRET_RE = [
    # provider API keys / tokens with enough entropy to skip test fixtures
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "AWS access key"),
    (re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\b"), "GitHub token"),
    (re.compile(r"\bgithub_pat_[A-Za-z0-9_]{22,}\b"), "GitHub fine-grained PAT"),
    (re.compile(r"\bglpat-[A-Za-z0-9_\-]{20,}\b"), "GitLab token"),
    (re.compile(r"\bxox[baprs]-[A-Za-z0-9\-]{10,}\b"), "Slack token"),
    (re.compile(r"\bsk-[A-Za-z0-9]{24,}\b"), "OpenAI/DeepSeek-style API key"),
    (re.compile(r"\bAIza[0-9A-Za-z_\-]{35}\b"), "Google API key"),
    (re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----"), "PEM private key"),
]

# --- public-mode additions (internal infra + personal signatures) ------------
# Mirrors the publish pipeline sweep: LAN 10.10.0.x, ACT runner naming,
# proxy var name, personal mailbox fragment, absolute personal paths,
# Gitea references. Kept as a combined regex string for one-flag reporting.
PUBLIC_EXTRA = re.compile(
    # legacy signatures that must stay hidden — NOT the public identity
    # (ChanceFlow <user@example.com>) which is expected in author
    # and tagger fields by design.
    r"10\.10\.0\.|runner|EGRESS_PROXY|/home/user|"
    r"gulugulu1103@qq\.com|chance@10\.10\.0\.1|"
    r"@10\.10\.0\.1|[Gg]itea"
)

SKIP_DIRS = {".git", "reference", "publish-prep", "build", ".dart_tool", ".gradle"}
# Detector files carry the patterns they detect — standard practice is to
# exempt the scanner itself (gitleaks allowlists its own config too).
SKIP_FILES = {"scripts/scan_leaks.py", "scripts/gitleaks.toml"}


def scan_text(text: str, mode: str) -> list[tuple[str, str]]:
    """Return (pattern-kind, matched-fragment) for every hit in text."""
    hits: list[tuple[str, str]] = []
    for rx, kind in SECRET_RE:
        for m in rx.finditer(text):
            frag = m.group(0)
            hits.append((f"{kind}: {frag[:40]}", frag))
    if mode == "public":
        for m in PUBLIC_EXTRA.finditer(text):
            hits.append(("internal/personal signature", m.group(0)))
    return hits


def git_stdout(args: list[str]) -> str:
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def scan_staged(mode: str) -> int:
    """Scan lines added in the staged diff (pre-commit)."""
    diff = git_stdout(["git", "diff", "--cached", "--unified=0"])
    findings = 0
    path = "(stage)"
    skip_file = False
    line_no = 0
    for raw in diff.splitlines():
        line = raw
        if line.startswith("diff --git"):
            skip_file = False
            continue
        if line.startswith("+++ b/"):
            path = line[6:]
            skip_file = path in SKIP_FILES
            continue
        if line.startswith("@@ "):
            m = re.search(r"\+(\d+)(?:,\d+)? ", line)
            line_no = int(m.group(1)) if m else 0
            continue
        if line.startswith("+") and not line.startswith("+++"):
            line_no += 1
            if skip_file:
                continue
            for kind, frag in scan_text(line[1:], mode):
                print(f"{path}:{line_no}:{kind} [{frag}]")
                findings += 1
    return 1 if findings else 0


def scan_commits(old: str, new: str, mode: str) -> int:
    """Scan messages + added lines in old..new (pre-push)."""
    if old == new:
        return 0
    findings = 0
    revs = git_stdout(["git", "rev-list", f"{old}..{new}"]).split()
    for sha in revs:
        body = git_stdout(["git", "show", "-s", "--format=%B", sha])
        for kind, frag in scan_text(body, mode):
            print(f"{sha[:12]}(message):{kind} [{frag}]")
            findings += 1
        diff = git_stdout(["git", "show", "--format=", "--unified=0", sha])
        path = "(diff)"
        line_no = 0
        for raw in diff.splitlines():
            line = raw
            if line.startswith("+++ b/"):
                path = line[6:]
                continue
            if line.startswith("@@ "):
                m = re.search(r"\+(\d+)(?:,\d+)? ", line)
                line_no = int(m.group(1)) if m else 0
                continue
            if line.startswith("+") and not line.startswith("+++"):
                line_no += 1
                for kind, frag in scan_text(line[1:], mode):
                    print(f"{sha[:12]}:{path}:{line_no}:{kind} [{frag}]")
                    findings += 1
    return 1 if findings else 0


def scan_all_blobs(mode: str) -> int:
    """Scan EVERY unique blob in the whole history (the comprehensive gate).

    Diff-based scans (`git show --unified=0`) only see CHANGED lines, so a
    leak sitting in old blob content that no later commit touched stays
    invisible. `--all-blobs` walks `git rev-list --objects --all` and cats
    every unique blob once — the only view that proves the history itself
    is clean. Use it in the publish pipeline's history sweep.
    """
    findings = 0
    # sha -> first path seen
    blob_paths: dict[str, str] = {}
    objs = git_stdout(["git", "rev-list", "--objects", "--all"])
    for line in objs.splitlines():
        parts = line.split()
        if len(parts) >= 2:
            blob_paths.setdefault(parts[0], parts[1])

    # batch cat-file the unique blob set
    blobs = sorted(blob_paths)
    if not blobs:
        return 0
    cat = subprocess.run(
        ["git", "cat-file", "--batch"],
        input=("".join(b + "\n" for b in blobs)).encode(),
        capture_output=True,
    )
    out = cat.stdout
    pos = 0
    for blob in blobs:
        header_end = out.find(b"\n", pos)
        if header_end == -1:
            break
        size = int(out[pos + 1 : header_end].split()[2])  # "<sha> blob <size>"
        data = out[header_end + 1 : header_end + 1 + size]
        pos = header_end + 1 + size + 1  # skip trailing \n
        if b"\x00" in data[:2048]:
            continue
        if blob_paths.get(blob) in SKIP_FILES:
            continue
        text = data.decode("utf-8", errors="replace")
        for kind, frag in scan_text(text, mode):
            print(f"blob {blob[:12]} ({blob_paths[blob]}):{kind} [{frag}]")
            findings += 1
            break
    return 1 if findings else 0


def scan_tree(mode: str) -> int:
    """Scan the working tree, skipping submodule/private dirs (pipeline use)."""
    findings = 0
    for p in sorted(REPO.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(REPO)
        if any(part in SKIP_DIRS for part in rel.parts):
            continue
        if str(rel) in SKIP_FILES:
            continue
        # text-ish only
        try:
            data = p.read_bytes()
        except OSError:
            continue
        if b"\x00" in data[:2048]:
            continue
        text = data.decode("utf-8", errors="replace")
        for kind, frag in scan_text(text, mode):
            print(f"{rel}:{kind} [{frag}]")
            findings += 1
            break  # one line per file is enough for a gate
    return 1 if findings else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--mode", choices=["secret", "public"], default="secret")
    ap.add_argument("--staged", action="store_true")
    ap.add_argument("--commits")
    ap.add_argument("--all-blobs", action="store_true")
    ap.add_argument("--tree", action="store_true")
    args = ap.parse_args()

    if args.staged:
        return scan_staged(args.mode)
    if args.commits:
        old, _, new = args.commits.partition("..")
        return scan_commits(old, new, args.mode)
    if args.all_blobs:
        return scan_all_blobs(args.mode)
    if args.tree:
        return scan_tree(args.mode)
    ap.error("one of --staged, --commits, --all-blobs, --tree is required")


if __name__ == "__main__":
    sys.exit(main())