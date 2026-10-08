/// The plan document's detail surface — the phone's answer to the reference's
/// plan pane.
///
/// The pin keeps the document out of its plan card: the card carries the
/// plan's first line and first paragraph (`PlanReviewPanel.tsx:52-58`) and a
/// `preview.full` link (`PlanCard.tsx:81-82`) opens the whole document in the
/// right sidebar, where `PlanPreview.tsx` renders it as a scrolling page.
/// A phone has one pane, so the document takes a pushed route: the app bar
/// names it, the markdown scrolls, and the review's actions are pinned in the
/// bottom bar. Opening it answers nothing — the pinned action is the only thing
/// that settles the review (`ui-user-questions/README.md:78`).
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/timeline_item.dart' show QuestionAnswer;
import 'package:flutter/material.dart';

import 'card_detail.dart';
import 'chat_ui_state.dart';
import 'markdown/markdown_text.dart';

/// Opens [args]'s document one surface deeper.
///
/// The answers ride the same [onAction] the card uses, so a decision taken
/// from the route settles the same request; the surface pops itself once the
/// action is dispatched, which restores the transcript's place with no reset.
Future<void> showPlanDetail(
  BuildContext context, {
  required PlanDetailArgs args,
  required String approveLabel,
  required String? declineLabel,
  required void Function(ChatAction) onAction,
}) => pushCardDetail<void>(
  context,
  name: 'card-detail:plan',
  args: args,
  builder: (context) => PlanDetailSurface(
    args: args,
    approveLabel: approveLabel,
    declineLabel: declineLabel,
    onAction: onAction,
  ),
);

/// The plan document as a full-screen surface.
class PlanDetailSurface extends StatelessWidget {
  const PlanDetailSurface({
    required this.args,
    required this.approveLabel,
    required this.declineLabel,
    required this.onAction,
    super.key,
  });

  /// The typed route payload: the document and the identity the pinned action
  /// answers.
  final PlanDetailArgs args;

  /// The approve option's own label (the wire string the host expects).
  final String approveLabel;

  /// The single alternative option, when the review carries one.
  final String? declineLabel;

  final void Function(ChatAction) onAction;

  void _decide(BuildContext context, String label) {
    onAction(
      AnswerQuestionAction(
        requestId: args.requestId,
        answers: [
          QuestionAnswer(questionId: args.questionId, selectedOptions: [label]),
        ],
      ),
    );
    Navigator.of(context).pop();
  }

  void _discuss(BuildContext context) {
    onAction(DismissQuestionAction(requestId: args.requestId));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final decline = declineLabel;
    return CardDetailScaffold(
      title: args.title,
      subtitle: args.description.isEmpty ? null : args.description,
      actions: <Widget>[
        TextButton(
          onPressed: () => _discuss(context),
          style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.edit_outlined, size: 14),
              const SizedBox(width: 6),
              Text(l10n.planDiscuss),
            ],
          ),
        ),
        if (decline != null)
          OutlinedButton(
            onPressed: () => _decide(context, decline),
            child: Text(l10n.planDecline),
          ),
        FilledButton(
          onPressed: () => _decide(context, approveLabel),
          child: Text(l10n.planApprove),
        ),
      ],
      // The document is a reading surface: the app's own markdown renderer
      // draws it, the same one the transcript uses, so a plan reads the same
      // in both places.
      child: MarkdownText(text: args.plan),
    );
  }
}
