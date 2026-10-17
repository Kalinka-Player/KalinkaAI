import 'package:flutter/material.dart';

import '../utils/click_cursor.dart';

/// A tint laid *over* a control rather than a ground laid under it, so one
/// that paints its own — a bordered tile, a row already marked as chosen —
/// keeps what it had.
const _kHovered = Color(0x0DFFFFFF);
const _kPressed = Color(0x1AFFFFFF);

/// The same lift for a Material control, which runs its own overlay: pass it
/// as an [InkWell]'s `overlayColor`. One that owns its gestures instead wraps
/// itself in [TapHighlight].
final WidgetStateProperty<Color?> kalinkaOverlay =
    WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) return _kPressed;
      if (states.contains(WidgetState.hovered)) return _kHovered;
      return null;
    });

/// Round icon actions with the same pointer highlight as other Kalinka controls.
/// Leave keyboard focus to IconButton's native focus highlight: a menu may
/// focus its anchor after a touch without needing a persistent focus border.
final kalinkaIconButtonStyle = ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
  padding: const WidgetStatePropertyAll(EdgeInsets.all(12)),
  shape: const WidgetStatePropertyAll(CircleBorder()),
  overlayColor: kalinkaOverlay,
);

/// Makes a row answer the pointer: the click cursor where there is somewhere
/// to go, a lift under the pointer, and a stronger one while it is held.
///
/// Owns the tap, so the child brings only its looks. A child that draws its
/// own ground keeps it — the lift goes on top. Give [borderRadius] where the
/// control has corners of its own, or the tint will square them off, and
/// [inset] where the row runs wider than the mark should.
class TapHighlight extends StatefulWidget {
  final Widget child;

  /// What a tap does. Null leaves the row inert: no cursor, no lift, and no
  /// tap falling through to whatever is behind it.
  final VoidCallback? onTap;

  final BorderRadius? borderRadius;

  /// How far in from its own edges the mark stops. A full-bleed row keeps its
  /// whole width tappable but marks only as wide as the rule between rows, so
  /// the two line up; a control already inset by its sheet takes none.
  final double inset;

  const TapHighlight({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius,
    this.inset = 0,
  });

  @override
  State<TapHighlight> createState() => _TapHighlightState();
}

class _TapHighlightState extends State<TapHighlight> {
  bool _hovering = false;
  bool _pressed = false;

  void _hover(bool value) {
    if (value != _hovering) setState(() => _hovering = value);
  }

  void _press(bool value) {
    if (value != _pressed) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.onTap != null;
    final tint = !live
        ? null
        : _pressed
        ? _kPressed
        : _hovering
        ? _kHovered
        : null;

    return MouseRegion(
      cursor: clickCursor(interactive: live),
      onEnter: (_) => _hover(true),
      onExit: (_) => _hover(false),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: live ? (_) => _press(true) : null,
        onTapUp: live ? (_) => _press(false) : null,
        onTapCancel: live ? () => _press(false) : null,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            widget.child,
            Positioned(
              left: widget.inset,
              right: widget.inset,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: widget.borderRadius,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
