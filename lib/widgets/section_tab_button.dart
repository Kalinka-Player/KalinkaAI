import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/click_cursor.dart';

/// PLAYING / QUEUE's tab treatment, shared with Settings and search.
class SectionTabButton extends StatelessWidget {
  static const spacing = 8.0;
  static const horizontalPadding = 8.0;

  final String label;
  final String? semanticLabel;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  final AlignmentGeometry contentAlignment;

  const SectionTabButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
    this.semanticLabel,
    this.contentAlignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: semanticLabel ?? label,
        excludeFromSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            mouseCursor: clickCursor(interactive: !selected),
            hoverColor: KalinkaColors.surfaceInput,
            focusColor: KalinkaColors.surfaceOverlay,
            child: Stack(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 48,
                    minWidth: 48,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: 12,
                    ),
                    child: Align(
                      alignment: contentAlignment,
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (leading != null) ...[
                            leading!,
                            const SizedBox(width: 8),
                          ],
                          AnimatedDefaultTextStyle(
                            duration: duration,
                            curve: Curves.easeOutCubic,
                            style: KalinkaTextStyles.sectionLabel.copyWith(
                              color: selected
                                  ? KalinkaColors.textPrimary
                                  : KalinkaColors.textSecondary,
                            ),
                            child: Text(
                              label.toUpperCase(),
                              maxLines: 1,
                              softWrap: false,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: horizontalPadding,
                  right: horizontalPadding,
                  bottom: 4,
                  child: AnimatedContainer(
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    height: 2,
                    decoration: BoxDecoration(
                      color: selected
                          ? KalinkaColors.accent
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
