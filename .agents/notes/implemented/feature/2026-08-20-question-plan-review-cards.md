# Agent Note: Question and plan-review cards (web ui-user-questions parity)

Status: implemented

## Problem

The LLM's `ask_user_question` feedback rendered as a plain stacked column:
every question at once with flat toggle buttons, a plain single-line detail,
and a bottom Answer button. Plan reviews (`plan-review` intent) were a bare
header plus a `Wrap` of buttons over an inset markdown box. Neither matched
the web client's composer takeover, so multi-question batches were hard to
scan and plan approval read as an afterthought rather than a decision.

## Decision

Port the reference `ui-user-questions` presentation (card + one-question
pager for the generic flow; waiting-approval card for plan review) onto the
existing question wire channel:

- **Routing mirrors the web `planReviewOf`.** A request is a plan-review card
  only when a single question declares `intent.kind == 'plan-review'`, carries
  the plan as its `detail`, and stays a binary single choice (≤2 options, the
  intent's `approve` present, never multi-select). Anything else keeps the
  generic flow — same narrowing as the reference, so a request the card cannot
  answer stays answerable.
- **Generic flow = `_QuestionCard`** (web QuestionComposer): rounded input-major
  card with an eyebrow/title header and a dismiss (✕) button; the detail as
  markdown; option rows with a leading number chip (single-select) or checkbox
  (multi-select), a `（推荐）`/`(recommended)` badge, and descriptions; an inline
  custom-answer row (optionless questions get a free-form textarea); and a
  footer with prev/next pager, `1 / N` progress, validation feedback, and
  Skip / Next / Submit. One question shows at a time; drafts stay keyed by
  question id; single-select choose auto-advances like the web.
- **Plan review = `_PlanReviewCard`** (web PlanReviewPanel): warn-tinted strip
  (dot + "计划待审"), the plan as the whole markdown body, and a right-aligned
  action row — "去聊天里说" (dismiss), "拒绝" (decline), "确认执行" (approve).
  The buttons answer with the asker's own option labels (`intent.approve` and
  the other offered option); the actions carry localised copy.
- **Dismiss is a wire verb.** `DismissQuestionAction` → repository
  `cancelQuestions` responds with the `cancelled` error envelope on the
  question RPC, resolving the asker's call as cancelled (the web
  `PendingQuestion.cancel()` path; the host folds `question/resolved` with
  outcome `cancelled`).
- **Colors ride native M3 roles.** The option-number chip uses
  `surfaceContainerHighest`, the checkbox stroke `outlineVariant` with an
  `onSurface` check, and the optionless question textarea
  `surfaceContainerHigh` (post-2026-08-21 native-M3 removal; no custom
  tokens). Copy lives in ARB:
  `questionPrev/Next/Cancel/Recommended/ErrorIncomplete/
  ErrorUnanswered/Submit/SubmitNext` and `planApprove/Decline/Discuss`.

## Alternatives considered

- **Keep the stacked layout, only restyle buttons/cards**: rejected — the
  user chose the web pager; one question at a time keeps long batches scannable
  and the recommended badge / option numbers readable.
- **Route plan review per-question inside the generic card**: rejected —
  a mixed batch would render a decision card mid-quiz; the web's whole-request
  narrowing is the settled contract.
- **Dismiss as a no-op / only visual**: rejected — the host resolves the
  asker's tool call; leaving it unanswered would strand the agent turn.

## Consequences

- Widget tests drive the new surfaces through the real screen entry path:
  single-select submit, multi-select + custom preservation, recommended badge,
  optionless textarea, batch dismiss, plan approve/decline/discuss, and the
  non-binary-batch fallback to the generic card.
- Controller + adapter tests cover the dismiss wire path: the action reaches
  `cancelQuestions` and the response carries `ok: false` with `code:
  'cancelled'`.
- The old per-question "Skipped / Answer instead" UI is gone; skip is now the
  web's per-page skip that records an empty-answer draft and advances.
