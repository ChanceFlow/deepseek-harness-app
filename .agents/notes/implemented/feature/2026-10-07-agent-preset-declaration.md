# Agent Note: Reading an agent preset's declared composition

Status: implemented

## Problem

The roster (`agentPresets/list`) gives a preset's identity, published copy,
whether it is the default, and why it cannot compose a session. It does not
give the *declaration* — the child plugin list the preset actually composes —
and `agentPresets/read` is the endpoint that renders it as entry-list YAML in
the Loader's own dialect (`packages/preset/agent-preset-registry/src/index.ts`
`readDocument` → `AgentPresetDocument {agentPreset, content, name?,
description?}`).

The phone listed the roster and could select a default, but a reader who
wanted to know what a preset *is* — which is exactly what a broken preset
demands — had nowhere to look: `agentPresets/read` was one of the 46 unwired
endpoints, and the settings page's note says presets are composed on the host
and never managed here, so a read-only view of the declaration is the only
honest surface for it.

## Decision

- **`agentPresets/read` joins the registry** and decodes into
  `AgentPresetDocument`; `readAgentPreset(agentPreset)` is the repository
  method, whose refusal (`agent-preset/not-found`) surfaces as a
  `RepositoryFailure`.
- **The roster card gains one read-only affordance.** Its trailing *View*
  button opens the declaration page for that preset; the card's own tap stays
  the default selection, so the two verbs never compete.
- **The page renders the document, not a summary.** The published sentence
  (when there is one) sits above the declaration as selectable monospaced
  text, uncropped and unfurled — a reader comparing two presets needs the text
  itself. The bar carries the published name, falling back to the roster label
  before the read lands.
- **A failed read states itself** (*"the declaration could not be read from
  this host"*) and keeps the roster label in the bar, rather than showing an
  empty card that reads as an empty preset.

## Alternatives considered

- **Select the text into a copyable dialog**: rejected — the document is the
  content; a dialog would cap it and take the selection surface away from the
  page a reader returns to.
- **Fold the declaration into the roster cards inline**: rejected — a
  declaration is a YAML list of arbitrary length, and expanding every card
  would turn the roster into a wall of YAML.
- **Write or copy the composition on the phone**: rejected by the host's own
  contract — preset authoring left the Remote surface, so there is nothing to
  write; the page says as much in its intro.
- **Reuse the roster row's tap for the declaration**: rejected — that tap
  selects the deployment default, and a read-only view must not compete with
  the one verb the row exists for.

## Consequences

One extra read per opened preset, none per roster render. The declaration is
shown exactly as the host renders it, so a `!!js` condition reads as declared
rather than as an evaluated expression — which is the point of the host
serializing it that way. Coverage moves to declared 86 / identical 84 /
missing 44, and `agentPresets/read` leaves the reviewed out-of-scope list in
`docs/spec.md` §4.6.

## Testing

`packages/harness_adapter/test/harness_repository_integration_test.dart` pins
the request field and the decode (identity, copy, YAML content).
`app/test/ui/settings/agent_preset_document_test.dart` covers the rendered
name, sentence and declaration, and the refused read keeping the roster label.
The roster card's affordance rides the existing agent-presets page tests.
