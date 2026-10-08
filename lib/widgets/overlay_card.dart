import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'hover_text_action.dart';

/// The chrome shared by the surfaces that open over the title bar — smart
/// search and search-and-filters.
///
/// One implementation rather than two that resemble each other: these cards
/// sit in the same place, are dismissed the same way, and are read as the same
/// kind of thing, so the fill, the corner, the border and the lift are defined
/// once here.
class KalinkaOverlayCard extends StatelessWidget {
  final Widget child;

  /// Vertical space the card may occupy before its own body must scroll.
  /// Unbounded when null.
  final double? maxHeight;

  const KalinkaOverlayCard({super.key, required this.child, this.maxHeight});

  @override
  Widget build(BuildContext context) {
    return TextFieldTapRegion(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          constraints: maxHeight == null
              ? null
              : BoxConstraints(maxHeight: maxHeight!),
          decoration: BoxDecoration(
            color: KalinkaColors.surfaceRaised,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: KalinkaColors.borderDefault, width: 1),
            // Elevation so the card lifts off the fading scrim.
            boxShadow: const [
              BoxShadow(
                color: Color(0xB3000000),
                offset: Offset(0, 12),
                blurRadius: 40,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}

/// An overlay card's title row: an optional accent mark, the card's name in
/// mono caps, an optional textual action, and the dismiss button.
class OverlayCardHeader extends StatelessWidget {
  /// Named in mono caps — what this card is.
  final String title;

  /// Accent glyph in a tinted tile, leading the title. Omitted where the
  /// card's name is enough.
  final IconData? icon;

  /// A textual action sitting before the dismiss button, such as Reset.
  final Widget? action;

  final VoidCallback onClose;

  /// What the dismiss button announces, e.g. 'Close filters'.
  final String closeLabel;

  const OverlayCardHeader({
    super.key,
    required this.title,
    required this.onClose,
    required this.closeLabel,
    this.icon,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
      child: Row(
        children: [
          if (icon != null) ...[
            _AccentMark(icon: icon!),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              title,
              style: KalinkaFonts.mono(
                fontSize: KalinkaTypography.baseSize + 2,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.0,
                color: KalinkaColors.textPrimary,
              ),
            ),
          ),
          ?action,
          OverlayCloseButton(onTap: onClose, label: closeLabel),
        ],
      ),
    );
  }
}

/// The card's identity glyph — an accent-tinted tile, the same shape language
/// as the rows inside it.
class _AccentMark extends StatelessWidget {
  final IconData icon;

  const _AccentMark({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: KalinkaColors.accentSubtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KalinkaColors.accentBorder),
      ),
      child: Center(
        child: Icon(icon, size: 17, color: KalinkaColors.accentBright),
      ),
    );
  }
}

/// Dismisses an overlay card. Its ring lightens under the pointer, the same
/// cue the pills and the title-bar button use.
class OverlayCloseButton extends StatefulWidget {
  final VoidCallback onTap;
  final String label;

  const OverlayCloseButton({
    super.key,
    required this.onTap,
    required this.label,
  });

  @override
  State<OverlayCloseButton> createState() => _OverlayCloseButtonState();
}

class _OverlayCloseButtonState extends State<OverlayCloseButton> {
  bool _hovering = false;

  void _setHovering(bool value) {
    if (value == _hovering) return;
    setState(() => _hovering = value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      button: true,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovering(true),
        onExit: (_) => _setHovering(false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOut,
            width: 34,
            height: 34,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hovering
                  ? KalinkaColors.surfaceOverlay
                  : Colors.transparent,
              border: Border.all(
                color: _hovering
                    ? KalinkaColors.textMuted
                    : KalinkaColors.borderDefault,
              ),
            ),
            child: const Icon(
              Icons.close_rounded,
              size: 18,
              color: KalinkaColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// An overlay card's textual action (Reset, Clear). Crimson inside the card,
/// where there is nothing tinted for it to compete with.
class OverlayTextAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const OverlayTextAction({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return HoverTextAction(
      label: label,
      onTap: onTap,
      color: KalinkaColors.accentTint,
      hoverColor: KalinkaColors.accentBright,
      fontSize: KalinkaTypography.baseSize + 1,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
}
