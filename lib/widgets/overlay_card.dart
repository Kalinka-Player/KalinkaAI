import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'hover_text_action.dart';
import 'kalinka_popover.dart';

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
    final inPopover = KalinkaPopoverContentScope.contains(context);
    // Keep the same wrappers in both presentations. Replacing the subtree on
    // resize loses EditableText's input connection even with a retained focus
    // node and controller.
    return TextFieldTapRegion(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight ?? double.infinity),
          // Keep Container's padding wrapper when the decorated border goes.
          padding: EdgeInsets.zero,
          decoration: inPopover
              ? const BoxDecoration()
              : BoxDecoration(
                  color: KalinkaColors.surfaceDialog,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: KalinkaColors.borderDefault,
                    width: 1,
                  ),
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

/// Shared dismiss button for dialogs, popovers and sheets. The filter card's
/// 34dp ring sits inside a 48dp target, with the same neutral feedback for
/// hover and press and a primary outline for keyboard focus.
class OverlayCloseButton extends StatelessWidget {
  final VoidCallback onTap;
  final String label;

  const OverlayCloseButton({
    super.key,
    required this.onTap,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onTap,
      icon: Icon(Icons.close_rounded, size: 18, semanticLabel: label),
      style: ButtonStyle(
        fixedSize: const WidgetStatePropertyAll(Size.square(34)),
        minimumSize: const WidgetStatePropertyAll(Size.square(34)),
        maximumSize: const WidgetStatePropertyAll(Size.square(34)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: const WidgetStatePropertyAll(CircleBorder()),
        foregroundColor: const WidgetStatePropertyAll(
          KalinkaColors.textPrimary,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.any(
                {
                  WidgetState.hovered,
                  WidgetState.pressed,
                  WidgetState.focused,
                }.contains,
              )
              ? KalinkaColors.surfaceOverlay
              : Colors.transparent,
        ),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return const BorderSide(color: KalinkaColors.textPrimary, width: 2);
          }
          return BorderSide(
            color:
                states.any({WidgetState.hovered, WidgetState.pressed}.contains)
                ? KalinkaColors.textMuted
                : KalinkaColors.borderDefault,
          );
        }),
        animationDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 130),
      ),
    );
  }
}

/// An overlay card's secondary textual action (Reset, Clear). Stay neutral so
/// the primary action is the card's only crimson control.
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
      color: KalinkaColors.textSecondary,
      hoverColor: KalinkaColors.textPrimary,
      fontSize: KalinkaTypography.baseSize + 1,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
}
