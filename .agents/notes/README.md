# Agent Notes — decision records

Agent sessions are stateless; this tree is the repository's memory. Every
non-trivial change updates at least one note **in the same change** — the note
that already owns the decision satisfies the rule; never duplicate.
Non-trivial = alters behavior, architecture, a cross-file contract,
process/tooling, testing strategy, or an on-disk/wire/config format.

## Tree

```text
.agents/notes/
├── proposed/      not yet built; future tense is legitimate
├── implemented/   shipped; present tense; kept current with reality
└── rejected/      declined; kept only while it prevents a real mistake
```

Path = `{lifecycle}/{class}/yyyy-mm-dd-topic.md`; the date is when the topic
was first proposed. Closed class set:

| Class | Covers |
|---|---|
| `feature` | New user-facing capability |
| `bug-fix` | Defect correction, postmortem follow-up |
| `simplification` | Removes code/behavior/surface without adding capability |
| `architecture` | Structural decision about shipped source |
| `process` | Tooling, policy, workflow — gates, CI, vendoring |
| `testing` | Test infrastructure and strategy |

## Format

First three lines exactly:

```markdown
# Agent Note: <title>

Status: <status>
```

`Status` is `proposed`, `implemented`, or `rejected — <why, one line>`, and
must agree with the lifecycle folder. Status carries no dates — the filename
and git hold those.

Required sections per lifecycle:

- `proposed/`: `## Problem`, `## Proposal`, `## Alternatives considered`,
  `## Acceptance criteria`, `## Risks`
- `implemented/`: `## Problem`, `## Decision`, `## Alternatives considered`,
  `## Consequences`
- `rejected/`: the proposal frozen, verdict on the `Status:` line

`## Alternatives considered` is mandatory in every lifecycle — a decision
recorded without what it beat invites re-litigation. Record real
alternatives; never invent them for format.

## Rules

- **Implemented notes stay current.** When code later moves a file or renames
  a key, the note updates in the same change — facts only, never the decision.
  Present tense throughout; no "should", no migration plans.
- **Supersession check on every new note.** Search the tree for notes covering
  the same decision; fully superseded ones consolidate (the new owner
  preserves every unique rationale and repairs inbound links); partial
  supersessions keep both, cross-linked.
- **Lifecycle moves re-satisfy the target skeleton** in the same change:
  proposed → implemented rewrites `## Proposal` into present-tense
  `## Decision` and folds acceptance criteria and risks into consequences;
  proposed → rejected only adds the verdict.
- **Cross-reference with relative markdown links**, never bare prose — links
  are checked by `verify_md_links`.
- **No central index.** The tree is the inventory; an index rots. When a
  note's future decision value fades, delete it (rejected) or archive it
  frozen under `docs/notes/` — never edit history in place.

Predates this tree and stays in place (inbound links exist):
[ADR-0001 Flutter rewrite](../../docs/adr-0001-flutter-rewrite.md).

Enforcement: `python3 scripts/verify_note_format.py` (part of
`scripts/verify_all.py`); word ceilings per note live in
[scripts/gates_manifest.json](../../scripts/gates_manifest.json).
