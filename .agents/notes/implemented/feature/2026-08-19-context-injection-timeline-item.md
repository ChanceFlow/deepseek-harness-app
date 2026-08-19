# Agent Note: Non-user `user/message` sources render as context injections

Status: implemented

## Problem

`user/message` events carry a durable `source` whose `kind` names the
producer. Only `kind: 'user'` is a human prompt; every other kind — goal
snapshots, skill invocations, workspace instruction files, plugin
catalogs, cross-session recalls — is context injected into model history.
The timeline reducer treated all of them as user chat bubbles, so the
mobile transcript showed machine-injected material as if the human had
typed it.

## Decision

The reducer ports the web classifier verbatim
(`reference/deepseek-harness/packages/client/ui-conversation/src/client/conversation-nodes/message.ts`):
a `user/message` whose `source.kind` is not `user` folds into a new
`TimelineContextInjection` domain item carrying the collected content, the
producer label, the recall flag, and a notice-form summary. The label
projection ports
`.../client/runtime/src/client/sessions/context-provenance.ts`:
`session-reference` → joined reference labels (recall role),
`agent-instructions` → joined change paths, `plugin` → plugin id,
`skill-invocation` → skill name, any other readable kind → the bare kind,
no readable kind → null. A `notice` form's `summary` rides the row
collapsed. The UI row (`ContextInjectionRow` in
`flutter/app/lib/ui/chat/chat_screen.dart`) uses the Tool-call disclosure
chrome: header "Context injection" (or "Recall"), dot separator, producer
label, summary; the body expands to the injected text. A missing source
kind classifies as context, matching the web projection's documented
degrade for merge-extensible sources; the plain user bubble requires
`kind: 'user'` exactly.

## Alternatives considered

- **Filter injections out entirely** (render nothing): rejected — the web
  keeps the material visible behind a disclosure because it is
  model-visible and readers need to know it entered the history.
- **Reuse `TimelineMessage` with a presentation flag**: rejected — the
  sealed item union is the placement boundary between the adapter and the
  UI; a distinct variant fails compilation at every exhaustive switch,
  which is the repo's defensive contract for closed unions.
- **Map only the known kinds, default to user**: rejected — the web's
  documented default for an unknown producer is context labeled by its own
  durable kind; defaulting to user reintroduces the bug for new producers.

## Consequences

Injected goal/skill/instruction/catalog/recall material no longer
impersonates user prompts on mobile. Existing reducer fixtures gained the
wire-required `source` field (`createUserMessage` always writes it). The
subagent timeline's summary view shows context injections as one-line
`◇` rows. Auto-scroll's trailing-user force-scroll keys on
`TimelineMessage` with the user role, so injections never trigger it.
