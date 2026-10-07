# Agent Note: The input dock's height budget, and the decision card's action row

Status: implemented

## Problem

A question or plan-review card owns the composer dock while it waits, and its
answer buttons are the only way forward. Both cards capped their scrollable
body against the raw screen (`MediaQuery.sizeOf(context).height * 0.45`) while
the dock itself was unbounded whenever the keyboard was closed, and the panel
the dock lives in is shorter than the screen: the app bar takes 56dp, the root
navigation bar ~80dp, and the system insets the rest. On a phone whose panel
falls under roughly 660dp — a 5" device, a landscape window, any panel with a
keyboard open — the card grew past the panel's bottom edge. The panel's Column
then reported `RenderFlex overflowed by 43 pixels on the bottom`, the action
row was painted under the tab bar, and the taps that should have answered the
question landed on the bar instead. The report was "同意或者继续讨论我都点不到".

## Decision

- **The dock's budget is measured from the panel, not the screen**
  (`_InputDock` + `_dockBudgetShare`): the chat panel wraps its body in a
  `LayoutBuilder` and hands the dock `min(clamp(0.62 × panelHeight, 200, 520),
  panelHeight)`. While a decision waits the share rises to 0.78 — answering is
  the only thing that session can do, so the decision seat keeps more room than
  the composer ever needs — and the cap can never exceed the panel it lives in.
- **The dock is always bounded and scrolls internally**, keyboard or not: the
  dock publishes its budget through `DockBudget` (`ui/shared/dock_anchor.dart`)
  and clips at it, so no strip can ever paint below the panel's bottom edge.
- **A decision card sizes its body against that budget**
  (`_decisionBody`): the scrollable plan or option list takes
  `budget - chrome` (the card's own header, answer field, action row), so the
  card as a whole fits the dock and its action row lands at the dock's bottom
  edge, above the tab bar, instead of below it. The historical 45%-of-screen
  cap stays for a bare pump of a card with no dock around it.

## Alternatives considered

- **Keep the 45%-of-screen cap**: rejected — the screen is not the panel; the
  app bar, the tab bar and the insets are all outside the dock's constraints.
- **Pin the actions with `Flexible`** (the dock's last child takes the
  remaining budget, the card's body flexes): rejected — when the card's own
  chrome exceeds the budget the card's Column overflows by the difference
  (measured at 2px on a keyboard-shrunk panel), and a flex child inside the
  dock's scroll view is not legal, so the fallback for that case would be a
  second layout path anyway. Capping the body keeps one path for every height.
- **Open the card as a modal sheet or a full-screen route**: rejected — the
  reference keeps the decision in the input dock, and covering the transcript
  hides the conversation the plan is about.
- **Collapse the transcript while a decision waits**: rejected — the plan
  review asks the reader to judge what the conversation above produced.

## Consequences

On a short panel the plan body shows less at once and scrolls inside the card;
when the card's chrome alone exceeds the budget (a keyboard-shrunk landscape
panel), the dock scrolls and the actions sit just below it rather than under
the tab bar. The transcript keeps at least 22% of the panel while a decision
waits. Nothing in the dock can be painted below the panel's bottom edge any
more, and no strip can push the composer off-panel on a crowded dock.

## Testing

`app/test/ui/chat/decision_dock_test.dart` pumps the real chat screen at the
panel heights that used to fail (a 400dp panel, a 480dp panel with reminder
strips above the card, a 564dp panel with a 300dp keyboard) and asserts no
overflow, that each action's rect stays inside the viewport above the keyboard,
and that pressing the buttons dispatches. All four cases are red before this
change and green after; the existing composer-dock tests in
`chat_screen_test.dart` cover the non-decision dock.
