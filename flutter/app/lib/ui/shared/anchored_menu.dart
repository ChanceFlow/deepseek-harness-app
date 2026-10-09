/// The pin's menu as a true popover: an overlay card placed from its trigger's
/// rect, with no scrim and no route.
///
/// The reference's dropdown is a portaled list positioned from the anchor rect
/// (`ui-primitives/Menu.tsx:131-142`: portal mode is "fixed-positioned from the
/// anchor rect (follows movement and resizing while open)"), placed by the
/// shared hook (`useAnchoredPosition.ts:39-120`): `left = align == 'end' ?
/// rect.right - width : rect.left`, `top = side == 'top' ? rect.top - gap -
/// height : rect.bottom + gap`, clamped to `margin` against every viewport
/// edge. It is dismissed by an outside pointerdown
/// (`useDismissOnOutsidePointer.ts:23-33`), Escape, or a window blur that moved
/// focus away (`Menu.tsx:131-142`). No mask exists anywhere in the family:
/// `MenuSurface.module.css` carries only the surface material.
///
/// This is that shape on a phone. The card is an [OverlayPortal] child, so no
/// route and no barrier exist between the reader and their content: opening a
/// menu neither dims the page nor moves its scroll or selection. The card is
/// [MenuMaterial] — the construction [showMenuSheet] draws — so a seat that
/// migrates here keeps the material it already had, and [showMenuSheet] stays
/// the opener for the seats that have not migrated yet.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';
import 'menu_material.dart';

/// Which anchor edge the card hangs from (`useAnchoredPosition` `side`).
enum MenuSide { top, bottom }

/// Which anchor edge the card lines up with (`useAnchoredPosition` `align`).
enum MenuAlign { start, end }

/// One menu as an anchored popover: [trigger] opens it, [card] is the surface.
///
/// The state is owned here (the pin's `Menu` is owner-controlled; a phone seat
/// owns its own open state), and [card] receives the `close` verb so a row can
/// dismiss the menu the way `onClose` does in the pin.
class AnchoredMenu extends StatefulWidget {
  const AnchoredMenu({
    required this.trigger,
    required this.card,
    super.key,
    this.side = MenuSide.bottom,
    this.align = MenuAlign.start,
    this.gap = 4,
    this.margin = 12,
    this.maxHeight,
    this.minWidth = 144,
    this.maxWidth = 360,
    this.cardKey,
    this.semanticLabel,
    this.canOpen = true,
  });

  /// The trigger: told whether the card is open (the way the pin's `data-open`
  /// trigger mirrors it) and handed the toggle its own press calls.
  final Widget Function(BuildContext context, bool open, VoidCallback toggle)
  trigger;

  /// The card's content. [close] dismisses it; the card is wrapped in the menu
  /// material, so a builder contributes rows only.
  final Widget Function(BuildContext context, VoidCallback close) card;

  final MenuSide side;
  final MenuAlign align;

  /// Distance kept between the anchor edge [side] names and the card
  /// (`useAnchoredPosition` `gap`).
  final double gap;

  /// Distance kept between the card and each viewport edge (`margin`).
  final double margin;

  /// The card's height ceiling; null lets the content decide.
  final double? maxHeight;

  /// The menu card's width band — the design's outer card widths including the
  /// pad (`Menu.module.css:9-34`: `min-width: 144px`, `max-width: 360px`).
  final double minWidth;
  final double maxWidth;

  /// The card's own key, for a test that reads the material.
  final Key? cardKey;

  /// The card's accessible name, when the seat has one to state.
  final String? semanticLabel;

  /// Whether the seat can be open at all. The pin closes a panel whose fact
  /// went away while it stood ("close the now-unavailable panel instead of
  /// preserving stale UI", `ContextMeter.tsx:74-77`); this does the same, and
  /// a trigger whose fact is absent cannot open one.
  final bool canOpen;

  @override
  State<AnchoredMenu> createState() => _AnchoredMenuState();
}

class _AnchoredMenuState extends State<AnchoredMenu>
    with WidgetsBindingObserver {
  final GlobalKey _anchorKey = GlobalKey();
  final OverlayPortalController _portal = OverlayPortalController();

  bool _open = false;

  /// The anchor's rect as last measured between frames. The card is placed from
  /// this, and refreshed after every frame while the menu stands: the pin
  /// re-reads the anchor "on open, each animation frame, and scroll/resize"
  /// (`Menu.tsx:154-160`), because a viewport change moves the trigger without
  /// rebuilding the portaled card.
  Rect? _anchor;

  /// Whether a post-frame measurement is already queued.
  bool _measuring = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _toggle() {
    if (!widget.canOpen && !_open) return;
    setState(() => _open = !_open);
    if (_open) {
      _portal.show();
    } else {
      _portal.hide();
    }
  }

  void _close() {
    if (!_open) return;
    _portal.hide();
    setState(() => _open = false);
    _anchor = null;
  }

  @override
  void didUpdateWidget(covariant AnchoredMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.canOpen && _open) {
      // The fact the card stated is gone: close it rather than render stale
      // UI from the next build.
      _portal.hide();
      _open = false;
    }
  }

  /// A window blur closes the menu — the pin's third dismissal, documented as
  /// "a window blur that moved focus into an iframe (the only signal a
  /// pointerdown inside a cross-origin iframe leaves)" (`Menu.tsx:131-142`).
  /// On a phone the same fact is the app leaving the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _close();
  }

  /// The system back press closes an open menu instead of popping the screen
  /// behind it. A popover owns no route, so the modal sheet's back-dismissal
  /// has to be taken here to keep the behaviour a reader had.
  @override
  Future<bool> didPopRoute() async {
    if (!_open) return false;
    _close();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _overlay,
      child: KeyedSubtree(
        key: _anchorKey,
        child: widget.trigger(context, _open, _toggle),
      ),
    );
  }

  /// The anchor's rect, measured between frames — a layout-time read of
  /// another render object's transform is not allowed (`localToGlobal` walks
  /// ancestors that are mid-layout), so the card cannot ask for it inside the
  /// placement delegate.
  Rect? _measureAnchor() {
    final RenderObject? render = _anchorKey.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return null;
    return render.localToGlobal(Offset.zero) & render.size;
  }

  /// Watch the anchor while the menu stands. Queued from the overlay's build,
  /// so the frame after any movement — a rotation, a keyboard inset, a
  /// scroll — re-places the card.
  void _watchAnchor() {
    if (_measuring) return;
    _measuring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measuring = false;
      if (!mounted || !_open) return;
      final Rect? measured = _measureAnchor();
      if (measured != null && measured != _anchor) {
        setState(() => _anchor = measured);
      }
      _watchAnchor();
    });
  }

  Widget _overlay(BuildContext context) {
    _watchAnchor();
    final Rect? anchor = _anchor ?? _measureAnchor();
    return Positioned.fill(
      child: Stack(
        children: <Widget>[
          // The outside tap: the popover's dismissal, and the only thing
          // between the card and the page. It paints nothing — the pin's menu
          // has no mask (`MenuSurface.module.css`) — and it is opaque so the
          // tap cannot reach the reader's content underneath.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned.fill(child: _positioned(context, anchor)),
        ],
      ),
    );
  }

  Widget _positioned(BuildContext context, Rect? anchor) {
    return CustomSingleChildLayout(
      delegate: _MenuPlacementDelegate(
        anchor: anchor,
        side: widget.side,
        align: widget.align,
        gap: widget.gap,
        margin: widget.margin,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: widget.minWidth,
          maxWidth: widget.maxWidth,
          maxHeight: widget.maxHeight ?? double.infinity,
        ),
        child: Semantics(
          label: widget.semanticLabel,
          container: true,
          child: MenuMaterial(
            key: widget.cardKey,
            // `--dsw-radius-lg`, the menu surface's own corner
            // (`MenuSurface.module.css:3-5`).
            borderRadius: BorderRadius.circular(kRadiusLg),
            padding: const EdgeInsets.all(4),
            // `--dsw-elevation-prominent` with the menu's `border-l1` stroke
            // rebound (`Menu.module.css:16-18`), on an outer box so the clip
            // cannot eat the ring.
            shadows: DshElevation.prominent(
              Theme.of(context).colorScheme,
              stroke: Theme.of(context).colorScheme.borderL1,
            ),
            border: false,
            child: _dismissible(context),
          ),
        ),
      ),
    );
  }

  /// Escape, the pin's second dismissal, plus the focus the key needs.
  Widget _dismissible(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Focus(autofocus: true, child: widget.card(context, _close)),
    );
  }
}

/// Places the card from its anchor's rect, clamped inside the viewport the way
/// `useAnchoredPosition.ts:39-120` does.
class _MenuPlacementDelegate extends SingleChildLayoutDelegate {
  _MenuPlacementDelegate({
    required this.anchor,
    required this.side,
    required this.align,
    required this.gap,
    required this.margin,
  });

  /// The trigger's rect, in the overlay's coordinate space, or null before the
  /// trigger has been laid out (the card then waits at the top margin for the
  /// next frame's measurement).
  final Rect? anchor;
  final MenuSide side;
  final MenuAlign align;
  final double gap;
  final double margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: (constraints.maxWidth - margin * 2).clamp(
        0.0,
        constraints.maxWidth,
      ),
      maxHeight: constraints.maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final Rect anchor = this.anchor ?? Rect.zero;
    final double left = align == MenuAlign.end
        ? anchor.right - childSize.width
        : anchor.left;
    final double top = side == MenuSide.top
        ? anchor.top - gap - childSize.height
        : anchor.bottom + gap;
    final double maxLeft = size.width - childSize.width - margin;
    final double maxTop = size.height - childSize.height - margin;
    return Offset(
      left.clamp(margin, maxLeft < margin ? margin : maxLeft),
      top.clamp(margin, maxTop < margin ? margin : maxTop),
    );
  }

  @override
  bool shouldRelayout(_MenuPlacementDelegate oldDelegate) =>
      anchor != oldDelegate.anchor ||
      side != oldDelegate.side ||
      align != oldDelegate.align ||
      gap != oldDelegate.gap ||
      margin != oldDelegate.margin;
}
