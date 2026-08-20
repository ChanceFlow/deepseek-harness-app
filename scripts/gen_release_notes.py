#!/usr/bin/env python3
"""Generate a release-notes changelog from the repository's merge commits.

release-please style: merged pull-request titles are grouped by their
Conventional Commit type (feat/fix/docs/...), each entry linked to its
pull request on the forge. The range is "since the newest stable v* tag
reachable from --head" (prerelease suffixes excluded, --exclude-tag
skipped) — the same baseline the APK workflow uses to derive the next
alpha version — or from the root commit when no previous stable tag
exists (a first release lists everything ever merged).

The APK release workflow
(.gitea/workflows/release-apk.yaml) runs this to build the Gitea Release
body: the changelog is prepended under a "What's Changed" heading, with
the artifact metadata block following.

Prints markdown to stdout; prints nothing when there are no pull-request
merges in the range.

Usage:
  gen_release_notes.py --repo . --head <sha> [--exclude-tag <tag>] \
      --base <forge-base>
"""

import argparse
import re
import subprocess
import sys

# "Merge pull request 'feat(scope): title' (#12) from branch into master"
_MERGE = re.compile(r"^Merge pull request '(?P<title>.+)' \(#(?P<num>\d+)\)")
# Conventional Commit: type(scope): subject
_CONVENTIONAL = re.compile(
    r"^(?P<type>[A-Za-z]+)(?:\((?P<scope>[^)]*)\))?:\s*(?P<subject>.+)$"
)
# prerelease suffix, e.g. v0.1.0-alpha.1 / -beta.2 / -rc.3 / -dev.7
_PRERELEASE = re.compile(r"-(?:alpha|beta|rc|dev)[.]?[0-9]*$")

GROUPS = [
    ("✨ Features", {"feat"}),
    ("🐛 Bug Fixes", {"fix", "bugfix"}),
    ("⚡ Performance", {"perf"}),
    ("♻️ Refactors", {"refactor"}),
    ("📝 Documentation", {"docs", "doc"}),
    ("🧪 Tests", {"test", "tests"}),
    ("🔧 Chores", {"chore", "build", "ci", "deps", "style"}),
]
FALLBACK = "📦 Other"


def _git(repo: str, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", repo, *args], capture_output=True, text=True, check=True
    ).stdout


def latest_stable_tag(repo: str, head: str, exclude: str | None) -> str | None:
    """Newest stable v* tag (prerelease excluded) that is an ancestor of head."""
    tags = _git(repo, "tag", "-l", "v*", "--sort=-v:refname").splitlines()
    for tag in tags:
        if _PRERELEASE.search(tag) or tag == exclude:
            continue
        probe = subprocess.run(
            ["git", "-C", repo, "merge-base", "--is-ancestor", tag, head],
            capture_output=True,
            text=True,
        )
        if probe.returncode == 0:
            return tag
    return None


def merge_subjects(repo: str, since: str | None, head: str) -> list[str]:
    if since is not None:
        spec = f"{since}..{head}"
    else:
        root = _git(repo, "rev-list", "--max-parents=0", "HEAD").splitlines()[0]
        spec = f"{root}..{head}"
    return _git(repo, "log", "--merges", "--format=%s", spec).splitlines()


def parse(subject: str) -> dict | None:
    """Split a merge-commit subject into a changelog entry; None = noise."""
    match = _MERGE.match(subject)
    if match is None:
        return None  # "Merge remote-tracking branch ..." and non-PR merges
    raw = match.group("title")
    number = match.group("num")
    conv = _CONVENTIONAL.match(raw)
    if conv is not None:
        return {
            "type": conv.group("type").lower(),
            "scope": conv.group("scope"),
            "subject": conv.group("subject"),
            "num": number,
        }
    return {"type": None, "scope": None, "subject": raw, "num": number}


def _entry_line(entry: dict, base: str) -> str:
    link = f"[#{entry['num']}]({base}/pulls/{entry['num']})"
    if entry["scope"]:
        return f"- **{entry['scope']}:** {entry['subject']} ({link})"
    return f"- {entry['subject']} ({link})"


def render(entries: list[dict], base: str) -> str:
    buckets: dict[str, list[dict]] = {name: [] for name, _ in GROUPS}
    fallback: list[dict] = []
    for entry in entries:
        placed = False
        for name, kinds in GROUPS:
            if entry["type"] in kinds:
                buckets[name].append(entry)
                placed = True
                break
        if not placed:
            fallback.append(entry)

    lines: list[str] = []
    for name, _ in GROUPS:
        if buckets[name]:
            lines.append(f"### {name}")
            lines.extend(_entry_line(e, base) for e in buckets[name])
            lines.append("")
    if fallback:
        lines.append(f"### {FALLBACK}")
        lines.extend(_entry_line(e, base) for e in fallback)
        lines.append("")
    return "\n".join(lines).rstrip("\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=".", help="path to the git repository")
    parser.add_argument("--head", required=True, help="commit the release is built at")
    parser.add_argument(
        "--exclude-tag",
        default="",
        help="stable v* tag to skip (the release being created); empty = none",
    )
    parser.add_argument(
        "--base",
        required=True,
        help="forge base URL for pull-request links, e.g. http://host/owner/repo",
    )
    args = parser.parse_args()

    since = latest_stable_tag(args.repo, args.head, args.exclude_tag or None)
    entries = [e for e in (parse(s) for s in merge_subjects(args.repo, since, args.head)) if e]
    sys.stdout.write(render(entries, args.base))
    return 0


if __name__ == "__main__":
    sys.exit(main())
