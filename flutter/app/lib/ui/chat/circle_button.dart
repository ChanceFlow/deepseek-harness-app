/// Composer circle trigger — the web InputBar control family (`.add`):
/// a 28px circle on the selector fill whose hover swaps to the solid
/// interactive fill. The 40px tap target around the 28px visual keeps
/// the control thumb-sized on touch screens (the web's 28px target is
/// mouse-oriented).
library;

import 'package:flutter/material.dart';

import '../theme/deepsuite_extension.dart';

class DsCircleButton extends StatefulWidget {
  const DsCircleButton({
    super.key,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<DsCircleButton> createState() => _DsCircleButtonState();
}

class _DsCircleButtonState extends State<DsCircleButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Opacity(
          opacity: widget.enabled ? 1 : 0.5,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.enabled ? widget.onTap : null,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _hovering
                          ? ds.interactiveBgHoverSolid
                          : ds.specificSelector,
                      shape: BoxShape.circle,
                    ),
                    child: Center(child: widget.child),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
