# Prose standard: contracts, not reasoning transcripts

Every future agent session reads this repo's prose cold. A contract is
actionable in that situation; a reasoning transcript spends context and
teaches nothing stable. This standard governs `///` doc comments, docs,
commit messages, and user-visible strings.

## State complete contracts

Before editing any passage, identify its propositions and keep each relevant
one: actor and action; condition, timing, ordering; modality
(must/may/never); negative guarantees and exceptions; ownership, side
effects, failure modes. Then cut adjectives, repetition, and narration — a
smaller word count that drops a failure mode is a defect, not an improvement.

## Rules

- **Document current state, never change history.** No
  "previously/now/no longer/we used to/renamed" in durable prose. Name the
  live mechanism; the story lives in a decision record
  ([`.agents/notes/`](../.agents/notes/README.md)) and gets one link.
- **No reasoning transcripts.** Delete control-flow narration, review
  history, and rejected-local-alternative discussions from comments and docs;
  keep the resulting contract.
- **Concrete terms over metaphors.** Before writing "shape", "surface",
  "boundary", ask whether the exact noun (response fields, DTO decoder,
  WebSocket frames, the import gate) names the subject better.
- **One physical line per paragraph.** Soft-wrap in the editor; keep diffs
  and grep minimal. Code blocks, tables, and lists keep their formatting.
- **Emphasis is budgeted.** Bold marks only the clause that changes behavior;
  emphasis everywhere means emphasis nowhere.
- **Address the agent as the reader.** Name the command, the file, the
  failure. "Be careful with X" is not a rule; "run `verify_all.py docs`
  before committing doc changes; it rejects dead links" is.
- **One home per fact.** Standing orders → [AGENTS.md](../AGENTS.md);
  module boundaries → [README](../README.md#module-boundaries); wire contract
  and coverage → [spec.md](spec.md); rationale → decision records;
  procedures → skills. Everywhere else links.

## Slop checklist

Audit any document against this before accepting it:

- The same rule stated in more than one home — grep a distinctive phrase;
  keep one home, link the rest.
- Narrated history or war stories; PR numbers in durable prose.
- Implementation-status annotations ("done!", "future:") — status rots; the
  tree and git carry it.
- Hand-restated inventories (file, package, or test lists) that the
  filesystem or a generator already owns.
- Paragraph walls carrying several rules — split or demote to the owning home.
- Spec-speak in records of shipped decisions: "should", "shall", migration
  plans — an implemented record describes what *is*.

## Enforcement

Mechanical parts are gates: markdown link resolution and word budgets run in
`python3 scripts/verify_all.py docs`. The semantic parts — completeness,
accuracy, placement — are covered by review applying this checklist.
