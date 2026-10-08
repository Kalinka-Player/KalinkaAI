import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'floating_search_bar.dart';

/// Collapsed search entry point: a floating circular button in the bottom-right
/// of the main screen, sitting a little above the mini-player. A tap target
/// only — no field, no
/// keyboard — that opens the full-screen search session. It pops (scales down
/// with a little spring) on press for tactile feedback.
class SearchDock extends StatefulWidget {
  final VoidCallback onTap;

  /// Apply the bottom safe-area inset. False on phone (the mini-player below
  /// owns it); true on tablet, where the button is the bottom-most element.
  final bool bottomSafeArea;

  /// Key placed on the button itself (not the full-width strip) so the coach
  /// mark can spotlight just the floating button.
  final Key? buttonKey;

  const SearchDock({
    super.key,
    required this.onTap,
    this.bottomSafeArea = false,
    this.buttonKey,
  });

  @override
  State<SearchDock> createState() => _SearchDockState();
}

class _SearchDockState extends State<SearchDock> {
  bool _pressed = false;
  bool _hovering = false;

  void _setPressed(bool value) {
    if (value == _pressed) return;
    setState(() => _pressed = value);
  }

  void _setHovering(bool value) {
    if (value == _hovering) return;
    setState(() => _hovering = value);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: widget.bottomSafeArea,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 16, 16),
        child: Align(
          alignment: Alignment.bottomRight,
          child: Semantics(
            label: 'Search music',
            hint: 'Opens the search screen',
            button: true,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => _setHovering(true),
              onExit: (_) => _setHovering(false),
              child: GestureDetector(
                // Scale on touch-down so the press shows at once; the tap
                // itself opens search on release.
                onTapDown: (_) => _setPressed(true),
                onTapUp: (_) => _setPressed(false),
                onTapCancel: () => _setPressed(false),
                onTap: widget.onTap,
                behavior: HitTestBehavior.opaque,
                // Press dips it; a pointer hover lifts it a touch. Combined so a
                // press mid-hover still reads as a press.
                child: AnimatedScale(
                  scale: _pressed
                      ? 0.88
                      : _hovering
                      ? 1.06
                      : 1.0,
                  duration: const Duration(milliseconds: 130),
                  curve: Curves.easeOutBack,
                  child: AnimatedContainer(
                    key: widget.buttonKey,
                    duration: const Duration(milliseconds: 130),
                    curve: Curves.easeOut,
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: KalinkaColors.accent,
                      shape: BoxShape.circle,
                      // Hover draws a bright ring so the button reads as the
                      // primary target under a cursor (desktop).
                      border: _hovering
                          ? Border.all(
                              color: KalinkaColors.textPrimary,
                              width: 2,
                            )
                          : null,
                      boxShadow: FloatingSearchBar.pillShadow,
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      size: 22,
                      color: KalinkaColors.textPrimary,
                    ),
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
