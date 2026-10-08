/// The card → detail pattern: every interactive card is one line where it
/// stands, and its content opens one surface deeper.
///
/// The reference is a desktop web app whose cards put their details in a
/// right-hand pane: the plan card's document leaves the card and the sidebar
/// renders it (`ui-plan/src/client/PlanCard.tsx:81-82` opens it;
/// `ui-user-questions/README.md:78` — "the plan plugin opens logged plans from
/// history and unlogged reviews as temporary sidebar previews, and opening a
/// document does not answer or dismiss the review"). A phone has no second
/// pane, so the same content gets a designed surface instead, chosen by the
/// card's own shape:
///
/// - a **content-shaped** card — the plan document, a diff, long output, a
///   delivered file — pushes a full-screen route ([CardDetailScaffold]) whose
///   actions are pinned in the bottom bar, where the thumb already is;
/// - a **decision-shaped** card — an ask, an approval, a few options — opens a
///   large bottom sheet with the options at the bottom
///   ([showCardDetailSheet]), dimming the transcript behind it.
///
/// The card's own row stays one line ([CardDetailRow]): the pin's plan card is
/// a single 60px button (`PlanPreview.module.css` `.card`, :2-19) — a 40px
/// icon seat, a 13/20 title, a 10/16 tertiary description and a trailing open
/// chip. A card that unfolds in place would push the reader's own reading away;
/// the transcript is the surface they are reading, so the detail moves off it.
///
/// The route carries a typed [CardDetailArgs]: a surface restored from the
/// payload rebuilds the same document instead of resetting the card that
/// opened it, and no two panes are ever live on a phone.
library;

import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'process_disclosure.dart' show flatInkOverlay;
import 'tool_row_model.dart' show EditDiffModel;

/// The typed payload a card-detail route carries.
///
/// It is the card's identity plus the content the surface renders — never
/// widget state. A route restored from it rebuilds the same surface, and the
/// card that opened it keeps its place in the transcript.
sealed class CardDetailArgs {
  const CardDetailArgs();

  /// The surface's app-bar title.
  String get title;
}

/// One plan review's submitted document.
final class PlanDetailArgs extends CardDetailArgs {
  const PlanDetailArgs({
    required this.requestId,
    required this.questionId,
    required this.title,
    required this.description,
    required this.plan,
  });

  /// The review request the document belongs to. Opening the document never
  /// answers or dismisses that review (the pin's own rule, in the citation
  /// above), so the payload carries the id only to name the surface.
  final String requestId;

  /// The question the approve label answers ([`QuestionItem.id`], the pin's
  /// `review.id`); the document alone does not answer it, the pinned action
  /// does.
  final String questionId;

  /// The document's first line, extracted the pin's way
  /// (`PlanReviewPanel.tsx:48-51`, `mode: 'first-line'`).
  @override
  final String title;

  /// The document's first paragraph, empty when it is the title itself
  /// (`PlanReviewPanel.tsx:50-51`). The card's own second line.
  final String description;

  /// The whole markdown document.
  final String plan;
}

/// One edit's unified diff.
final class DiffDetailArgs extends CardDetailArgs {
  const DiffDetailArgs({
    required this.path,
    required this.diff,
    required this.title,
  });

  /// The edited path; its basename names the surface and its full value is the
  /// preview's subject.
  final String path;

  final EditDiffModel diff;

  @override
  final String title;
}

/// One delivered file.
final class FileDetailArgs extends CardDetailArgs {
  const FileDetailArgs({
    required this.path,
    required this.title,
    required this.description,
  });

  final String path;

  @override
  final String title;

  /// The model's own description of the file, or the extension when it wrote
  /// none (the pin's `PresentedFileCard`).
  final String description;
}

/// One tool row's whole payload: the diff or the input/output body the row
/// shows a bounded peek of, plus the file it edited when there is one.
final class ToolDetailArgs extends CardDetailArgs {
  const ToolDetailArgs({
    required this.title,
    this.diff,
    this.input,
    this.output,
    this.failed = false,
    this.path,
  });

  /// The tool's own business title (the row's header).
  @override
  final String title;

  /// A replacement/edit call's unified diff, when it has one.
  final EditDiffModel? diff;

  /// The call's arguments, as the row's IN section renders them.
  final String? input;

  /// The settled result text, as the row's OUT section renders it.
  final String? output;

  /// Whether the run failed; the OUT section wears the error tone then.
  final bool failed;

  /// The edited file, when the call names one; it earns the preview seat.
  final String? path;
}

/// The route a content-shaped card pushes.
///
/// [name] identifies the card family on the route (`RouteSettings.name`) and
/// [args] is the typed payload (`RouteSettings.arguments`), so the surface can
/// be recognised and restored without reading widget state.
Route<T> cardDetailRoute<T>({
  required String name,
  required CardDetailArgs args,
  required WidgetBuilder builder,
}) => MaterialPageRoute<T>(
  settings: RouteSettings(name: name, arguments: args),
  builder: builder,
);

/// Pushes a content-shaped card's full-screen detail surface.
Future<T?> pushCardDetail<T>(
  BuildContext context, {
  required String name,
  required CardDetailArgs args,
  required WidgetBuilder builder,
}) =>
    Navigator.of(context)
        .push<T>(cardDetailRoute<T>(name: name, args: args, builder: builder));

/// The full-screen detail surface of a content-shaped card.
///
/// The app bar names the card, the content scrolls — this surface is the only
/// scroller on screen, because the transcript that opened it is behind the
/// route — and the card's actions are pinned in the bottom bar rather than
/// trailing a long document, so the decision is reachable without a scroll to
/// the end.
class CardDetailScaffold extends StatelessWidget {
  const CardDetailScaffold({
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const <Widget>[],
    this.feedback,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 24),
    this.fullBleed = false,
    super.key,
  });

  /// The card's name in the app bar.
  final String title;

  /// A second app-bar line — the card's own summary.
  final String? subtitle;

  /// The document. Vertical scrolling belongs to this surface.
  final Widget child;

  /// The card's actions, pinned in the bottom bar in reading order; the last
  /// entry is the filled seat.
  final List<Widget> actions;

  /// A status line above the actions (a failure, a wait).
  final Widget? feedback;

  /// The content's own inset. A diff or a console draws to the edge and turns
  /// this off with [fullBleed].
  final EdgeInsetsGeometry padding;

  /// Whether the content draws edge to edge.
  final bool fullBleed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitleText = subtitle;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: subtitleText == null
            ? Text(title)
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title),
                  Text(
                    subtitleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DshType.xxxs11.style(color: scheme.labelTertiary),
                  ),
                ],
              ),
      ),
      // The bar owns the bottom inset; the content must not scroll under it.
      body: SafeArea(
        top: false,
        bottom: false,
        child: SingleChildScrollView(
          padding: fullBleed ? EdgeInsets.zero : padding,
          child: child,
        ),
      ),
      bottomNavigationBar: actions.isEmpty && feedback == null
          ? null
          : CardDetailActionBar(actions: actions, feedback: feedback),
    );
  }
}

/// The pinned bottom bar of a detail surface: the chrome tone the app gives
/// every dock, divided from the content by a hairline, carrying the card's
/// actions.
class CardDetailActionBar extends StatelessWidget {
  const CardDetailActionBar({required this.actions, this.feedback, super.key});

  /// The actions in reading order; the last entry is the filled seat.
  final List<Widget> actions;

  /// A status line above the actions.
  final Widget? feedback;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (feedback case final Widget feedback) feedback,
                // A wrap, not a row: three actions and their labels exceed a
                // 360dp phone's width, and wrapping is what keeps the primary
                // seat on screen instead of overflowing.
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One card's collapsed row — the one line the card keeps where it stands.
///
/// It is the pin's plan card (`PlanPreview.module.css` `.card`, :2-19): a 60px
/// button on `bg-layer-2` at the `xl` radius edged by a half-pixel `border-l1`,
/// a 40px icon seat at the `md` radius, the title on the pin's 13/20 step, the
/// description one step under it in `label-tertiary`, and a trailing open chip
/// on `button-floating-fill` edged by `border-l3` (`:15-19`). The row is the
/// card's own seat: it opens the detail surface, and it never unfolds in place.
class CardDetailRow extends StatelessWidget {
  const CardDetailRow({
    required this.icon,
    required this.title,
    required this.onOpen,
    this.summary,
    this.openLabel,
    this.status,
    this.trailing,
    this.semanticLabel,
    this.enabled = true,
    super.key,
  });

  /// The business glyph in the 40px leading seat.
  final IconData icon;

  /// The card's name — one line.
  final String title;

  /// The card's one line of summary; null leaves the title alone on the line.
  final String? summary;

  /// The open chip's label (the pin's `cardOpen`). Null drops the chip.
  final String? openLabel;

  /// A trailing status seat (a count, a state chip) sitting before the chip.
  final Widget? status;

  /// A trailing action seat after the open chip — the dock's primary action,
  /// so a decision stays answerable from the thumb while its detail lives one
  /// surface deeper.
  final Widget? trailing;

  /// What assistive technology announces for the row.
  final String? semanticLabel;

  final bool enabled;

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summaryText = summary;
    final open = openLabel;
    final statusSeat = status;
    final trailingSeat = trailing;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: flatInkOverlay(
        context,
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: enabled ? onOpen : null,
            borderRadius: BorderRadius.circular(kRadiusXl),
            child: Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.bgLayer2,
                borderRadius: BorderRadius.circular(kRadiusXl),
                border: Border.all(color: scheme.borderL1, width: 0.5),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(kRadiusMd),
                      border: Border.all(color: scheme.borderL1, width: 0.5),
                    ),
                    child: Center(
                      child: Icon(
                        icon,
                        size: 20,
                        color: enabled ? scheme.labelSecondary : scheme.outline,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DshType.xsStrong13.style(
                            color: enabled
                                ? scheme.labelPrimary
                                : scheme.labelDimmed,
                          ),
                        ),
                        if (summaryText != null)
                          Text(
                            summaryText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            // The pin's `.cardDescription` is 10/16
                            // (`PlanPreview.module.css:17`); the token layer
                            // carries the named step one size up rather than a
                            // raw 10px size, so the row reads the step.
                            style: DshType.xxxs11.style(
                              color: scheme.labelTertiary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (statusSeat != null) ...[
                    const SizedBox(width: 8),
                    statusSeat,
                  ],
                  if (open != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.buttonFloatingFill,
                        borderRadius: BorderRadius.circular(kRadiusSm),
                        border: Border.all(color: scheme.borderL3, width: 0.5),
                      ),
                      child: Text(
                        open,
                        style: DshType.xxs12.style(
                          color: scheme.labelSecondary,
                        ),
                      ),
                    ),
                  ],
                  if (trailingSeat != null) ...[
                    const SizedBox(width: 8),
                    trailingSeat,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens a decision-shaped card's detail surface: a large sheet on the house
/// menu material, with the options at the bottom and the transcript dimmed
/// behind it.
///
/// The sheet takes most of the screen — a decision is the only thing the
/// reader can do with the session, and the pin's own decision cards are
/// full-width panels — but it keeps the page visible above it, so the
/// conversation the decision belongs to stays in view.
Future<T?> showCardDetailSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double heightShare = 0.8,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    // A transparent background hides Material's sheet surface but not its
    // elevation: the modal route still paints the theme's shadow under the
    // whole sheet, so the panel's own `DshElevation.prominent` ring would sit
    // on a second, heavier shadow.
    elevation: 0,
    sheetAnimationStyle: const AnimationStyle(
      duration: DshMotion.durationMedium,
      curve: DshMotion.curveEmphasized,
      reverseCurve: DshMotion.curveExit,
    ),
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * heightShare,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.bgLayer2,
              borderRadius: BorderRadius.circular(kRadiusPanel),
              boxShadow: DshElevation.prominent(scheme),
            ),
            clipBehavior: Clip.antiAlias,
            child: builder(sheetContext),
          ),
        ),
      );
    },
  );
}
