import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../keyboard/ink_focus_outline.dart';
import '../modifier_click.dart';

/// A row's or a cover's own control: [icon] in a 32dp grey circle, within a
/// 44×48 target. Grey: a shortcut, not the screen's one decision. Hover warms
/// the circle so it reads as its own control rather than as part of what it
/// sits on.
class RowCircleButton extends StatefulWidget {
  /// What a tap does, told to a screen reader.
  final String label;
  final IconData icon;

  /// Kept while [busy], so the click never falls through to what the button
  /// sits on.
  final VoidCallback onTap;

  /// Its last tap is still being answered, so the pointer does not warm it.
  final bool busy;
  final FocusNode? focusNode;

  const RowCircleButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.busy = false,
    this.focusNode,
  });

  @override
  State<RowCircleButton> createState() => _RowCircleButtonState();
}

class _RowCircleButtonState extends State<RowCircleButton> {
  bool _hovering = false;

  void _setHover(bool value) {
    if (value == _hovering) return;
    setState(() => _hovering = value);
  }

  @override
  Widget build(BuildContext context) {
    final hot = _hovering && !widget.busy;

    return ClickAtOnce(
      child: MergeSemantics(
        child: Semantics(
          button: true,
          label: widget.label,
          child: SizedBox(
            width: 44,
            height: 48,
            child: Center(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  focusNode: widget.focusNode,
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  customBorder: const CircleBorder(),
                  onTap: widget.onTap,
                  onHover: _setHover,
                  focusColor: KalinkaColors.surfaceOverlay,
                  child: InkFocusOutline(
                    shape: const CircleBorder(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hot
                            ? KalinkaColors.surfaceOverlay
                            : KalinkaColors.surfaceElevated,
                        border: Border.all(
                          color: hot
                              ? KalinkaColors.textMuted
                              : KalinkaColors.borderDefault,
                        ),
                      ),
                      child: Icon(
                        widget.icon,
                        size: 18,
                        color: KalinkaColors.textPrimary,
                      ),
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
