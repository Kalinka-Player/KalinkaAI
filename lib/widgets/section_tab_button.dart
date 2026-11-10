import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/click_cursor.dart';

/// PLAYING / QUEUE's tab treatment, shared with Settings and search.
class SectionTabButton extends StatelessWidget {
  static const spacing = 8.0;
  static const horizontalPadding = 8.0;
  static const _badgeSize = 7.8;

  final String label;
  final String? semanticLabel;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  final AlignmentGeometry contentAlignment;
  final TextOverflow? overflow;

  /// A status dot at the title's top right. Describe it in [semanticLabel].
  final bool showBadge;

  const SectionTabButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
    this.semanticLabel,
    this.contentAlignment = Alignment.center,
    this.overflow,
    this.showBadge = false,
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
              fit: StackFit.passthrough,
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
                          Flexible(
                            child: Stack(
                              // The dot uses the tab's existing padding,
                              // following the text even when it ellipsizes.
                              clipBehavior: Clip.none,
                              children: [
                                AnimatedDefaultTextStyle(
                                  duration: duration,
                                  curve: Curves.easeOutCubic,
                                  style: KalinkaTextStyles.sectionLabel
                                      .copyWith(
                                        color: selected
                                            ? KalinkaColors.textPrimary
                                            : KalinkaColors.textSecondary,
                                      ),
                                  child: Text(
                                    label.toUpperCase(),
                                    maxLines: 1,
                                    softWrap: false,
                                    textAlign: TextAlign.center,
                                    overflow: overflow,
                                  ),
                                ),
                                if (showBadge)
                                  const Positioned(
                                    top: -5.2,
                                    right: -_badgeSize,
                                    child: DecoratedBox(
                                      key: ValueKey('section-tab-badge'),
                                      decoration: BoxDecoration(
                                        color: KalinkaColors.accent,
                                        shape: BoxShape.circle,
                                      ),
                                      child: SizedBox(
                                        width: _badgeSize,
                                        height: _badgeSize,
                                      ),
                                    ),
                                  ),
                              ],
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
